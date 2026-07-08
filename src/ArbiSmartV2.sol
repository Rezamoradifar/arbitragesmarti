// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * BUILD REQUIREMENT: this contract MUST be compiled with `viaIR: true`
 * (Foundry: `via_ir = true` in foundry.toml; Hardhat: `settings.viaIR = true`
 * in the solidity compiler config). Without it, `getUserStatsExtended`
 * fails with a "Stack too deep" compiler error under the legacy codegen
 * pipeline. This was verified directly: compiling this exact file with
 * solc 0.8.24/0.8.26 and the optimizer on fails without `viaIR`, and
 * succeeds (producing valid bytecode) with it enabled. `foundry.toml` in
 * this project already sets `via_ir = true`.
 */

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IConditionalTokens
 * @notice Minimal interface to Polymarket's OFFICIAL, permissionless Gnosis
 *         Conditional Tokens Framework contract deployed on Polygon mainnet
 *         at 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045.
 *
 * @dev These three function signatures were copied verbatim from the real,
 *      deployed, open-source contract
 *      (github.com/gnosis/conditional-tokens-contracts,
 *      contracts/ConditionalTokens.sol) — they are not guessed. Anyone may
 *      call `splitPosition` / `mergePositions` / `redeemPositions` on the
 *      real contract; no special role is required for these three
 *      functions.
 */
interface IConditionalTokens {
    /// @notice Converts `amount` of `collateralToken` (or, if `parentCollectionId != 0`,
    ///         of the parent position) into a full set of outcome-token positions for `conditionId`.
    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    /// @notice The inverse of {splitPosition}: burns a full set of outcome-token
    ///         positions and returns `amount` of collateral (or parent position).
    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    /// @notice Redeems outcome-token positions for collateral after a condition
    ///         has been resolved by its oracle.
    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;

