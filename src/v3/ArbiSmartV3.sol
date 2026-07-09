// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * BUILD REQUIREMENT: compile with `viaIR: true` (same reason as ArbiSmartV2 —
 * verified directly: several view functions here return 7+ values, which
 * trips "Stack too deep" under the legacy codegen pipeline).
 */

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {GuardianGovernance} from "./GuardianGovernance.sol";
import {OwnerTimelock} from "./OwnerTimelock.sol";
import {RecoveryVault} from "./RecoveryVault.sol";
import {ArbitrageVault} from "./ArbitrageVault.sol";

/**
 * @title ArbiSmartV3
 * @notice Institutional-grade rewrite of ArbiSmartV2: USDT-only staking with
 *         tiered daily rewards, multi-level referrals, and a bounded
 *         treasury arbitrage strategy — with fund-moving emergency power
 *         structurally removed from the owner and placed under 5-of-5
 *         independent guardian consensus with a mandatory 24-hour timelock.
 *
 * @dev ============================================================
 *      OWNER SECURITY MODEL — READ THIS FIRST
 *      ============================================================
 *      Owner CAN (all non-fund-moving, all 24h-timelocked except pause):
 *        - pause() / unpause() [instant — protective, not fund-moving]
 *        - scheduleSetFeeWallets / executeSetFeeWallets
 *        - scheduleSetFeeSplitBps / executeSetFeeSplitBps
 *        - scheduleSetProfitRecipient / executeSetProfitRecipient
 *        - scheduleSetProfitFeeBps / executeSetProfitFeeBps
 *        - scheduleAllocateToArbitrage / executeAllocateToArbitrage (capped
 *          at 20% of pool balance; funds go ONLY to the immutable
 *          {ArbitrageVault} address, never to the owner)
 *        - scheduleSetArbitrageProtocol / executeSetArbitrageProtocol
 *        - setBlacklist (compliance tool; cannot block {earlyExit} or
 *          {emergencyWithdraw} — principal can never be permanently frozen)
 *
 *      Owner CANNOT, under any code path in this contract:
 *        - withdraw pooled user collateral to itself or any address
 *        - drain the {ArbitrageVault} (it has no owner-withdraw function)
 *        - trigger the guardian emergency-recovery path (owner is not, and
 *          cannot be, a guardian — enforced in {GuardianGovernance}'s
 *          constructor)
 *        - redirect an emergency transfer anywhere but the immutable
 *          {RecoveryVault} address
 *
 *      Fund-moving emergency power belongs ONLY to 5 independent guardian
 *      wallets, requires unanimous (5/5) approval, a mandatory 24-hour
 *      timelock after the 5th approval, and an on-chain recorded reason.
 *      See {GuardianGovernance}.
 */
