// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IArbiSmartV3StakeReader {
    function stakes(address user)
        external
        view
        returns (
            uint256 amount,
            uint256 plan,
            uint256 rate,
            uint256 startTime,
            uint256 lastClaimTime,
            uint256 totalClaimed,
            bool active,
            bool earlyExited,
            bool freeStake
        );
}

/**
 * @title RecoveryVault
 * @notice The ONLY possible destination for an emergency fund transfer out
 *         of ArbiSmartV3 (see {GuardianGovernance}). This contract can never
 *         send funds to an owner or admin address — it has no such function.
 *         It exists solely to let users self-serve recover their pro-rata
 *         share of whatever was transferred in, or voluntarily migrate that
 *         share to a new, guardian-approved contract.
 *
 * @dev Deployed once per ArbiSmartV3 instance, referencing it immutably.
 *      `fund()` can only be called by that exact main contract, and only
 *      once (enforced by `recoveryActive` never being unset). There is no
 *      owner, no `Ownable`, no privileged withdrawal path of any kind.
 */
contract RecoveryVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateralToken;
    address public immutable mainContract;

    bool public recoveryActive;
    uint256 public totalRecovered;
    uint256 public totalEntitledSnapshot;
    string public emergencyReason;
    uint256 public fundedAt;

    mapping(address => bool) public claimed;
    mapping(address => bool) public approvedMigrationTargets;

    event Funded(uint256 totalRecovered, uint256 totalEntitledSnapshot, string reason, uint256 timestamp);
    event Claimed(address indexed user, uint256 amount);
    event MigratedOut(address indexed user, address indexed newContract, uint256 amount);
    event MigrationTargetApproved(address indexed target, bool approved);

    error ZeroAddress();
    error OnlyMainContract();
    error AlreadyFunded();
    error NotFunded();
    error AlreadyClaimed();
    error NothingToClaim();
    error MigrationTargetNotApproved();

    modifier onlyMainContract() {
        if (msg.sender != mainContract) revert OnlyMainContract();
        _;
    }

    constructor(address _collateralToken, address _mainContract) {
        if (_collateralToken == address(0) || _mainContract == address(0)) revert ZeroAddress();
        collateralToken = IERC20(_collateralToken);
        mainContract = _mainContract;
    }

    /// @notice Called exactly once by ArbiSmartV3, only after its 5-of-5
    ///         guardian-approved, 24-hour-timelocked emergency execution.
    /// @param totalEntitled The main contract's `totalStaked` at the moment
    ///        of transfer — the fixed baseline every user's pro-rata share
    ///        is computed against.
    function fund(uint256 totalEntitled, string calldata reason) external onlyMainContract {
        if (recoveryActive) revert AlreadyFunded();
        recoveryActive = true;
        totalEntitledSnapshot = totalEntitled;
        emergencyReason = reason;
        fundedAt = block.timestamp;
        totalRecovered = collateralToken.balanceOf(address(this));
        emit Funded(totalRecovered, totalEntitled, reason, block.timestamp);
    }

    function _entitlement(address user) internal view returns (uint256) {
        if (totalEntitledSnapshot == 0) return 0;
        // Only `amount` (the user's recorded principal) is needed from this
        // view struct — the other 8 fields (plan/rate/timestamps/flags) are
        // intentionally unused, not an overlooked return value.
        // slither-disable-next-line unused-return
        (uint256 amount,,,,,,,,) = IArbiSmartV3StakeReader(mainContract).stakes(user);
        return (amount * totalRecovered) / totalEntitledSnapshot;
    }

    /// @notice View helper for frontends: what a user would receive if they
    ///         claimed right now.
    function previewClaim(address user) external view returns (uint256) {
        if (!recoveryActive || claimed[user]) return 0;
        return _entitlement(user);
    }

    /// @notice Claim your pro-rata share directly to your own address.
    function claim() external nonReentrant {
        _processClaim(msg.sender, msg.sender);
    }

    /// @notice Voluntarily redirect your pro-rata share to a new contract
    ///         you are migrating to. `newContract` must have been approved
    ///         via guardian governance ({GuardianGovernance.ApproveMigrationTarget})
    ///         — this is your own choice for your own funds, never something
    ///         the owner or guardians can force on your behalf.
    function claimToMigration(address newContract) external nonReentrant {
        if (!approvedMigrationTargets[newContract]) revert MigrationTargetNotApproved();
        _processClaim(msg.sender, newContract);
    }

    function _processClaim(address user, address to) private {
        if (!recoveryActive) revert NotFunded();
        if (claimed[user]) revert AlreadyClaimed();
        uint256 amount = _entitlement(user);
        // slither-disable-next-line incorrect-equality
        if (amount == 0) revert NothingToClaim();

        claimed[user] = true;
        collateralToken.safeTransfer(to, amount);

        if (to == user) {
            emit Claimed(user, amount);
        } else {
            emit MigratedOut(user, to, amount);
        }
    }

    /// @notice Approves (or revokes) a contract as a valid voluntary
    ///         migration destination. Callable only by the main contract,
    ///         which itself only allows this through full guardian
    ///         consensus (see `ArbiSmartV3.dispatchApproveMigrationTarget`).
    function setMigrationTargetApproved(address target, bool approved) external onlyMainContract {
        approvedMigrationTargets[target] = approved;
        emit MigrationTargetApproved(target, approved);
    }
}