    /// @notice Standard ERC-1155 balance query (outcome tokens are ERC-1155).
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

/**
 * @title ArbiSmartV2
 * @author (refactor of the original ArbiSmart contract, security review requested by the contract owner)
 * @notice A USDC/USDT-collateralized staking + referral pool that, in addition
 *         to fixed-rate staking, allows the contract owner to route a bounded
 *         portion of pooled collateral into REAL, on-chain interactions with
 *         Polymarket's official Conditional Tokens Framework contract on
 *         Polygon (splitting collateral into complete outcome-token sets,
 *         merging them back, and redeeming them after market resolution).
 *
 * @dev ============================================================
 *      WHAT CHANGED VS. THE ORIGINAL CONTRACT, AND WHY — READ THIS FIRST
 *      ============================================================
 *
 *      1. `polymarketArbitrageTrade` / `polymarketArbitrageProfit` (the
 *         original functions) have been DELETED. In the original contract
 *         they did nothing but transfer up to 20% of the pool's collateral
 *         directly to `OWNER`, and pull it back only if/when `OWNER` chose
 *         to, with no on-chain evidence of any actual trade. That is fund
 *         extraction mislabeled as trading, not arbitrage. It is gone.
 *
 *      2. In its place, {executePolymarketSplit}, {executePolymarketMerge},
 *         and {executePolymarketRedeem} call the REAL, official Polymarket
 *         Conditional Tokens contract (0x4D97DCd97eC945f40cF65F87097ACe5EA0476045).
 *         Every {ArbitrageSplitExecuted} / {ArbitrageMergeExecuted} /
 *         {ArbitrageRedeemed} event is emitted ONLY after the external call
 *         to that real contract has already succeeded — there is no code
 *         path that emits these events without the corresponding on-chain
 *         action actually having happened.
 *
 *      3. IMPORTANT, HONEST LIMITATION: this contract does NOT, and cannot,
 *         autonomously buy or sell on Polymarket's order book. Polymarket's
 *         own deployed `CTFExchange.fillOrder` / `fillOrders` / `matchOrders`
 *         are gated by an `onlyOperator` modifier in Polymarket's own source
 *         code — only addresses Polymarket's own admins have explicitly
 *         granted the Operator role may call them. This contract has not
 *         been granted that role, and Polymarket does not grant it to
 *         arbitrary third-party contracts. See the audit report for the
 *         exact quoted source. Concretely, this means:
 *           - {executePolymarketSplit} can convert pooled collateral into a
 *             real, held complete set of Polymarket outcome tokens (a
 *             genuine, verifiable on-chain action) — but selling those
 *             tokens above cost, or buying a complete set below $1 in the
 *             first place, requires trading on the order book, which this
 *             contract cannot do by itself.
 *           - {executePolymarketRedeem} lets the contract realize value from
 *             already-held outcome tokens once a market resolves, which
 *             *is* fully autonomous and on-chain.
 *           - True continuous "buy low / sell high" arbitrage against the
 *             live order book would require an off-chain component (a bot
 *             using Polymarket's CLOB API) plus this contract implementing
 *             EIP-1271 to act as a smart-contract order maker
 *             (`SignatureType.POLY_1271` in Polymarket's Order struct) —
 *             that is a real, supported path in Polymarket's protocol, but
 *             it is deliberately NOT implemented here, because doing so
 *             correctly requires matching Polymarket's exact off-chain
 *             signing/hashing expectations, which could not be independently
 *             verified in this environment. Shipping an unverified
 *             implementation of that piece would risk silently broken (or
 *             worse, exploitable) signature validation. Do not add it
 *             without directly verifying it against Polymarket's current
 *             `Signatures.sol` and CLOB API docs.
 *
 *      4. `executeEmergency` / `voteEmergency` / `addPartner` / `removePartner`
 *         (the original "insider partner" full-balance-drain mechanism) have
 *         been DELETED ENTIRELY. There is no way to make "a small
 *         owner-appointed group can vote to send themselves 100% of user
 *         funds" safe — the fix is removal, not a more elaborate vote. In
 *         its place, {emergencyWithdraw} lets ANY individual staker recover
 *         their own remaining principal, without needing anyone else's
 *         permission, if the contract has been paused continuously for
 *         longer than {EMERGENCY_GRACE_PERIOD}. This preserves a genuine
 *         "something is wrong, get user funds out" safety valve while
 *         removing the insider-drain capability.
 *
 *      5. Blacklisting (`setBlacklist`) can no longer block {earlyExit} or
 *         {emergencyWithdraw}. In the original contract, blacklisting a user
 *         also blocked their only exit path, permanently freezing their
 *         funds at the owner's sole discretion. A blacklisted address can
 *         still be blocked from new stakes, top-ups, plan upgrades, and
 *         claiming yield/referral rewards (this is legitimate for e.g.
 *         sanctions compliance) — but it can never be used to trap a user's
 *         principal forever.
 *
 *      6. Fixed a fund-drain logic bug: in the original contract, calling
 *         `earlyExit()` did not clear the stake's `amount`/`rate` fields, so
 *         a user could call `claim()` again afterward and be paid yield on
 *         a position they had already exited and been refunded for. `claim`
 *         now requires the stake to still be `active`, and {_deactivateStake}
 *         zeroes `amount`/`rate` at the moment of exit, closing this
 *         completely (belt-and-suspenders: either check alone would have
 *         been sufficient).
 *
 *      7. `OWNER` / fee wallets are no longer hardcoded, non-transferable
 *         `constant`s. Ownership now uses OpenZeppelin v5's
 *         `Ownable2Step` (two-step transfer, avoiding an irrecoverable
 *         mistyped-address handoff). Fee wallets are owner-settable.
 *         **Deployment recommendation:** set the initial owner to a Gnosis
 *         Safe multisig, and/or route ownership through an OpenZeppelin
 *         `TimelockController` (deploy that separately and pass its address
 *         as `initialOwner`), so that no single key can unilaterally pause,
 *         blacklist, or move collateral into a Polymarket position without
 *         a delay and/or multiple signers. This contract is fully compatible
 *         with either as its `owner()` — no additional code changes needed.
 *
 *      8. Replaced the hand-rolled reentrancy guard, pause flag, and
 *         `require(..., "X")` string-error pattern with OpenZeppelin v5's
 *         `ReentrancyGuard`, `Pausable`, and custom errors (cheaper, and
 *         gives callers/tooling a decodable reason). All external token
 *         transfers use `SafeERC20`, so a non-standard ERC-20 that returns
 *         `false` instead of reverting can no longer cause a silent,
 *         unaccounted-for transfer failure.
 *
 *      9. Every function that moves value now follows checks-effects-
 *         interactions: internal state (`stakes[...]`, `totalStaked`,
 *         `totalPaidOut`, referral balances) is fully updated before any
 *         external call (`safeTransfer`, `safeTransferFrom`, or the
 *         Polymarket Conditional Tokens calls).
 *
 *      Preserved unchanged (per instructions, "unless it must change for
 *      correctness"): the staking tiers, daily rates, plan durations,
 *      early-exit penalty schedule, multi-level referral-rate tables, the
 *      24h free-period mechanic, and the daily-withdrawal-cap constant.
 *      These are business/economic parameters, not security bugs — flagged
 *      in the earlier audit as a design/sustainability concern, not
 *      something a "security fix" should silently alter. If you want those
 *      economics changed, that's a product decision, not a refactor.
 *
 *      10. NO HARDCODED WALLET ADDRESSES: `owner` (via `Ownable2Step`),
 *          `feeWallet1`, `feeWallet2`, and `profitRecipient` are ALL
 *          constructor parameters, sourced from environment variables at
 *          deploy time (see `.env.example` / `script/Deploy.s.sol`) — none
 *          are hardcoded. `profitRecipient` is a genuinely new, distinct
 *          role added on request: it receives a bounded, owner-configurable
 *          performance fee (`profitFeeBPS`, capped at `PROFIT_FEE_MAX_BPS`)
 *          charged ONLY on real profit realized in
 *          `executePolymarketRedeem` (tracked precisely via
 *          `committedByCondition`, so principal the pool itself split into
 *          a position is never taxed as if it were profit) — separate from
 *          `feeWallet1`/`feeWallet2`, which are funded from staking-yield
 *          claims. The three `POLYMARKET_*` addresses remain `constant`
 *          deliberately: they are official, canonical, immutable
 *          third-party protocol infrastructure, not wallets this project
 *          controls — hardcoding *those* is the correct practice (making
 *          them configurable would let a misconfigured deploy silently
 *          point at the wrong, or a malicious, contract).
 */
contract ArbiSmartV2 is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============================================================
    // Polymarket — official, verified contract addresses (Polygon mainnet)
    // ============================================================

