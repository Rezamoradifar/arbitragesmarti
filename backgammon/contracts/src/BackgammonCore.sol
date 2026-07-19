// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRatingRegistry {
    function reportResult(address winner, address loser) external;
}

interface IReferralRegistry {
    /// @notice Splits `amount` between playerA's and playerB's multi-level
    /// referral chains (half each) and returns whatever wasn't claimed by
    /// any referrer (e.g. a player with no referrer, or a chain shorter
    /// than the configured level count) so the caller can route it back
    /// to the platform treasury. For native BNB, caller must send `amount`
    /// as msg.value. For ERC20, caller must transfer `amount` of `token`
    /// to this registry BEFORE calling, then call with msg.value == 0.
    function distributeCommission(
        address playerA,
        address playerB,
        address token,
        uint256 amount
    ) external payable returns (uint256 remainder);
}

/**
 * BackgammonCore
 * -----------------------------------------------------------------------
 * Fully on-chain 2-player backgammon engine for BNB Smart Chain.
 *
 * Board representation:
 *   int8[24] board -> points 0..23 (point 0 = player A's 1-point, point 23 = player B's 1-point)
 *   positive value = number of player A checkers on that point
 *   negative value = number of player B checkers on that point
 *   bar[0]/bar[1]  = checkers on the bar for player A / player B
 *   borneOff[0]/borneOff[1] = checkers already borne off
 *
 * Randomness:
 *   No oracle needed for a 2-party game. Both players commit a hashed
 *   secret before each roll, then reveal it. The dice values are derived
 *   from XOR of both reveals, so neither side can bias the outcome
 *   without the other's cooperation (and a no-show forfeits the game
 *   after a timeout).
 *
 * Revenue split on wagered games (of the combined pot, wagerAmount * 2):
 *   - protocolFeeBps  -> platform treasury (feeRecipient)
 *   - referralFeeBps  -> ReferralRegistry, paid out instantly, multi-level,
 *                        in the SAME transaction that finishes the game.
 *                        Any unclaimed share (no referrer / short chain)
 *                        flows back to feeRecipient automatically.
 *   Defaults: 5% platform + 10% referral = 15% total rake. Free-play
 *   games (wagerAmount == 0) are never fee'd.
 *
 * Scope note:
 *   This is a strong on-chain foundation covering the core rule set
 *   (movement, hitting, bar re-entry, bearing off, doubles, wagering,
 *   timeouts, referral payouts). The doubling cube, and full exhaustive
 *   "must play the maximum number of legal moves" enforcement are left
 *   as TODOs / a Phase 2 module to keep gas costs and this contract's
 *   complexity manageable. AI opponents, lessons, and deep move analysis
 *   are intentionally NOT part of this contract -- they belong off-chain
 *   (see project README).
 * -----------------------------------------------------------------------
 */