contract ArbiSmartV3 is Ownable2Step, ReentrancyGuard, Pausable, GuardianGovernance, OwnerTimelock {
    using SafeERC20 for IERC20;

    // ============================================================
    // Collateral — Polygon USDT only
    // ============================================================

    address public constant POLYGON_USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;

    IERC20 public immutable collateralToken;

    // ============================================================
    // Vaults (bootstrapped once, immediately after deployment)
    // ============================================================

    ArbitrageVault public arbitrageVault;
    RecoveryVault public recoveryVault;
    bool public vaultsInitialized;
    bool public emergencyTriggered;

    // ============================================================
    // Fee configuration
    // ============================================================

    address public feeWallet1;
    address public feeWallet2;
    uint256 public feeSplitBps1 = 7000; // 70% of the 10% claim fee
    uint256 public constant CLAIM_FEE_BPS = 1000; // 10% fee on staking PROFIT (reward) only, never principal

    address public profitRecipient;
    uint256 public profitFeeBPS = 1000; // 10% default performance fee on realized arbitrage profit
    uint256 public constant PROFIT_FEE_MAX_BPS = 2000;

    uint256 public constant ARBITRAGE_MAX_BPS = 2000; // hard cap: 20% of pool per allocation, not owner-adjustable

    // ============================================================
    // Staking state (preserved from ArbiSmartV2)
    // ============================================================

    uint256 public totalStaked;
    uint256 public totalPaidOut;
    uint256 public immutable deployTime;
    uint256 public constant FREE_PERIOD = 24 hours;
    uint256 public pausedAt;
    uint256 public constant EMERGENCY_GRACE_PERIOD = 30 days;

    uint256 private _userCount;
    uint256 private _activeStakeCount;

    struct Stake {
        uint256 amount;
        uint256 plan;
        uint256 rate;
        uint256 startTime;
        uint256 lastClaimTime;
        uint256 totalClaimed;
        bool active;
        bool earlyExited;
        bool freeStake;
    }

    struct Referral {
        address referrer;
        uint256 totalEarned;
        uint256 pendingReward;
        uint256 activeReferrals;
        uint256 level;
    }

    mapping(address => Stake) public stakes;
    mapping(address => Referral) public referrals;
    mapping(address => uint256) public lastWithdrawalDay;
    mapping(address => uint256) public dailyWithdrawn;
    mapping(address => bool) public blacklisted;
    mapping(address => address[]) private _f1List;
    mapping(address => uint256) private _f1Volume;
    mapping(address => uint256) private _f2Volume;
    mapping(address => uint256) private _claimCounts;

    uint256[4] public dailyRates = [120, 180, 240, 300];
    uint256[4] public planDurations = [180, 150, 120, 90];
    uint256[4] public minStakes = [10_000000, 500_000000, 2_500_000000, 10_000_000000];

    uint256[8] public referralRates = [800, 400, 1200, 600, 1500, 800, 2000, 1000];
    uint256[3] public f3Rates = [200, 400, 500];

    uint256 private constant MAX_DAILY_BPS = 20000;
    uint256 private constant MAX_STAKE = 25_000_000000;
    uint256 private constant MIN_STAKE = 10_000000;
    uint256 private constant PENALTY_W1 = 5000;
    uint256 private constant PENALTY_W2 = 4000;
    uint256 private constant PENALTY_W3 = 3000;
    uint256 private constant PENALTY_W4 = 2000;
    uint256 private constant PENALTY_AF = 1000;
    uint256 private constant DAY = 1 days;
    uint256 private constant WEEK = 7 days;
    uint256 private constant BPS_DENOMINATOR = 10000;

    // ============================================================
    // Events
    // ============================================================

    event Staked(address indexed user, uint256 amount, uint256 plan, address indexed referrer, bool free);
    event ToppedUp(address indexed user, uint256 amount, uint256 newTotal);
    event PlanUpgraded(address indexed user, uint256 oldPlan, uint256 newPlan);
    event Claimed(address indexed user, uint256 amount, uint256 fee);
    event ReferralClaimed(address indexed user, uint256 amount);
    event EarlyExited(address indexed user, uint256 amount, uint256 penalty);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event BlacklistUpdated(address indexed user, bool value);
    event FeeWalletsUpdated(address indexed newFeeWallet1, address indexed newFeeWallet2);
    event FeeSplitUpdated(uint256 newFeeSplitBps1);
    event ProfitRecipientUpdated(address indexed newRecipient);
    event ProfitFeeBpsUpdated(uint256 newFeeBPS);
    event EmergencyPaused(uint256 timestamp);
    event VaultsInitialized(address indexed arbitrageVault, address indexed recoveryVault);
    event ArbitrageAllocated(uint256 amount, uint256 poolBalanceAfter);
    event ArbitrageSwept(uint256 profit, uint256 loss);
    event GuardianEmergencyExecuted(uint256 indexed proposalId, uint256 totalTransferred, string reason);

    // ============================================================
    // Errors
    // ============================================================

    error ZeroAddress();
    error ZeroAmount();
    error Blacklisted();
    error ContractCallerNotAllowed();
    error AlreadyActive();
    error AlreadyExited();
    error NoActiveStake();
    error BelowMinStake();
    error AboveMaxStake();
    error InvalidFreeStakeAmount();
    error TransferAmountMismatch();
    error NothingToClaim();
    error DailyWithdrawalCapExceeded();
    error PlanUnchanged();
    error CannotBlacklistOwner();
    error AmountExceedsAvailable();
    error NotPausedError();
    error GracePeriodNotElapsed();
    error ProfitFeeTooHigh();
    error InvalidFeeSplit();
    error VaultsAlreadyInitialized();
    error VaultsNotInitialized();
    error InvalidCollateralToken();
    error EmergencyAlreadyTriggered();
    error InvalidGuardianActionForDispatch();

    modifier notBlacklisted() {
        if (blacklisted[msg.sender]) revert Blacklisted();
        _;
    }

    modifier onlyEOA() {
        if (tx.origin != msg.sender) revert ContractCallerNotAllowed();
        _;
    }

    modifier notInEmergency() {
        if (emergencyTriggered) revert EmergencyAlreadyTriggered();
        _;
    }

    // ============================================================
    // Constructor
    // ============================================================

    /// @param _collateralToken Must equal {POLYGON_USDT} when deployed on
    ///        Polygon mainnet (chainid 137); left flexible on other chains
    ///        purely so this contract remains testable in Foundry/Anvil.
    /// @param initialOwner Recommended: a Gnosis Safe multisig.
    /// @param _feeWallet1 / _feeWallet2 Claim-fee recipients (70/30 split by default).
    /// @param _profitRecipient Arbitrage performance-fee recipient.
    /// @param _guardians Exactly 5 distinct addresses, none equal to `initialOwner`.
    constructor(
        address _collateralToken,
        address initialOwner,
        address _feeWallet1,
        address _feeWallet2,
        address _profitRecipient,
        address[5] memory _guardians
    ) Ownable(initialOwner) GuardianGovernance(_guardians, initialOwner) {
        if (
            _collateralToken == address(0) || _feeWallet1 == address(0) || _feeWallet2 == address(0)
                || _profitRecipient == address(0)
        ) revert ZeroAddress();
        if (block.chainid == 137 && _collateralToken != POLYGON_USDT) revert InvalidCollateralToken();

        collateralToken = IERC20(_collateralToken);
        feeWallet1 = _feeWallet1;
        feeWallet2 = _feeWallet2;
        profitRecipient = _profitRecipient;
        deployTime = block.timestamp;
    }

    /// @notice One-time bootstrap: deploy {ArbitrageVault} and {RecoveryVault}
    ///         (each constructor needs this contract's own address, so they
    ///         cannot be created before this contract exists), then wire
    ///         them in. Callable once, by the owner, no timelock (there is
    ///         no user principal at risk before vaults are wired — the pool
    ///         cannot meaningfully operate arbitrage or emergency-recovery
    ///         until this runs, and it does not move any funds itself).
    function initializeVaults(address _arbitrageVault, address _recoveryVault) external onlyOwner {
        if (vaultsInitialized) revert VaultsAlreadyInitialized();
        if (_arbitrageVault == address(0) || _recoveryVault == address(0)) revert ZeroAddress();
        vaultsInitialized = true;
        arbitrageVault = ArbitrageVault(payable(_arbitrageVault));
        recoveryVault = RecoveryVault(_recoveryVault);
        emit VaultsInitialized(_arbitrageVault, _recoveryVault);
    }

    // ============================================================
    // Helpers
    // ============================================================

    function _getPlanByAmount(uint256 amount) private pure returns (uint256) {
        if (amount >= 10_000_000000) return 3;
        if (amount >= 2_500_000000) return 2;
        if (amount >= 500_000000) return 1;
        return 0;
    }

    function isFreePeriod() public view returns (bool) {
        return block.timestamp < deployTime + FREE_PERIOD;
    }

    function getTimeLeft() public view returns (uint256) {
        if (!isFreePeriod()) return 0;
        return (deployTime + FREE_PERIOD) - block.timestamp;
    }

    function arbitrageAvailable() public view returns (uint256) {
        return (collateralToken.balanceOf(address(this)) * ARBITRAGE_MAX_BPS) / BPS_DENOMINATOR;
    }

    // ============================================================
    // Owner — timelocked configuration (24h, no user principal at risk)
    // ============================================================

    function scheduleSetFeeWallets(address newFeeWallet1, address newFeeWallet2) external onlyOwner {
        _schedule(keccak256(abi.encode("setFeeWallets", newFeeWallet1, newFeeWallet2)));
    }

    function executeSetFeeWallets(address newFeeWallet1, address newFeeWallet2) external onlyOwner {
        if (newFeeWallet1 == address(0) || newFeeWallet2 == address(0)) revert ZeroAddress();
        _consume(keccak256(abi.encode("setFeeWallets", newFeeWallet1, newFeeWallet2)));
        feeWallet1 = newFeeWallet1;
        feeWallet2 = newFeeWallet2;
        emit FeeWalletsUpdated(newFeeWallet1, newFeeWallet2);
    }

    function scheduleSetFeeSplitBps(uint256 newSplit1) external onlyOwner {
        _schedule(keccak256(abi.encode("setFeeSplitBps", newSplit1)));
    }

    function executeSetFeeSplitBps(uint256 newSplit1) external onlyOwner {
        if (newSplit1 > BPS_DENOMINATOR) revert InvalidFeeSplit();
        _consume(keccak256(abi.encode("setFeeSplitBps", newSplit1)));
        feeSplitBps1 = newSplit1;
        emit FeeSplitUpdated(newSplit1);
    }

    function scheduleSetProfitRecipient(address newRecipient) external onlyOwner {
        _schedule(keccak256(abi.encode("setProfitRecipient", newRecipient)));
    }

    function executeSetProfitRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        _consume(keccak256(abi.encode("setProfitRecipient", newRecipient)));
        profitRecipient = newRecipient;
        emit ProfitRecipientUpdated(newRecipient);
    }

    function scheduleSetProfitFeeBps(uint256 newFeeBPS) external onlyOwner {
        _schedule(keccak256(abi.encode("setProfitFeeBps", newFeeBPS)));
    }

    function executeSetProfitFeeBps(uint256 newFeeBPS) external onlyOwner {
        if (newFeeBPS > PROFIT_FEE_MAX_BPS) revert ProfitFeeTooHigh();
        _consume(keccak256(abi.encode("setProfitFeeBps", newFeeBPS)));
        profitFeeBPS = newFeeBPS;
        emit ProfitFeeBpsUpdated(newFeeBPS);
    }

    function scheduleSetArbitrageProtocol(address protocol, bool approved) external onlyOwner {
        _schedule(keccak256(abi.encode("setArbitrageProtocol", protocol, approved)));
    }

    function executeSetArbitrageProtocol(address protocol, bool approved) external onlyOwner {
        if (!vaultsInitialized) revert VaultsNotInitialized();
        _consume(keccak256(abi.encode("setArbitrageProtocol", protocol, approved)));
        arbitrageVault.setProtocolApproved(protocol, approved);
    }

    function scheduleAllocateToArbitrage(uint256 amount) external onlyOwner {
        _schedule(keccak256(abi.encode("allocateToArbitrage", amount)));
    }

    /// @notice Transfers `amount` of pooled collateral to the immutable
    ///         {ArbitrageVault} — never to the owner or any other address.
    ///         Capped at 20% of the pool's CURRENT balance at execution time
    ///         (re-checked, not just at scheduling time).
    function executeAllocateToArbitrage(uint256 amount) external onlyOwner whenNotPaused notInEmergency nonReentrant {
        if (!vaultsInitialized) revert VaultsNotInitialized();
        if (amount == 0) revert ZeroAmount();
        if (amount > arbitrageAvailable()) revert AmountExceedsAvailable();
        _consume(keccak256(abi.encode("allocateToArbitrage", amount)));

        collateralToken.safeTransfer(address(arbitrageVault), amount);
        arbitrageVault.notifyAllocation(amount);
        emit ArbitrageAllocated(amount, collateralToken.balanceOf(address(this)));
    }

    /// @notice Pulls any profit the vault has already swept back to itself
    ///         and applies the performance fee. Permissionless: the vault's
    ///         own `sweep()` already pushes profit to this contract's
    ///         balance directly, so this just distributes the performance
    ///         fee on newly-received arbitrage profit tracked via
    ///         `arbitrageVault.totalProfitReturned()` deltas.
    uint256 private _lastSeenProfitReturned;

    function settleArbitrageProfit() external nonReentrant {
        if (!vaultsInitialized) revert VaultsNotInitialized();
        uint256 currentTotal = arbitrageVault.totalProfitReturned();
        uint256 newProfit = currentTotal - _lastSeenProfitReturned;
        if (newProfit == 0) return;
        _lastSeenProfitReturned = currentTotal;

        uint256 fee = (newProfit * profitFeeBPS) / BPS_DENOMINATOR;
        if (fee > 0) {
            collateralToken.safeTransfer(profitRecipient, fee);
        }
        // The remainder simply stays in the pool's own balance (already
        // received from the vault), directly benefiting `totalStaked`
        // backing without any extra bookkeeping needed.
    }

    // ============================================================
    // Owner — instant (protective, non-fund-moving)
    // ============================================================

    function pause() external onlyOwner {
        _pause();
        pausedAt = block.timestamp;
        emit EmergencyPaused(block.timestamp);
    }

    function unpause() external onlyOwner notInEmergency {
        _unpause();
        pausedAt = 0;
    }

    function setBlacklist(address user, bool value) external onlyOwner {
        if (user == owner()) revert CannotBlacklistOwner();
        blacklisted[user] = value;
        emit BlacklistUpdated(user, value);
    }

    // ============================================================
    // Guardian governance dispatch
    // ============================================================

    function _dispatchGuardianAction(uint256 proposalId, GuardianActionType actionType, bytes memory data)
        internal
        override
        notInEmergency
    {
        if (actionType == GuardianActionType.TriggerEmergency) {
            string memory reason = abi.decode(data, (string));
            _executeEmergencyTransfer(proposalId, reason);
        } else if (actionType == GuardianActionType.ApproveMigrationTarget) {
            address target = abi.decode(data, (address));
            recoveryVault.setMigrationTargetApproved(target, true);
        } else {
            revert InvalidGuardianActionForDispatch();
        }
    }

    function _executeEmergencyTransfer(uint256 proposalId, string memory reason) private {
        if (!vaultsInitialized) revert VaultsNotInitialized();
        emergencyTriggered = true;
        if (!paused()) _pause();

        uint256 balance = collateralToken.balanceOf(address(this));
        uint256 snapshot = totalStaked;

        if (balance > 0) {
            collateralToken.safeTransfer(address(recoveryVault), balance);
        }
        recoveryVault.fund(snapshot, reason);

        emit GuardianEmergencyExecuted(proposalId, balance, reason);
    }

    // ============================================================
    // User functions (preserved from ArbiSmartV2, unchanged business logic)
    // ============================================================

    function stake(uint256 amount, address referrer)
        external
        whenNotPaused
        notBlacklisted
        onlyEOA
        notInEmergency
        nonReentrant
    {
        Stake storage s = stakes[msg.sender];
        if (s.active) revert AlreadyActive();
        if (s.earlyExited) revert AlreadyExited();
        if (amount < MIN_STAKE) revert BelowMinStake();
        if (amount > MAX_STAKE) revert AboveMaxStake();

        bool free = false;
        if (isFreePeriod()) {
            if (amount != MIN_STAKE) revert InvalidFreeStakeAmount();
            free = true;
        }
        uint256 plan = _getPlanByAmount(amount);

        if (!free) {
            uint256 balanceBefore = collateralToken.balanceOf(address(this));
            collateralToken.safeTransferFrom(msg.sender, address(this), amount);
            if (collateralToken.balanceOf(address(this)) != balanceBefore + amount) revert TransferAmountMismatch();
        }

        if (referrer != address(0) && referrer != msg.sender && stakes[referrer].active && !blacklisted[referrer]) {
            referrals[msg.sender].referrer = referrer;
            referrals[referrer].activeReferrals++;
            _f1List[referrer].push(msg.sender);
            _f1Volume[referrer] += amount;
            _updateLevel(referrer);
            address grandparent = referrals[referrer].referrer;
            if (grandparent != address(0)) _f2Volume[grandparent] += amount;
        }

        if (s.amount == 0) _userCount++;
        stakes[msg.sender] = Stake(amount, plan, dailyRates[plan], block.timestamp, block.timestamp, 0, true, false, free);
        if (!free) totalStaked += amount;
        _activeStakeCount++;
        emit Staked(msg.sender, amount, plan, referrer, free);
    }

    function topUp(uint256 amount) external whenNotPaused notBlacklisted onlyEOA notInEmergency nonReentrant {
        Stake storage s = stakes[msg.sender];
        if (!s.active) revert NoActiveStake();
        if (s.freeStake) revert InvalidFreeStakeAmount();
        if (amount < MIN_STAKE) revert BelowMinStake();
        uint256 newTotal = s.amount + amount;
        if (newTotal > MAX_STAKE) revert AboveMaxStake();

        uint256 balanceBefore = collateralToken.balanceOf(address(this));
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        if (collateralToken.balanceOf(address(this)) != balanceBefore + amount) revert TransferAmountMismatch();

        s.amount = newTotal;
        totalStaked += amount;

        address referrer = referrals[msg.sender].referrer;
        if (referrer != address(0)) {
            _f1Volume[referrer] += amount;
            address grandparent = referrals[referrer].referrer;
            if (grandparent != address(0)) _f2Volume[grandparent] += amount;
            _updateLevel(referrer);
        }
        emit ToppedUp(msg.sender, amount, newTotal);
    }

    function upgradePlan() external whenNotPaused notBlacklisted onlyEOA notInEmergency nonReentrant {
        Stake storage s = stakes[msg.sender];
        if (!s.active) revert NoActiveStake();
        if (s.freeStake) revert InvalidFreeStakeAmount();
        uint256 newPlan = _getPlanByAmount(s.amount);
        if (newPlan == s.plan) revert PlanUnchanged();
        uint256 oldPlan = s.plan;
        s.plan = newPlan;
        s.rate = dailyRates[newPlan];
        emit PlanUpgraded(msg.sender, oldPlan, newPlan);
    }

    /// @notice Claims accrued staking reward. The 10% fee applies ONLY to
    ///         this reward (pure profit) — principal is never touched here;
    ///         it only ever leaves via {earlyExit} or {emergencyWithdraw}.
    function claim() external whenNotPaused notBlacklisted onlyEOA notInEmergency nonReentrant {
        Stake storage s = stakes[msg.sender];
        if (!s.active) revert NoActiveStake();

        uint256 reward = _pendingReward(msg.sender);
        // `reward` is deterministic from stored state, not an externally
        // manipulable balance — an exact zero-check is correct here.
        // slither-disable-next-line incorrect-equality
        if (reward == 0) revert NothingToClaim();

        _checkDailyCap(msg.sender, reward);
        s.lastClaimTime = block.timestamp;
        s.totalClaimed += reward;
        totalPaidOut += reward;

        // Two sequential bps-scalings (fee, then fee1 from fee) — each
        // division is by the fixed 10000 bps denominator, the standard and
        // only reasonably precise way to express nested percentages in
        // integer arithmetic; the residual rounding is negligible (<1 wei
        // per claim) and never favors any party systematically.
        // slither-disable-next-line divide-before-multiply
        uint256 fee = (reward * CLAIM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 fee1 = (fee * feeSplitBps1) / BPS_DENOMINATOR;
        uint256 fee2 = fee - fee1;
        uint256 userAmount = reward - fee;

        _processReferralRewards(msg.sender, reward);
        _updateDailyWithdrawn(msg.sender, userAmount);
        _claimCounts[msg.sender]++;

        if (fee1 > 0) collateralToken.safeTransfer(feeWallet1, fee1);
        if (fee2 > 0) collateralToken.safeTransfer(feeWallet2, fee2);
        collateralToken.safeTransfer(msg.sender, userAmount);

        emit Claimed(msg.sender, userAmount, fee);
    }

    function claimRef() external whenNotPaused notBlacklisted onlyEOA notInEmergency nonReentrant {
        Referral storage r = referrals[msg.sender];
        uint256 pending = r.pendingReward;
        if (pending == 0) revert NothingToClaim();

        r.pendingReward = 0;
        r.totalEarned += pending;

        collateralToken.safeTransfer(msg.sender, pending);
        emit ReferralClaimed(msg.sender, pending);
    }

    function earlyExit() external onlyEOA notInEmergency nonReentrant {
        Stake storage s = stakes[msg.sender];
        if (!s.active) revert NoActiveStake();

        bool free = s.freeStake;
        uint256 amount = s.amount;
        uint256 penalty = free ? 0 : _earlyExitPenalty(msg.sender);
        uint256 returned = free ? 0 : amount - penalty;

        s.earlyExited = true;
        _deactivateStake(msg.sender);

        if (returned > 0) collateralToken.safeTransfer(msg.sender, returned);
        emit EarlyExited(msg.sender, returned, penalty);
    }

    function emergencyWithdraw() external nonReentrant {
        if (!paused()) revert NotPausedError();
        if (emergencyTriggered) revert EmergencyAlreadyTriggered();
        if (pausedAt == 0 || block.timestamp < pausedAt + EMERGENCY_GRACE_PERIOD) revert GracePeriodNotElapsed();

        Stake storage s = stakes[msg.sender];
        if (!s.active) revert NoActiveStake();

        bool free = s.freeStake;
        uint256 amount = s.amount;

        s.earlyExited = true;
        _deactivateStake(msg.sender);

        if (!free && amount > 0) collateralToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdrawn(msg.sender, amount);
    }

    // ============================================================
    // Internal accounting (unchanged from ArbiSmartV2)
    // ============================================================

    function _deactivateStake(address user) private {
        Stake storage s = stakes[user];
        if (!s.freeStake) totalStaked -= s.amount;
        s.active = false;
        s.amount = 0;
        s.rate = 0;
        if (_activeStakeCount > 0) _activeStakeCount--;

        address referrer = referrals[user].referrer;
        if (referrer != address(0) && referrals[referrer].activeReferrals > 0) {
            referrals[referrer].activeReferrals--;
            _updateLevel(referrer);
        }
    }

    function _pendingReward(address user) private view returns (uint256) {
        Stake storage s = stakes[user];
        uint256 planEnd = s.startTime + (planDurations[s.plan] * DAY);
        uint256 accrualEnd = block.timestamp > planEnd ? planEnd : block.timestamp;
        if (accrualEnd <= s.lastClaimTime) return 0;
        uint256 elapsed = accrualEnd - s.lastClaimTime;
        return (s.amount * s.rate * elapsed) / (BPS_DENOMINATOR * DAY);
    }

    function _earlyExitPenalty(address user) private view returns (uint256) {
        Stake storage s = stakes[user];
        uint256 weeksElapsed = (block.timestamp - s.startTime) / WEEK;
        uint256 penaltyBps;
        if (weeksElapsed < 1) penaltyBps = PENALTY_W1;
        else if (weeksElapsed < 2) penaltyBps = PENALTY_W2;
        else if (weeksElapsed < 3) penaltyBps = PENALTY_W3;
        else if (weeksElapsed < 4) penaltyBps = PENALTY_W4;
        else penaltyBps = PENALTY_AF;
        return (s.amount * penaltyBps) / BPS_DENOMINATOR;
    }

    function _processReferralRewards(address user, uint256 reward) private {
        address referrer = referrals[user].referrer;
        if (referrer == address(0) || blacklisted[referrer]) return;

        uint256 level = referrals[referrer].level;
        uint256 f1 = (reward * referralRates[level * 2]) / BPS_DENOMINATOR;
        if (f1 > 0) referrals[referrer].pendingReward += f1;

        address grandparent = referrals[referrer].referrer;
        if (grandparent != address(0) && !blacklisted[grandparent]) {
            uint256 grandparentLevel = referrals[grandparent].level;
            uint256 f2 = (reward * referralRates[grandparentLevel * 2 + 1]) / BPS_DENOMINATOR;
            if (f2 > 0) referrals[grandparent].pendingReward += f2;

            if (level >= 1) {
                address greatGrandparent = referrals[grandparent].referrer;
                if (greatGrandparent != address(0) && !blacklisted[greatGrandparent]) {
                    uint256 f3 = (reward * f3Rates[level - 1]) / BPS_DENOMINATOR;
                    if (f3 > 0) referrals[greatGrandparent].pendingReward += f3;
                }
            }
        }
    }

    function _updateLevel(address user) private {
        Referral storage r = referrals[user];
        uint256 activeReferrals = r.activeReferrals;
        uint256 stakedAmount = stakes[user].amount;
        uint256 newLevel;
        if (stakedAmount >= 10_000_000000 && activeReferrals >= 100) newLevel = 3;
        else if (stakedAmount >= 2_500_000000 && activeReferrals >= 25) newLevel = 2;
        else if (stakedAmount >= 500_000000 && activeReferrals >= 5) newLevel = 1;
        else newLevel = 0;
        if (newLevel != r.level) r.level = newLevel;
    }

    function _checkDailyCap(address user, uint256 amount) private view {
        // slither-disable-next-line divide-before-multiply
        uint256 today = (block.timestamp / DAY) * DAY;
        // slither-disable-next-line incorrect-equality
        if (lastWithdrawalDay[user] == today) {
            if (dailyWithdrawn[user] + amount > (stakes[user].amount * MAX_DAILY_BPS) / BPS_DENOMINATOR) {
                revert DailyWithdrawalCapExceeded();
            }
        }
    }

    function _updateDailyWithdrawn(address user, uint256 amount) private {
        // slither-disable-next-line divide-before-multiply
        uint256 today = (block.timestamp / DAY) * DAY;
        if (lastWithdrawalDay[user] != today) {
            lastWithdrawalDay[user] = today;
            dailyWithdrawn[user] = 0;
        }
        dailyWithdrawn[user] += amount;
    }

    // ============================================================
    // Views
    // ============================================================

    function getReward(address user) external view returns (uint256) {
        return _pendingReward(user);
    }

    function getRefReward(address user) external view returns (uint256) {
        return referrals[user].pendingReward;
    }

    function getBalance() external view returns (uint256) {
        return collateralToken.balanceOf(address(this));
    }

    function getGlobalStats() external view returns (uint256, uint256, uint256, uint256) {
        return (_userCount, totalStaked, totalPaidOut, collateralToken.balanceOf(address(this)));
    }

    function getUserStats(address user)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        Stake storage s = stakes[user];
        Referral storage r = referrals[user];
        return (s.amount, s.plan, s.rate, _pendingReward(user), s.totalClaimed, r.totalEarned, r.pendingReward, r.activeReferrals);
    }

    function getStakeBasic(address user)
        external
        view
        returns (uint256, uint256, uint256, uint256, bool, bool, uint256, uint256)
    {
        Stake storage s = stakes[user];
        return (s.amount, s.plan, s.rate, s.startTime, s.active, s.freeStake, s.totalClaimed, _claimCounts[user]);
    }

    function getReferralInfo(address user) external view returns (address, uint256, uint256, uint256, uint256) {
        Referral storage r = referrals[user];
        return (r.referrer, r.totalEarned, r.pendingReward, r.activeReferrals, r.level);
    }

    function getTeamVolume(address user) external view returns (uint256, uint256, uint256) {
        return (_f1Volume[user], _f2Volume[user], _f1Volume[user] + _f2Volume[user]);
    }

    function getF1List(address user)
        external
        view
        returns (address[] memory addrs, uint256[] memory amounts, uint256[] memory plans)
    {
        uint256 len = _f1List[user].length;
        addrs = new address[](len);
        amounts = new uint256[](len);
        plans = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            addrs[i] = _f1List[user][i];
            amounts[i] = stakes[addrs[i]].amount;
            plans[i] = stakes[addrs[i]].plan;
        }
    }

    function getF1Count(address user) external view returns (uint256) {
        return _f1List[user].length;
    }

    function getClaimCount(address user) external view returns (uint256) {
        return _claimCounts[user];
    }

    // ============================================================
    // Native currency handling — explicitly rejected
    // ============================================================

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