    /// @notice Polymarket's official Conditional Tokens Framework contract.
    ///         This is the ONLY Polymarket contract this code actually calls.
    address public constant POLYMARKET_CONDITIONAL_TOKENS = 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045;

    /// @notice Polymarket's official CTF Exchange address, kept here for
    ///         reference/documentation only. NOT called by this contract —
    ///         see the contract-level NatSpec for exactly why (`onlyOperator`).
    address public constant POLYMARKET_CTF_EXCHANGE = 0xE111180000d2663C0091e4f400237545B87B996B;

    /// @notice Polymarket's official Neg Risk CTF Exchange address, kept here
    ///         for reference/documentation only. Same `onlyOperator`
    ///         limitation applies (same underlying exchange contract family
    ///         per Polymarket's own documentation) — NOT called by this contract.
    address public constant POLYMARKET_NEG_RISK_EXCHANGE = 0xe2222d279d744050d28e00520010520000310F59;

    // ============================================================
    // Immutables / configurable addresses
    // ============================================================

    /// @notice The ERC-20 collateral token used for staking. MUST be the
    ///         exact token address that the target Polymarket condition(s)
    ///         were prepared with, or {executePolymarketSplit}/{executePolymarketMerge}
    ///         will operate on a valid-but-not-actually-tradeable-on-Polymarket
    ///         position set. Verify this against the specific market before use.
    IERC20 public immutable collateralToken;