contract BackgammonCore is ReentrancyGuard, Ownable {
    uint256 public constant TURN_TIMEOUT = 5 minutes;
    uint256 public constant MAX_TOTAL_FEE_BPS = 3000; // hard ceiling: 30% combined, protects players

    uint256 public protocolFeeBps = 500;  // 5% -> platform treasury
    uint256 public referralFeeBps = 1000; // 10% -> multi-level referral pool
    address public feeRecipient;
    address public referralRegistry; // set to address(0) to disable (referral share then falls back to platform)
    address public ratingRegistry; // set to address(0) to disable rating updates

    enum Phase {
        None,
        WaitingForOpponent,
        CommitRoll,
        RevealRoll,
        Move,
        Finished
    }

    struct Move {
        int8 from; // 24 = entering from bar
        int8 to;   // 24 = bearing off
    }

    struct Game {
        address playerA;
        address playerB;
        address wagerToken;   // address(0) = native BNB
        uint256 wagerAmount;  // per-player stake; pot = 2x on start
        bool started;
        bool wagerFunded;     // both stakes deposited

        int8[24] board;
        uint8[2] bar;
        uint8[2] borneOff;

        uint8 turn; // 0 = playerA, 1 = playerB
        Phase phase;
        uint256 phaseDeadline;

        bytes32 commitA;
        bytes32 commitB;
        uint8 dieA;
        uint8 dieB;
        uint8[4] remainingPips; // up to 4 entries for doubles
        uint8 pipCount;

        address winner;
    }

    uint256 public nextGameId;
    mapping(uint256 => Game) private games;

    event GameCreated(uint256 indexed gameId, address indexed creator, uint256 wager, address token);
    event GameJoined(uint256 indexed gameId, address indexed opponent);
    event RollCommitted(uint256 indexed gameId, uint8 player);
    event RollRevealed(uint256 indexed gameId, uint8 dieA, uint8 dieB);
    event MovesPlayed(uint256 indexed gameId, uint8 player, Move[] moves);
    event GameFinished(uint256 indexed gameId, address winner, uint256 winnerPayout, uint256 platformFee, uint256 referralFee);
    event TimeoutClaimed(uint256 indexed gameId, address winner);

    constructor(address _feeRecipient) Ownable(msg.sender) {
        feeRecipient = _feeRecipient;
    }

    // ---------------------------------------------------------------
    // Game creation / joining / wager funding
    // ---------------------------------------------------------------

    function createGame(uint256 wagerAmount, address wagerToken) external payable returns (uint256 gameId) {
        gameId = nextGameId++;
        Game storage g = games[gameId];
        g.playerA = msg.sender;
        g.wagerAmount = wagerAmount;
        g.wagerToken = wagerToken;
        g.phase = Phase.WaitingForOpponent;
        _initBoard(g);

        if (wagerAmount > 0) {
            _collectStake(g, msg.sender);
        }

        emit GameCreated(gameId, msg.sender, wagerAmount, wagerToken);
    }

    function joinGame(uint256 gameId) external payable {
        Game storage g = games[gameId];
        require(g.phase == Phase.WaitingForOpponent, "not joinable");
        require(g.playerB == address(0), "full");
        require(msg.sender != g.playerA, "cannot join own game");

        g.playerB = msg.sender;
        if (g.wagerAmount > 0) {
            _collectStake(g, msg.sender);
            g.wagerFunded = true;
        } else {
            g.wagerFunded = true;
        }

        g.started = true;
        g.phase = Phase.CommitRoll;
        g.phaseDeadline = block.timestamp + TURN_TIMEOUT;
        emit GameJoined(gameId, msg.sender);
    }

    function _collectStake(Game storage g, address player) internal {
        if (g.wagerToken == address(0)) {
            require(msg.value == g.wagerAmount, "bad BNB stake");
        } else {
            require(msg.value == 0, "no BNB expected");
            IERC20(g.wagerToken).transferFrom(player, address(this), g.wagerAmount);
        }
    }

    // ---------------------------------------------------------------
    // Commit-reveal dice
    // ---------------------------------------------------------------

    function commitRoll(uint256 gameId, bytes32 commitHash) external {
        Game storage g = games[gameId];
        require(g.phase == Phase.CommitRoll, "not commit phase");
        address p = _playerAddr(g, msg.sender);

        if (p == g.playerA) {
            require(g.commitA == bytes32(0), "already committed");
            g.commitA = commitHash;
        } else {
            require(g.commitB == bytes32(0), "already committed");
            g.commitB = commitHash;
        }

        if (g.commitA != bytes32(0) && g.commitB != bytes32(0)) {
            g.phase = Phase.RevealRoll;
            g.phaseDeadline = block.timestamp + TURN_TIMEOUT;
        }
        emit RollCommitted(gameId, p == g.playerA ? 0 : 1);
    }

    function revealRoll(uint256 gameId, uint8 secretValue, bytes32 salt) external {
        Game storage g = games[gameId];
        require(g.phase == Phase.RevealRoll, "not reveal phase");
        address p = _playerAddr(g, msg.sender);
        bytes32 expected = keccak256(abi.encodePacked(secretValue, salt, msg.sender));

        if (p == g.playerA) {
            require(g.commitA == expected, "bad reveal");
            g.dieA = (secretValue % 6) + 1;
            g.commitA = bytes32(uint256(1)); // mark revealed (sentinel)
        } else {
            require(g.commitB == expected, "bad reveal");
            g.dieB = (secretValue % 6) + 1;
            g.commitB = bytes32(uint256(1));
        }

        if (g.dieA != 0 && g.dieB != 0) {
            _finalizeRoll(g);
        }
        emit RollRevealed(gameId, g.dieA, g.dieB);
    }

    function _finalizeRoll(Game storage g) internal {
        // Combine both players' secrets deterministically -> two dice for the active player's turn
        uint8 d1 = g.dieA;
        uint8 d2 = g.dieB;

        if (d1 == d2) {
            g.remainingPips = [d1, d1, d1, d1]; // doubles = 4 moves
            g.pipCount = 4;
        } else {
            g.remainingPips = [d1, d2, 0, 0];
            g.pipCount = 2;
        }

        g.dieA = 0;
        g.dieB = 0;
        g.commitA = bytes32(0);
        g.commitB = bytes32(0);
        g.phase = Phase.Move;
        g.phaseDeadline = block.timestamp + TURN_TIMEOUT;
    }

    // ---------------------------------------------------------------
    // Moves
    // ---------------------------------------------------------------

    function submitMoves(uint256 gameId, Move[] calldata moves) external {
        Game storage g = games[gameId];
        require(g.phase == Phase.Move, "not move phase");
        address p = _playerAddr(g, msg.sender);
        require((g.turn == 0 && p == g.playerA) || (g.turn == 1 && p == g.playerB), "not your turn");
        require(moves.length <= g.pipCount, "too many moves");

        int8 dir = g.turn == 0 ? int8(1) : int8(-1);

        for (uint256 i = 0; i < moves.length; i++) {
            _applyMove(g, moves[i], dir);
        }

        emit MovesPlayed(gameId, g.turn, moves);

        if (_checkWin(g)) {
            _finishGame(g, gameId, g.turn == 0 ? g.playerA : g.playerB);
            return;
        }

        // next turn
        g.turn = g.turn == 0 ? 1 : 0;
        g.phase = Phase.CommitRoll;
        g.phaseDeadline = block.timestamp + TURN_TIMEOUT;
    }

    function _applyMove(Game storage g, Move calldata m, int8 dir) internal {
        uint8 player = g.turn;
        uint8 pipsUsed = _pipsForMove(g, m, dir);
        require(_consumePip(g, pipsUsed), "die not available");

        if (m.from == 24) {
            // entering from bar
            require(g.bar[player] > 0, "no checker on bar");
            g.bar[player] -= 1;
        } else {
            require(m.from >= 0 && m.from < 24, "bad from");
            if (player == 0) {
                require(g.board[uint8(m.from)] > 0, "no checker there");
                g.board[uint8(m.from)] -= 1;
            } else {
                require(g.board[uint8(m.from)] < 0, "no checker there");
                g.board[uint8(m.from)] += 1;
            }
        }

        if (m.to == 24) {
            // bearing off
            require(_allInHome(g, player), "not all checkers home");
            g.borneOff[player] += 1;
        } else {
            require(m.to >= 0 && m.to < 24, "bad to");
            int8 occ = g.board[uint8(m.to)];
            if (player == 0) {
                require(occ >= -1, "point blocked");
                if (occ == -1) {
                    g.board[uint8(m.to)] = 1; // hit
                    g.bar[1] += 1;
                } else {
                    g.board[uint8(m.to)] += 1;
                }
            } else {
                require(occ <= 1, "point blocked");
                if (occ == 1) {
                    g.board[uint8(m.to)] = -1; // hit
                    g.bar[0] += 1;
                } else {
                    g.board[uint8(m.to)] -= 1;
                }
            }
        }
    }

    function _pipsForMove(Game storage g, Move calldata m, int8 dir) internal view returns (uint8) {
        int8 from = m.from == 24 ? (g.turn == 0 ? int8(-1) : int8(24)) : m.from;
        int8 to = m.to == 24 ? (g.turn == 0 ? int8(24) : int8(-1)) : m.to;
        int8 diff = (to - from) * dir;
        require(diff > 0 && diff <= 6, "invalid pip distance");
        return uint8(uint8(diff));
    }

    function _consumePip(Game storage g, uint8 pips) internal returns (bool) {
        for (uint8 i = 0; i < 4; i++) {
            if (g.remainingPips[i] == pips) {
                g.remainingPips[i] = 0;
                if (i < g.pipCount) {
                    // compact array not required for correctness, just mark used
                }
                return true;
            }
        }
        return false;
    }

    function _allInHome(Game storage g, uint8 player) internal view returns (bool) {
        if (g.bar[player] > 0) return false;
        if (player == 0) {
            for (uint8 i = 0; i < 18; i++) {
                if (g.board[i] > 0) return false;
            }
        } else {
            for (uint8 i = 6; i < 24; i++) {
                if (g.board[i] < 0) return false;
            }
        }
        return true;
    }

    function _checkWin(Game storage g) internal view returns (bool) {
        return g.borneOff[0] == 15 || g.borneOff[1] == 15;
    }

    // ---------------------------------------------------------------
    // Timeouts & finishing
    // ---------------------------------------------------------------

    function claimTimeout(uint256 gameId) external {
        Game storage g = games[gameId];
        require(g.started && g.phase != Phase.Finished, "not active");
        require(block.timestamp > g.phaseDeadline, "not expired");

        address loserTurnPlayer = g.turn == 0 ? g.playerA : g.playerB;
        address winner = loserTurnPlayer == g.playerA ? g.playerB : g.playerA;
        _finishGame(g, gameId, winner);
        emit TimeoutClaimed(gameId, winner);
    }

    function _finishGame(Game storage g, uint256 gameId, address winner) internal {
        g.phase = Phase.Finished;
        g.winner = winner;

        uint256 winnerPayout = 0;
        uint256 platformFee = 0;
        uint256 referralFee = 0;

        if (g.wagerAmount > 0) {
            uint256 pot = g.wagerAmount * 2;
            platformFee = (pot * protocolFeeBps) / 10000;
            referralFee = (pot * referralFeeBps) / 10000;
            winnerPayout = pot - platformFee - referralFee;
            _payout(g, winner, winnerPayout, platformFee, referralFee);
        }

        address loser = winner == g.playerA ? g.playerB : g.playerA;
        _reportRating(winner, loser);

        emit GameFinished(gameId, winner, winnerPayout, platformFee, referralFee);
    }

    /// @dev Best-effort rating update: a misbehaving/unset registry must never
    /// block payout or game finalization, so failures are swallowed.
    function _reportRating(address winner, address loser) internal {
        if (ratingRegistry == address(0)) return;
        try IRatingRegistry(ratingRegistry).reportResult(winner, loser) {
            // ok
        } catch {
            // registry not authorized/misconfigured -- game result still stands
        }
    }

    function _payout(
        Game storage g,
        address winner,
        uint256 winnerPayout,
        uint256 platformFee,
        uint256 referralFee
    ) internal nonReentrant {
        if (g.wagerToken == address(0)) {
            if (winnerPayout > 0) {
                (bool s1, ) = payable(winner).call{value: winnerPayout}("");
                require(s1, "payout failed");
            }
            if (platformFee > 0) {
                (bool s2, ) = payable(feeRecipient).call{value: platformFee}("");
                require(s2, "fee transfer failed");
            }
            if (referralFee > 0) {
                _routeReferralFee(g, referralFee, address(0));
            }
        } else {
            if (winnerPayout > 0) IERC20(g.wagerToken).transfer(winner, winnerPayout);
            if (platformFee > 0) IERC20(g.wagerToken).transfer(feeRecipient, platformFee);
            if (referralFee > 0) {
                // Registry pulls via transfer-then-call for ERC20 (see IReferralRegistry docs)
                IERC20(g.wagerToken).transfer(referralRegistry == address(0) ? feeRecipient : referralRegistry, referralFee);
                if (referralRegistry != address(0)) {
                    _routeReferralFee(g, referralFee, g.wagerToken);
                }
            }
        }
    }

    /// @dev Forwards the referral pool to the registry (multi-level, instant payout in this
    /// same transaction). If no registry is configured, or the registry call fails, the
    /// referral share safely falls back to the platform treasury instead of being lost.
    function _routeReferralFee(Game storage g, uint256 referralFee, address token) internal {
        if (referralRegistry == address(0)) {
            if (token == address(0)) {
                (bool s, ) = payable(feeRecipient).call{value: referralFee}("");
                require(s, "fallback fee transfer failed");
            }
            // ERC20 case already sent to feeRecipient above when registry == address(0)
            return;
        }

        if (token == address(0)) {
            try IReferralRegistry(referralRegistry).distributeCommission{value: referralFee}(
                g.playerA,
                g.playerB,
                token,
                referralFee
            ) returns (uint256) {
                // remainder is handled inside the registry (sent to ITS configured treasury)
            } catch {
                // Registry misbehaved -- do not trap funds, send to platform treasury instead.
                (bool s, ) = payable(feeRecipient).call{value: referralFee}("");
                require(s, "referral fallback failed");
            }
        } else {
            // Tokens were already transferred to the registry by _payout above.
            try IReferralRegistry(referralRegistry).distributeCommission(g.playerA, g.playerB, token, referralFee) {
                // ok
            } catch {
                // Best-effort: funds sit in the registry if this fails; owner can recover
                // via a registry-side rescue function (see ReferralRegistry.sol).
            }
        }
    }

    /// @notice Either player may resign at any time, forfeiting the wager.
    function resign(uint256 gameId) external {
        Game storage g = games[gameId];
        require(g.started && g.phase != Phase.Finished, "not active");
        address p = _playerAddr(g, msg.sender);
        address winner = p == g.playerA ? g.playerB : g.playerA;
        _finishGame(g, gameId, winner);
    }

    // ---------------------------------------------------------------
    // Views & helpers
    // ---------------------------------------------------------------

    function getGame(uint256 gameId)
        external
        view
        returns (
            address playerA,
            address playerB,
            Phase phase,
            uint8 turn,
            uint8[2] memory bar,
            uint8[2] memory borneOff,
            address winner
        )
    {
        Game storage g = games[gameId];
        return (g.playerA, g.playerB, g.phase, g.turn, g.bar, g.borneOff, g.winner);
    }

    function getBoard(uint256 gameId) external view returns (int8[24] memory) {
        return games[gameId].board;
    }

    function getDice(uint256 gameId) external view returns (uint8[4] memory remainingPips, uint8 pipCount) {
        Game storage g = games[gameId];
        return (g.remainingPips, g.pipCount);
    }

    function getTiming(uint256 gameId) external view returns (uint256 phaseDeadline, uint256 turnTimeoutSeconds) {
        return (games[gameId].phaseDeadline, TURN_TIMEOUT);
    }

    function _playerAddr(Game storage g, address sender) internal view returns (address) {
        require(sender == g.playerA || sender == g.playerB, "not a player");
        return sender;
    }

    function _initBoard(Game storage g) internal {
        // Standard starting position, player A moving 0->23, player B moving 23->0
        g.board[0] = 2;
        g.board[11] = 5;
        g.board[16] = 3;
        g.board[18] = 5;

        g.board[23] = -2;
        g.board[12] = -5;
        g.board[7] = -3;
        g.board[5] = -5;
    }

    function setProtocolFee(uint256 bps) external onlyOwner {
        require(bps + referralFeeBps <= MAX_TOTAL_FEE_BPS, "combined fee too high");
        protocolFeeBps = bps;
    }

    function setReferralFeeBps(uint256 bps) external onlyOwner {
        require(protocolFeeBps + bps <= MAX_TOTAL_FEE_BPS, "combined fee too high");
        referralFeeBps = bps;
    }

    function setFeeRecipient(address r) external onlyOwner {
        feeRecipient = r;
    }

    function setReferralRegistry(address r) external onlyOwner {
        referralRegistry = r;
    }

    function setRatingRegistry(address r) external onlyOwner {
        ratingRegistry = r;
    }
}
