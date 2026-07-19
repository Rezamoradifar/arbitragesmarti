// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * ReferralRegistry
 * -----------------------------------------------------------------------
 * Multi-level referral program. Every wagered game routes its referral
 * fee (set in BackgammonCore, default 10% of the pot) here, and this
 * contract pays every eligible upline referrer INSTANTLY, in the same
 * transaction that finishes the game -- no separate claim step.
 *
 * How referral chains form:
 *   A new player calls setReferrer(referrerAddress) once (typically
 *   right after connecting their wallet via a ?ref=0x... link in the
 *   frontend). This is self-service and permissionless; it does not
 *   require the referrer's cooperation.
 *
 * How a payout splits:
 *   BackgammonCore sends the referral fee for a finished game here and
 *   names both players (playerA, playerB). The fee is split 50/50
 *   between "playerA's referral chain" and "playerB's referral chain"
 *   -- i.e. each player's wager equally funds their own upline. Within
 *   one player's half, levelBps[0] goes to their direct referrer,
 *   levelBps[1] to that referrer's referrer, and so on. Any level with
 *   no referrer (chain too short, or player was never referred) is not
 *   paid -- that unclaimed share flows back to feeRecipient in the same
 *   transaction, so funds are never stuck.
 * -----------------------------------------------------------------------
 */
contract ReferralRegistry is ReentrancyGuard, Ownable {
    mapping(address => address) public referrerOf;
    mapping(address => bool) public authorizedCallers; // e.g. BackgammonCore, BackgammonTournament
    address public feeRecipient;

    // Default 3 levels: 50% / 30% / 20% of a player's half of the referral pool.
    uint16[] public levelBps = [5000, 3000, 2000];

    event ReferrerSet(address indexed user, address indexed referrer);
    event CommissionPaid(address indexed referrer, address indexed sourcePlayer, uint8 level, uint256 amount, address token);
    event RemainderSwept(uint256 amount, address token);
    event CallerAuthorized(address indexed caller, bool allowed);

    constructor(address _feeRecipient) Ownable(msg.sender) {
        feeRecipient = _feeRecipient;
    }

    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender], "not authorized");
        _;
    }

    // ---------------------------------------------------------------
    // Referral graph
    // ---------------------------------------------------------------

    /// @notice Set your upline referrer once. Cannot be changed afterward
    /// (prevents last-minute re-routing of an already-active chain).
    function setReferrer(address referrer) external {
        require(referrer != address(0), "zero referrer");
        require(referrer != msg.sender, "cannot refer yourself");
        require(referrerOf[msg.sender] == address(0), "referrer already set");
        require(!_wouldCreateCycle(msg.sender, referrer), "cycle detected");

        referrerOf[msg.sender] = referrer;
        emit ReferrerSet(msg.sender, referrer);
    }

    function _wouldCreateCycle(address user, address referrer) internal view returns (bool) {
        address cur = referrer;
        for (uint256 i = 0; i < levelBps.length + 2; i++) {
            if (cur == address(0)) return false;
            if (cur == user) return true;
            cur = referrerOf[cur];
        }
        return false;
    }

    function getChain(address user, uint256 maxLevels) external view returns (address[] memory chain) {
        chain = new address[](maxLevels);
        address cur = referrerOf[user];
        for (uint256 i = 0; i < maxLevels; i++) {
            chain[i] = cur;
            if (cur == address(0)) break;
            cur = referrerOf[cur];
        }
    }

    // ---------------------------------------------------------------
    // Commission distribution (called by BackgammonCore / Tournament)
    // ---------------------------------------------------------------

    /// @notice Splits `amount` 50/50 between playerA's and playerB's referral
    /// chains and pays every eligible level instantly. Unclaimed share is
    /// swept to feeRecipient in the same call. For BNB, caller sends
    /// `amount` as msg.value. For ERC20, caller must have already
    /// transferred `amount` of `token` to this contract before calling.
    function distributeCommission(
        address playerA,
        address playerB,
        address token,
        uint256 amount
    ) external payable onlyAuthorized nonReentrant returns (uint256 remainder) {
        if (token == address(0)) {
            require(msg.value == amount, "bad BNB amount");
        } else {
            require(msg.value == 0, "no BNB expected for token payout");
        }

        uint256 half = amount / 2;
        uint256 otherHalf = amount - half; // handles odd wei without losing a unit

        uint256 paidA = _payChain(playerA, half, token, playerA);
        uint256 paidB = _payChain(playerB, otherHalf, token, playerB);

        remainder = amount - paidA - paidB;
        if (remainder > 0) {
            _send(feeRecipient, remainder, token);
            emit RemainderSwept(remainder, token);
        }
    }

    function _payChain(address player, uint256 pool, address token, address sourcePlayer) internal returns (uint256 paid) {
        address cur = referrerOf[player];
        for (uint8 lvl = 0; lvl < levelBps.length; lvl++) {
            if (cur == address(0)) break;
            uint256 amt = (pool * levelBps[lvl]) / 10000;
            if (amt > 0) {
                _send(cur, amt, token);
                paid += amt;
                emit CommissionPaid(cur, sourcePlayer, lvl, amt, token);
            }
            cur = referrerOf[cur];
        }
    }

    function _send(address to, uint256 amount, address token) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            (bool s, ) = payable(to).call{value: amount}("");
            require(s, "referral payout failed");
        } else {
            IERC20(token).transfer(to, amount);
        }
    }

    // ---------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------

    function setAuthorizedCaller(address caller, bool allowed) external onlyOwner {
        authorizedCallers[caller] = allowed;
        emit CallerAuthorized(caller, allowed);
    }

    function setLevelBps(uint16[] calldata newLevels) external onlyOwner {
        uint256 total;
        for (uint256 i = 0; i < newLevels.length; i++) total += newLevels[i];
        require(total <= 10000, "levels exceed 100%");
        delete levelBps;
        for (uint256 i = 0; i < newLevels.length; i++) levelBps.push(newLevels[i]);
    }

    function setFeeRecipient(address r) external onlyOwner {
        feeRecipient = r;
    }

    /// @notice Rescue path for ERC20 tokens that end up stuck here (e.g. an
    /// authorized caller transferred tokens but its distributeCommission
    /// call then reverted/was never made). Native BNB has no equivalent
    /// stuck-fund case since distributeCommission is payable and atomic.
    function rescueToken(address token, uint256 amount, address to) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