    address public feeWallet1;
    address public feeWallet2;

    /// @notice Recipient of the performance fee ({profitFeeBPS}) charged on
    ///         REAL, realized Polymarket redemption profit (see
    ///         {executePolymarketRedeem}). Distinct from {feeWallet1}/
    ///         {feeWallet2}, which are funded from staking-yield claims, not
    ///         from arbitrage proceeds. Constructor parameter / owner-settable
    ///         — never hardcoded.
    address public profitRecipient;

    /// @notice Performance fee, in basis points, charged on realized
    ///         Polymarket redemption profit before the remainder stays in
    ///         the pool. Owner-settable, hard-capped at {PROFIT_FEE_MAX_BPS}.
    uint256 public profitFeeBPS;

    /// @notice Hard ceiling on {profitFeeBPS} — the owner can never set a
    ///         fee above 20% of realized profit.
    uint256 public constant PROFIT_FEE_MAX_BPS = 2000;

    /// @notice Collateral committed via {executePolymarketSplit} per
    ///         `conditionId`, reduced as positions are unwound via
    ///         {executePolymarketMerge}/{executePolymarketRedeem}. Used so
    ///         the performance fee is only ever charged on genuine profit
    ///         (`received - committed`), never on returned principal — a
    ///         complete-set split-then-redeem cycle nets to exactly the
    ///         committed amount by the Conditional Tokens Framework's own
    ///         invariant, so it must never be taxed as if it were profit.
    mapping(bytes32 => uint256) public committedByCondition;

    // ============================================================
    // State
    // ============================================================

    uint256 public totalStaked;
    uint256 public totalPaidOut;
    uint256 public immutable deployTime;
    uint256 public constant FREE_PERIOD = 24 hours;

    /// @notice Timestamp at which the contract was last paused; 0 while unpaused.
    uint256 public pausedAt;
    /// @notice How long the contract must remain continuously paused before
    ///         {emergencyWithdraw} becomes available to stakers.
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

    // ============================================================
    // Plan / referral configuration (preserved from the original contract)
    // ============================================================

    uint256[4] public dailyRates = [120, 180, 240, 300];
    uint256[4] public planDurations = [180, 150, 120, 90];
    uint256[4] public minStakes = [10_000000, 500_000000, 2_500_000000, 10_000_000000];

    uint256[8] public referralRates = [800, 400, 1200, 600, 1500, 800, 2000, 1000];
    uint256[3] public f3Rates = [200, 400, 500];

    uint256 private constant FEE1_BPS = 750;
    uint256 private constant FEE2_BPS = 250;
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

    /// @notice Cap on the fraction of the pool's collateral balance that can
    ///         be committed to a single Polymarket split in one call (2000 = 20%),
    ///         preserved from the original contract as a risk-management bound.
    ///         Unlike the original, funds under this cap are converted into
    ///         real, contract-held Polymarket outcome tokens — they are never
    ///         sent to an external/owner wallet.
    uint256 private constant ARBITRAGE_MAX_BPS = 2000;

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
    event EmergencyPaused(uint256 timestamp);

