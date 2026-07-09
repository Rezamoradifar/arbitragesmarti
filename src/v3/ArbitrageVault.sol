// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IConditionalTokens {
    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;
}

/**
 * @title ArbitrageVault
 * @notice Holds the bounded share of pool collateral (capped at 20% by the
 *         main contract, enforced there) allocated for on-chain arbitrage
 *         strategies. Owner is `ArbiSmartV3` itself — every privileged call
 *         here is therefore already subject to whatever access control the
 *         main contract applies before forwarding the call.
 *
 * @dev CRITICAL INVARIANT: there is no function anywhere in this contract
 *      that sends collateral to an arbitrary address. Funds can only:
 *        (a) flow to a whitelisted external protocol via `executeCall`, or
 *        (b) flow back to the main contract via `sweep`.
 *      The owner (the main contract) cannot withdraw vault capital to
 *      itself or anyone else outside of these two paths.
 */
contract ArbitrageVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateralToken;
    address public immutable pool; // the ArbiSmartV3 contract profits/losses are settled against

    uint256 public allocatedBaseline; // collateral value this vault is "supposed" to hold, for profit/loss accounting
    uint256 public totalProfitReturned;
    uint256 public totalLossRecorded;

    mapping(address => bool) public approvedProtocols;

    address public constant POLYMARKET_CONDITIONAL_TOKENS = 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045;

    event ProtocolApproved(address indexed protocol, bool approved);
    event Allocated(uint256 amount, uint256 newBaseline);
    event ArbitrageCallExecuted(address indexed protocol, bytes data, uint256 timestamp);
    event ProfitReturned(uint256 amount, uint256 newBaseline);
    event LossRecorded(uint256 amount, uint256 newBaseline);
    event PolymarketSplit(bytes32 indexed conditionId, uint256 amount, uint256[] partition);
    event PolymarketMerge(bytes32 indexed conditionId, uint256 amount, uint256[] partition);
    event PolymarketRedeem(bytes32 indexed conditionId, uint256[] indexSets, uint256 received);

    error ZeroAddress();
    error ProtocolNotApproved();
    error OnlyPool();
    error CallFailed();

    modifier onlyPool() {
        if (msg.sender != pool) revert OnlyPool();
        _;
    }

    constructor(address _collateralToken, address _pool, address _owner) Ownable(_owner) {
        if (_collateralToken == address(0) || _pool == address(0)) revert ZeroAddress();
        collateralToken = IERC20(_collateralToken);
        pool = _pool;
        approvedProtocols[POLYMARKET_CONDITIONAL_TOKENS] = true;
        emit ProtocolApproved(POLYMARKET_CONDITIONAL_TOKENS, true);
        collateralToken.forceApprove(POLYMARKET_CONDITIONAL_TOKENS, type(uint256).max);
    }

    /// @notice Called by the pool immediately after transferring `amount` of
    ///         collateral into this vault, to update the profit/loss baseline.
    function notifyAllocation(uint256 amount) external onlyPool {
        allocatedBaseline += amount;
        emit Allocated(amount, allocatedBaseline);
    }

    /// @notice Owner (the pool contract, itself gated by its own timelock)
    ///         manages which external protocol contracts this vault may call.
    function setProtocolApproved(address protocol, bool approved) external onlyOwner {
        if (protocol == address(0)) revert ZeroAddress();
        approvedProtocols[protocol] = approved;
        emit ProtocolApproved(protocol, approved);
    }

    /// @notice Generic whitelisted-protocol call, for future integrations
    ///         beyond the built-in Polymarket helpers below. Reverts unless
    ///         `protocol` is on the whitelist. Cannot target an arbitrary
    ///         address — this is the sole guarantee that keeps vault capital
    ///         from ever reaching an unapproved destination.
    function executeCall(address protocol, bytes calldata data) external onlyOwner nonReentrant returns (bytes memory) {
        if (!approvedProtocols[protocol]) revert ProtocolNotApproved();
        (bool success, bytes memory ret) = protocol.call(data);
        if (!success) revert CallFailed();
        emit ArbitrageCallExecuted(protocol, data, block.timestamp);
        return ret;
    }

    function executePolymarketSplit(bytes32 conditionId, uint256[] calldata partition, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (!approvedProtocols[POLYMARKET_CONDITIONAL_TOKENS]) revert ProtocolNotApproved();
        IConditionalTokens(POLYMARKET_CONDITIONAL_TOKENS).splitPosition(
            collateralToken, bytes32(0), conditionId, partition, amount
        );
        emit PolymarketSplit(conditionId, amount, partition);
    }

    function executePolymarketMerge(bytes32 conditionId, uint256[] calldata partition, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (!approvedProtocols[POLYMARKET_CONDITIONAL_TOKENS]) revert ProtocolNotApproved();
        IConditionalTokens(POLYMARKET_CONDITIONAL_TOKENS).mergePositions(
            collateralToken, bytes32(0), conditionId, partition, amount
        );
        emit PolymarketMerge(conditionId, amount, partition);
    }

    function executePolymarketRedeem(bytes32 conditionId, uint256[] calldata indexSets) external onlyOwner nonReentrant {
        if (!approvedProtocols[POLYMARKET_CONDITIONAL_TOKENS]) revert ProtocolNotApproved();
        uint256 before = collateralToken.balanceOf(address(this));
        IConditionalTokens(POLYMARKET_CONDITIONAL_TOKENS).redeemPositions(
            collateralToken, bytes32(0), conditionId, indexSets
        );
        uint256 received = collateralToken.balanceOf(address(this)) - before;
        emit PolymarketRedeem(conditionId, indexSets, received);
    }

    /// @notice Reconciles the vault's actual balance against `allocatedBaseline`.
    ///         If the vault holds MORE than its baseline, the excess (profit)
    ///         is transferred back to the pool automatically and the
    ///         baseline is restored to its prior level. If it holds LESS
    ///         (a loss), the loss is recorded on-chain and the baseline is
    ///         written down to the new, lower actual balance — it is never
    ///         silently hidden or "made whole" from anywhere else.
    ///         Callable by anyone: this only ever moves funds TOWARD the
    ///         pool (for stakers' benefit), never away from it, so there is
    ///         no incentive concern with permissionless calling.
    function sweep() external nonReentrant returns (uint256 profit, uint256 loss) {
        uint256 currentBalance = collateralToken.balanceOf(address(this));
        if (currentBalance > allocatedBaseline) {
            profit = currentBalance - allocatedBaseline;
            totalProfitReturned += profit;
            collateralToken.safeTransfer(pool, profit);
            emit ProfitReturned(profit, allocatedBaseline);
        } else if (currentBalance < allocatedBaseline) {
            loss = allocatedBaseline - currentBalance;
            totalLossRecorded += loss;
            allocatedBaseline = currentBalance;
            emit LossRecorded(loss, allocatedBaseline);
        }
    }

    // Both revert() unconditionally — no native currency can ever be
    // received, so there is nothing to "lock" or need a withdraw path for.
    // slither-disable-next-line locked-ether
    receive() external payable {
        revert();
    }

    // slither-disable-next-line locked-ether
    fallback() external payable {
        revert();
    }
}