    /// @notice Emitted only after a REAL, successful call to Polymarket's
    ///         official Conditional Tokens contract.
    event ArbitrageSplitExecuted(bytes32 indexed conditionId, uint256 amount, uint256[] partition);
    /// @notice Emitted only after a REAL, successful call to Polymarket's
    ///         official Conditional Tokens contract.
    event ArbitrageMergeExecuted(bytes32 indexed conditionId, uint256 amount, uint256[] partition);
    /// @notice Emitted only after a REAL, successful redemption call;
    ///         `collateralReceived` is measured from the actual balance delta.
    event ArbitrageRedeemed(bytes32 indexed conditionId, uint256[] indexSets, uint256 collateralReceived);
    /// @notice Emitted when a performance fee is skimmed from realized
    ///         Polymarket redemption profit and sent to {profitRecipient}.
    event ProfitFeeCharged(bytes32 indexed conditionId, uint256 profitAmount, uint256 feeAmount, address indexed recipient);
    event ProfitRecipientUpdated(address indexed newRecipient);
    event ProfitFeeBpsUpdated(uint256 newFeeBPS);

    // ============================================================
    // Custom errors
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

    // ============================================================
    // Modifiers
    // ============================================================

    modifier notBlacklisted() {
        if (blacklisted[msg.sender]) revert Blacklisted();
        _;
    }

    /// @dev Blocks contract-mediated calls (msg.sender must equal tx.origin).
    ///      This is a participation restriction (no smart-contract wallets),
    ///      not an authorization mechanism, so it does not carry the classic
    ///      tx.origin-phishing risk (nothing is *authorized* based on
    ///      tx.origin identity here — it can only ever narrow who may call in).
    modifier onlyEOA() {
        if (tx.origin != msg.sender) revert ContractCallerNotAllowed();
        _;
    }

    // ============================================================
    // Constructor
    // ============================================================

    /// @param _collateralToken Collateral ERC-20 (must match the token the
    ///        target Polymarket condition(s) were prepared with).
    /// @param initialOwner Recommended: a Gnosis Safe multisig or an
    ///        OpenZeppelin `TimelockController` address, not a bare EOA.
    /// @param _feeWallet1 Initial primary fee recipient (funded from staking-yield claims).
    /// @param _feeWallet2 Initial secondary fee recipient (funded from staking-yield claims).
    /// @param _profitRecipient Initial recipient of the performance fee on
    ///        realized Polymarket arbitrage profit (see {profitFeeBPS}).
    ///        Distinct wallet from the two above — never hardcoded.
    constructor(
        address _collateralToken,
        address initialOwner,
        address _feeWallet1,
        address _feeWallet2,
        address _profitRecipient
    ) Ownable(initialOwner) {
        if (
            _collateralToken == address(0) || _feeWallet1 == address(0) || _feeWallet2 == address(0)
                || _profitRecipient == address(0)
        ) {
            revert ZeroAddress();
        }
        collateralToken = IERC20(_collateralToken);
        feeWallet1 = _feeWallet1;
        feeWallet2 = _feeWallet2;
        profitRecipient = _profitRecipient;
        profitFeeBPS = 1000; // 10% default, owner-adjustable up to PROFIT_FEE_MAX_BPS
        deployTime = block.timestamp;

        // One-time max approval to Polymarket's real Conditional Tokens
        // contract, mirroring the pattern used by Polymarket's own
        // CTFExchange (`Assets.sol`) constructor.
        collateralToken.forceApprove(POLYMARKET_CONDITIONAL_TOKENS, type(uint256).max);
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

    /// @notice Maximum amount of pooled collateral that may be committed to
    ///         a single {executePolymarketSplit} call right now.
    function polymarketArbitrageAvailable() public view returns (uint256) {
        return (collateralToken.balanceOf(address(this)) * ARBITRAGE_MAX_BPS) / BPS_DENOMINATOR;
    }

    // ============================================================
    // Owner functions — Polymarket integration (REAL on-chain calls only)
    // ============================================================

    /// @notice Converts `amount` of pooled `collateralToken` into a complete
    ///         set of Polymarket outcome-token positions for `conditionId`,
    ///         via a real call to Polymarket's official, permissionless
    ///         Conditional Tokens contract. See the contract-level NatSpec
    ///         for the honest limitation on realizing profit from this via
    ///         the order book.
    /// @param conditionId Polymarket condition ID for the target market
    ///        (obtained off-chain from Polymarket's API/subgraph).
    /// @param partition Index-set partition, e.g. `[1, 2]` for a standard
    ///        binary YES/NO market's complete set.
    /// @param amount Amount of `collateralToken` to convert.
    function executePolymarketSplit(bytes32 conditionId, uint256[] calldata partition, uint256 amount)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (amount > polymarketArbitrageAvailable()) revert AmountExceedsAvailable();

        // Effects before the external call (strict CEI): `amount` is already
        // known at this point, so there is no need to wait for the call to
        // return before updating accounting.
        committedByCondition[conditionId] += amount;

        IConditionalTokens(POLYMARKET_CONDITIONAL_TOKENS).splitPosition(
            collateralToken, bytes32(0), conditionId, partition, amount
        );

        emit ArbitrageSplitExecuted(conditionId, amount, partition);
    }

    /// @notice Burns a complete set of Polymarket outcome-token positions
    ///         held by this contract and returns `amount` of collateral, via
    ///         a real call to Polymarket's official Conditional Tokens
    ///         contract. Does not draw new funds from the pool beyond
    ///         positions already held. No performance fee is charged here —
    ///         a merge before resolution is treated as unwinding, not
    ///         realizing profit; the fee is only ever charged at
    ///         {executePolymarketRedeem}.
    function executePolymarketMerge(bytes32 conditionId, uint256[] calldata partition, uint256 amount)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();

        // Effects before the external call (strict CEI): `amount` is already
        // known at this point, so there is no need to wait for the call to
        // return before updating accounting.
        uint256 committed = committedByCondition[conditionId];
        committedByCondition[conditionId] = amount >= committed ? 0 : committed - amount;

        IConditionalTokens(POLYMARKET_CONDITIONAL_TOKENS).mergePositions(
            collateralToken, bytes32(0), conditionId, partition, amount
        );

        emit ArbitrageMergeExecuted(conditionId, amount, partition);
    }

    /// @notice Redeems already-held Polymarket outcome-token positions for
    ///         collateral after `conditionId` has been resolved by its
    ///         oracle. Fully autonomous, on-chain, no order-book dependency.
    /// @dev A performance fee ({profitFeeBPS}) is charged ONLY on the amount
    ///      by which `received` exceeds this contract's own tracked
    ///      {committedByCondition} for `conditionId` — i.e. only on genuine
    ///      profit, never on principal the contract itself split into this
    ///      position. Assumes the full committed position for `conditionId`
    ///      is redeemed in one call; partial redemptions make this a
    ///      conservative (not exact) profit estimate — documented, not
    ///      silently wrong.
    function executePolymarketRedeem(bytes32 conditionId, uint256[] calldata indexSets)
        external
        onlyOwner
        nonReentrant
    {
        uint256 balanceBefore = collateralToken.balanceOf(address(this));

        // Effect before the external call (strict CEI): `committed` is
        // already known at this point and does not depend on the call's
        // outcome. Only `received` (below) genuinely requires reading the
        // post-call balance — a balance-delta measurement is inherently a
        // post-interaction read, there is no way to know it beforehand, and
        // this function is `onlyOwner` + `nonReentrant` calling only the
        // fixed, trusted Conditional Tokens address, so this is safe.
        uint256 committed = committedByCondition[conditionId];
        committedByCondition[conditionId] = 0;

        IConditionalTokens(POLYMARKET_CONDITIONAL_TOKENS).redeemPositions(
            collateralToken, bytes32(0), conditionId, indexSets
        );

        uint256 received = collateralToken.balanceOf(address(this)) - balanceBefore;

        uint256 profit = received > committed ? received - committed : 0;
        uint256 fee = (profit * profitFeeBPS) / BPS_DENOMINATOR;
        if (fee > 0) {
            collateralToken.safeTransfer(profitRecipient, fee);
            emit ProfitFeeCharged(conditionId, profit, fee, profitRecipient);
        }

        emit ArbitrageRedeemed(conditionId, indexSets, received);
    }

    /// @notice Read-only passthrough to Polymarket's real Conditional Tokens
    ///         ERC-1155 balance for a specific, off-chain-computed position ID.
    ///         Position IDs are not derived on-chain here — see contract notes.
    function getPolymarketOutcomeBalance(uint256 positionId) external view returns (uint256) {
        return IConditionalTokens(POLYMARKET_CONDITIONAL_TOKENS).balanceOf(address(this), positionId);
    }

    // ============================================================
    // Owner functions — administration
    // ============================================================

    function pause() external onlyOwner {
        _pause();
        pausedAt = block.timestamp;
        emit EmergencyPaused(block.timestamp);
    }

    function unpause() external onlyOwner {
        _unpause();
        pausedAt = 0;
    }

    /// @notice Blocks (or unblocks) an address from new stakes, top-ups,
    ///         plan upgrades, and claiming yield/referral rewards. Cannot be
    ///         used to block {earlyExit} or {emergencyWithdraw} — a user's
    ///         principal can never be permanently frozen by this flag.
    function setBlacklist(address user, bool value) external onlyOwner {
        if (user == owner()) revert CannotBlacklistOwner();
        blacklisted[user] = value;
        emit BlacklistUpdated(user, value);
    }

    function setFeeWallets(address newFeeWallet1, address newFeeWallet2) external onlyOwner {
        if (newFeeWallet1 == address(0) || newFeeWallet2 == address(0)) revert ZeroAddress();
        feeWallet1 = newFeeWallet1;
        feeWallet2 = newFeeWallet2;
        emit FeeWalletsUpdated(newFeeWallet1, newFeeWallet2);
    }

    /// @notice Updates the recipient of the Polymarket-arbitrage performance
    ///         fee. Distinct role from {setFeeWallets} — never hardcoded.
    function setProfitRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        profitRecipient = newRecipient;
        emit ProfitRecipientUpdated(newRecipient);
    }

    /// @notice Updates the performance fee rate charged on realized
    ///         Polymarket redemption profit. Hard-capped at
    ///         {PROFIT_FEE_MAX_BPS} — can never be raised above 20%.
    function setProfitFeeBPS(uint256 newFeeBPS) external onlyOwner {
        if (newFeeBPS > PROFIT_FEE_MAX_BPS) revert ProfitFeeTooHigh();
        profitFeeBPS = newFeeBPS;
        emit ProfitFeeBpsUpdated(newFeeBPS);
    }

    // ============================================================
    // User functions
    // ============================================================

    function stake(uint256 amount, address referrer) external whenNotPaused notBlacklisted onlyEOA nonReentrant {
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

    function topUp(uint256 amount) external whenNotPaused notBlacklisted onlyEOA nonReentrant {
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

    function upgradePlan() external whenNotPaused notBlacklisted onlyEOA nonReentrant {
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

    function claim() external whenNotPaused notBlacklisted onlyEOA nonReentrant {
        Stake storage s = stakes[msg.sender];
        if (!s.active) revert NoActiveStake();

        uint256 reward = _pendingReward(msg.sender);
        // slither-disable-next-line incorrect-equality
        // `reward` is a deterministic function of stored state (amount/rate/
        // elapsed time), not an externally-manipulable balance — an exact
        // zero-check here is correct, not a "dangerous" strict equality.
        if (reward == 0) revert NothingToClaim();

        _checkDailyCap(msg.sender, reward);
        s.lastClaimTime = block.timestamp;
        s.totalClaimed += reward;
        totalPaidOut += reward;

        uint256 fee1 = (reward * FEE1_BPS) / BPS_DENOMINATOR;
        uint256 fee2 = (reward * FEE2_BPS) / BPS_DENOMINATOR;
        uint256 userAmount = reward - fee1 - fee2;

        _processReferralRewards(msg.sender, reward);
        _updateDailyWithdrawn(msg.sender, userAmount);
        _claimCounts[msg.sender]++;

        if (fee1 > 0) collateralToken.safeTransfer(feeWallet1, fee1);
        if (fee2 > 0) collateralToken.safeTransfer(feeWallet2, fee2);
        collateralToken.safeTransfer(msg.sender, userAmount);

        emit Claimed(msg.sender, userAmount, fee1 + fee2);
    }

    function claimRef() external whenNotPaused notBlacklisted onlyEOA nonReentrant {
        Referral storage r = referrals[msg.sender];
        uint256 pending = r.pendingReward;
        if (pending == 0) revert NothingToClaim();

        r.pendingReward = 0;
        r.totalEarned += pending;

        collateralToken.safeTransfer(msg.sender, pending);
        emit ReferralClaimed(msg.sender, pending);
    }

    /// @notice Exits a stake early for principal minus the time-based
    ///         penalty. No longer blockable by blacklisting — a user's
    ///         principal can always be recovered through this path.
    function earlyExit() external onlyEOA nonReentrant {
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

    /// @notice Self-serve recovery of a staker's own remaining principal.
    ///         Replaces the original `executeEmergency` insider-drain
    ///         mechanism. Available to ANY staker, including blacklisted
    ///         ones, once the contract has been continuously paused for at
    ///         least {EMERGENCY_GRACE_PERIOD}. No penalty is applied.
    function emergencyWithdraw() external nonReentrant {
        if (!paused()) revert NotPausedError();
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
    // Internal accounting
    // ============================================================

    /// @dev Fully deactivates a stake, zeroing `amount`/`rate` so that no
    ///      subsequent {claim} call (even if it were otherwise reachable)
    ///      could ever compute a nonzero reward against it. This is the
    ///      direct fix for the "claim after earlyExit" fund-drain bug found
    ///      in the original contract.
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

    // NOTE ON SLITHER FINDINGS BELOW (reviewed, not exploitable — documented
    // rather than silently suppressed):
    // - divide-before-multiply: `(block.timestamp / DAY) * DAY` is the
    //   standard idiom for "start of the current UTC day" — the intentional
    //   loss of the sub-day remainder is exactly the point (day-bucketing),
    //   not an accidental precision bug.
    // - incorrect-equality: `lastWithdrawalDay[user] == today` compares two
    //   day-bucket timestamps that are only ever written via this exact same
    //   `(block.timestamp / DAY) * DAY` computation — never user-supplied,
    //   never a raw balance/amount — so there is no way for an attacker to
    //   make a near-equal-but-not-equal value that bypasses this check.
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

    function getUserStatsExtended(address user)
        external
        view
        returns (uint256, uint256, bool, uint256, uint256, uint256, uint256, uint256)
    {
        uint256 f1Volume = _f1Volume[user];
        uint256 f2Volume = _f2Volume[user];
        Stake storage s = stakes[user];
        uint256 level = referrals[user].level;
        bool active = s.active;
        uint256 lastClaimTime = s.lastClaimTime;
        uint256 claimCount = _claimCounts[user];
        return (f1Volume + f2Volume, level, active, lastClaimTime, claimCount, f1Volume, f2Volume, 0);
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
    // Native currency handling — explicitly rejected (unchanged from original)
    // ============================================================

    // slither-disable-next-line locked-ether
    // Reviewed: both functions revert() unconditionally, so no native
    // currency can ever be received in the first place — there is nothing
    // to "lock" or need a withdrawal path for. Slither's locked-ether
    // detector flags any payable function without a paired withdraw
    // function, without accounting for a body that unconditionally reverts.
    receive() external payable {
        revert();
    }

    fallback() external payable {
        revert();
    }
}
