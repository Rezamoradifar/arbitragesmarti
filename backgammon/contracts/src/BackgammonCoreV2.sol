// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IRatingRegistry {
    function reportResult(address winner, address loser) external;
}

interface IReferralRegistry {
    function distributeCommission(
        address playerA,
        address playerB,
        address token,
        uint256 amount
    ) external payable returns (uint256 remainder);
}

/**
 * BackgammonCoreV2
 * -----------------------------------------------------------------------
 * V2 of BackgammonCore: adds the doubling cube and an owner-only
 * emergency pause on top of the V1 game engine (board/dice/moves/wager
 * escrow, commit-reveal randomness, timeouts, referral/rating hooks).
 * V1 is immutable and stays live for any games already in progress there
 * -- this is a separate contract, not an upgrade.
 *
 * Doubling cube funds model:
 *   Standard backgammon lets the cube climb (1 -> 2 -> 4 -> ...) without
 *   either side depositing more money until the game settles, because
 *   it's a private cash game between two people who trust each other to
 *   pay. That doesn't work for a trustless on-chain escrow: the contract
 *   can only ever pay out what it's actually holding. So a double here
 *   requires BOTH sides to top up their escrowed stake to match the new
 *   cube value before it takes effect:
 *     1. offerDouble() is payable -- the offering player immediately
 *        escrows `wagerAmount * cubeValue` (their matching top-up for
 *        the proposed new value) and the game enters DoubleOffered.
 *     2. The other player calls acceptDouble() (payable, same amount) to
 *        confirm -- cubeValue doubles, they become the new cube owner,
 *        and play continues with the offering player still on roll.
 *     3. ...or declineDouble(): the offer's escrowed top-up is refunded,
 *        and the game ends immediately in the offering player's favor at
 *        the pot as it stood *before* this offer (a resign-equivalent).
 *     4. A non-response past the timeout lets the offering player claim
 *        the win the same way (their top-up is refunded since the double
 *        never completed).
 *   Only the player who owns the cube (or either player, if it's
 *   centered / never been doubled) may offer -- matching the standard
 *   rule that you can't double away a cube you don't hold.
 * -----------------------------------------------------------------------
 */
contract BackgammonCoreV2 is ReentrancyGuard, Ownable, Pausable {
    uint256 public constant TURN_TIMEOUT = 5 minutes;
    uint256 public constant MAX_TOTAL_FEE_BPS = 3000; // hard ceiling: 30% combined, protects players
    uint8 public constant MAX_CUBE_VALUE = 8; // caps how many times a game's escrow can be doubled

    uint256 public protocolFeeBps = 500;  // 5% -> platform treasury
    uint256 public referralFeeBps = 1000; // 10% -> multi-level referral pool
    address public feeRecipient;
    address public referralRegistry;
    address public ratingRegistry;

    enum Phase {
        None,
        WaitingForOpponent,
        CommitRoll,
        RevealRoll,
        Move,
        DoubleOffered,
        Finished
    }

    struct Move {
        int8 from;
        int8 to;
    }

    struct Game {
        address playerA;
        address playerB;
        address wagerToken;
        uint256 wagerAmount;
        bool started;
        bool wagerFunded;

        int8[24] board;
        uint8[2] bar;
        uint8[2] borneOff;

        uint8 turn;
        Phase phase;
        Phase phaseBeforeDouble; // resume phase once a double offer resolves
        uint256 phaseDeadline;

        bytes32 commitA;
        bytes32 commitB;
        uint8 dieA;
        uint8 dieB;
        uint8[4] remainingPips;
        uint8 pipCount;

        uint8 cubeValue;      // 1, 2, 4, or 8
        address cubeOwner;    // address(0) = centered, either player may offer
        address doubleOfferedBy;
        uint256 pendingDoubleEscrow; // offering player's top-up, held until accept/decline

        address winner;
    }

    uint256 public nextGameId;
    mapping(uint256 => Game) private games;

    event GameCreated(uint256 indexed gameId, address indexed creator, uint256 wager, address token);
    event GameJoined(uint256 indexed gameId, address indexed opponent);
    event RollCommitted(uint256 indexed gameId, uint8 player);
    event RollRevealed(uint256 indexed gameId, uint8 dieA, uint8 dieB);
    event MovesPlayed(uint256 indexed gameId, uint8 player, Move[] moves);
    event DoubleOffered(uint256 indexed gameId, address indexed by, uint8 newCubeValue);
    event DoubleAccepted(uint256 indexed gameId, address indexed by, uint8 newCubeValue);
    event DoubleDeclined(uint256 indexed gameId, address indexed by);
    event GameFinished(uint256 indexed gameId, address winner, uint256 winnerPayout, uint256 platformFee, uint256 referralFee);
    event TimeoutClaimed(uint256 indexed gameId, address winner);

    constructor(address _feeRecipient) Ownable(msg.sender) {
        feeRecipient = _feeRecipient;
    }

    // ---------------------------------------------------------------
    // Game creation / joining / wager funding
    // ---------------------------------------------------------------

    function createGame(uint256 wagerAmount, address wagerToken) external payable whenNotPaused returns (uint256 gameId) {
        gameId = nextGameId++;
        Game storage g = games[gameId];
        g.playerA = msg.sender;
        g.wagerAmount = wagerAmount;
        g.wagerToken = wagerToken;
        g.phase = Phase.WaitingForOpponent;
        g.cubeValue = 1;
        _initBoard(g);

        if (wagerAmount > 0) {
            _collectStake(g, msg.sender, wagerAmount);
        }

        emit GameCreated(gameId, msg.sender, wagerAmount, wagerToken);
    }

    function joinGame(uint256 gameId) external payable whenNotPaused {
        Game storage g = games[gameId];
        require(g.phase == Phase.WaitingForOpponent, "not joinable");
        require(g.playerB == address(0), "full");
        require(msg.sender != g.playerA, "cannot join own game");

        g.playerB = msg.sender;
        if (g.wagerAmount > 0) {
            _collectStake(g, msg.sender, g.wagerAmount);
        }
        g.wagerFunded = true;

        g.started = true;
        g.phase = Phase.CommitRoll;
        g.phaseDeadline = block.timestamp + TURN_TIMEOUT;
        emit GameJoined(gameId, msg.sender);
    }

    function _collectStake(Game storage g, address player, uint256 amount) internal {
        if (g.wagerToken == address(0)) {
            require(msg.value == amount, "bad BNB stake");
        } else {
            require(msg.value == 0, "no BNB expected");
            IERC20(g.wagerToken).transferFrom(player, address(this), amount);
        }
    }

    // ---------------------------------------------------------------
    // Doubling cube
    // ---------------------------------------------------------------

    /// @notice Offer to double the stake. Only the current cube owner (or
    /// either player if the cube is centered) may offer, only at the start
    /// of their own turn (CommitRoll phase, before rolling), and only if
    /// there's a real wager. Escrows the offering player's matching top-up.
    function offerDouble(uint256 gameId) external payable whenNotPaused {
        Game storage g = games[gameId];
        require(g.phase == Phase.CommitRoll, "not offerable now");
        require(g.wagerAmount > 0, "free play has no cube");
        address p = _playerAddr(g, msg.sender);
        require((g.turn == 0 && p == g.playerA) || (g.turn == 1 && p == g.playerB), "not your turn");
        require(g.cubeOwner == address(0) || g.cubeOwner == p, "you don't hold the cube");
        require(g.cubeValue < MAX_CUBE_VALUE, "cube maxed out");

        uint256 topUp = g.wagerAmount * g.cubeValue;
        _collectStake(g, msg.sender, topUp);

        g.pendingDoubleEscrow = topUp;
        g.doubleOfferedBy = p;
        g.phaseBeforeDouble = g.phase;
        g.phase = Phase.DoubleOffered;
        g.phaseDeadline = block.timestamp + TURN_TIMEOUT;

        emit DoubleOffered(gameId, p, g.cubeValue * 2);
    }

    function acceptDouble(uint256 gameId) external payable whenNotPaused {
        Game storage g = games[gameId];
        require(g.phase == Phase.DoubleOffered, "no pending double");
        address p = _playerAddr(g, msg.sender);
        require(p != g.doubleOfferedBy, "cannot accept your own offer");

        uint256 topUp = g.wagerAmount * g.cubeValue;
        _collectStake(g, msg.sender, topUp);

        g.cubeValue *= 2;
        g.cubeOwner = p;
        g.pendingDoubleEscrow = 0;
        g.doubleOfferedBy = address(0);
        g.phase = g.phaseBeforeDouble;
        g.phaseDeadline = block.timestamp + TURN_TIMEOUT;

        emit DoubleAccepted(gameId, p, g.cubeValue);
    }

    function declineDouble(uint256 gameId) external whenNotPaused {
        Game storage g = games[gameId];
        require(g.phase == Phase.DoubleOffered, "no pending double");
        address p = _playerAddr(g, msg.sender);
        require(p != g.doubleOfferedBy, "cannot decline your own offer");

        // Checks-effects-interactions: clear the pending escrow and finish
        // the game (which flips phase to Finished) BEFORE sending the
        // refund transfer. Sending it first would let a malicious
        // doubleOfferedBy contract reenter while the game still looked
        // "active" and trigger a second _finishGame/_payout for the same
        // gameId -- draining the contract via a double payout.
        uint256 refundAmount = g.pendingDoubleEscrow;
        address refundTo = g.doubleOfferedBy;
        address refundToken = g.wagerToken;
        g.pendingDoubleEscrow = 0;

        emit DoubleDeclined(gameId, p);
        _finishGame(g, gameId, g.doubleOfferedBy);

        if (refundAmount > 0) _sendRefund(refundToken, refundTo, refundAmount);
    }

    function _sendRefund(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool s, ) = payable(to).call{value: amount}("");
            require(s, "double refund failed");
        } else {
            IERC20(token).transfer(to, amount);
        }
    }

    // ---------------------------------------------------------------
    // Commit-reveal dice
    // ---------------------------------------------------------------

    function commitRoll(uint256 gameId, bytes32 commitHash) external whenNotPaused {
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

    function revealRoll(uint256 gameId, uint8 secretValue, bytes32 salt) external whenNotPaused {
        Game storage g = games[gameId];
        require(g.phase == Phase.RevealRoll, "not reveal phase");
        address p = _playerAddr(g, msg.sender);
        bytes32 expected = keccak256(abi.encodePacked(secretValue, salt, msg.sender));

        if (p == g.playerA) {
            require(g.commitA == expected, "bad reveal");
            g.dieA = (secretValue % 6) + 1;
            g.commitA = bytes32(uint256(1));
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
        uint8 d1 = g.dieA;
        uint8 d2 = g.dieB;

        if (d1 == d2) {
            g.remainingPips = [d1, d1, d1, d1];
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

    function submitMoves(uint256 gameId, Move[] calldata moves) external whenNotPaused {
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

        g.turn = g.turn == 0 ? 1 : 0;
        g.phase = Phase.CommitRoll;
        g.phaseDeadline = block.timestamp + TURN_TIMEOUT;
    }

    function _applyMove(Game storage g, Move calldata m, int8 dir) internal {
        uint8 player = g.turn;
        uint8 pipsUsed = _pipsForMove(g, m, dir);
        require(_consumePip(g, pipsUsed), "die not available");

        if (m.from == 24) {
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
            require(_allInHome(g, player), "not all checkers home");
            g.borneOff[player] += 1;
        } else {
            require(m.to >= 0 && m.to < 24, "bad to");
            int8 occ = g.board[uint8(m.to)];
            if (player == 0) {
                require(occ >= -1, "point blocked");
                if (occ == -1) {
                    g.board[uint8(m.to)] = 1;
                    g.bar[1] += 1;
                } else {
                    g.board[uint8(m.to)] += 1;
                }
            } else {
                require(occ <= 1, "point blocked");
                if (occ == 1) {
                    g.board[uint8(m.to)] = -1;
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

    /// @notice Claim a win when the opponent's clock has expired. Works in
    /// every active phase including DoubleOffered -- an un-answered double
    /// offer times out the same way a stalled move or reveal does, and the
    /// offering player's escrowed top-up is refunded since the double never
    /// completed.
    function claimTimeout(uint256 gameId) external {
        Game storage g = games[gameId];
        require(g.started && g.phase != Phase.Finished, "not active");
        require(block.timestamp > g.phaseDeadline, "not expired");

        address winner;
        uint256 refundAmount;
        address refundTo;
        address refundToken = g.wagerToken;
        if (g.phase == Phase.DoubleOffered) {
            winner = g.doubleOfferedBy;
            refundAmount = g.pendingDoubleEscrow;
            refundTo = g.doubleOfferedBy;
            g.pendingDoubleEscrow = 0; // clear before any external call -- see declineDouble
        } else {
            address loserTurnPlayer = g.turn == 0 ? g.playerA : g.playerB;
            winner = loserTurnPlayer == g.playerA ? g.playerB : g.playerA;
        }

        _finishGame(g, gameId, winner);
        emit TimeoutClaimed(gameId, winner);

        if (refundAmount > 0) _sendRefund(refundToken, refundTo, refundAmount);
    }

    function _finishGame(Game storage g, uint256 gameId, address winner) internal {
        g.phase = Phase.Finished;
        g.winner = winner;

        uint256 winnerPayout = 0;
        uint256 platformFee = 0;
        uint256 referralFee = 0;

        if (g.wagerAmount > 0) {
            uint256 pot = g.wagerAmount * 2 * g.cubeValue;
            platformFee = (pot * protocolFeeBps) / 10000;
            referralFee = (pot * referralFeeBps) / 10000;
            winnerPayout = pot - platformFee - referralFee;
            _payout(g, winner, winnerPayout, platformFee, referralFee);
        }

        address loser = winner == g.playerA ? g.playerB : g.playerA;
        _reportRating(winner, loser);

        emit GameFinished(gameId, winner, winnerPayout, platformFee, referralFee);
    }

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
                IERC20(g.wagerToken).transfer(referralRegistry == address(0) ? feeRecipient : referralRegistry, referralFee);
                if (referralRegistry != address(0)) {
                    _routeReferralFee(g, referralFee, g.wagerToken);
                }
            }
        }
    }

    function _routeReferralFee(Game storage g, uint256 referralFee, address token) internal {
        if (referralRegistry == address(0)) {
            if (token == address(0)) {
                (bool s, ) = payable(feeRecipient).call{value: referralFee}("");
                require(s, "fallback fee transfer failed");
            }
            return;
        }

        if (token == address(0)) {
            try IReferralRegistry(referralRegistry).distributeCommission{value: referralFee}(
                g.playerA,
                g.playerB,
                token,
                referralFee
            ) returns (uint256) {
                // remainder handled inside the registry
            } catch {
                (bool s, ) = payable(feeRecipient).call{value: referralFee}("");
                require(s, "referral fallback failed");
            }
        } else {
            try IReferralRegistry(referralRegistry).distributeCommission(g.playerA, g.playerB, token, referralFee) {
                // ok
            } catch {
                // Best-effort: funds sit in the registry if this fails; owner can recover
                // via a registry-side rescue function.
            }
        }
    }

    /// @notice Either player may resign at any time (except mid-double-offer,
    /// where declineDouble/acceptDouble/claimTimeout are the exits), forfeiting
    /// the wager at the current cube value.
    function resign(uint256 gameId) external {
        Game storage g = games[gameId];
        require(g.started && g.phase != Phase.Finished && g.phase != Phase.DoubleOffered, "not active");
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

    function getCube(uint256 gameId) external view returns (uint8 cubeValue, address cubeOwner, address doubleOfferedBy) {
        Game storage g = games[gameId];
        return (g.cubeValue, g.cubeOwner, g.doubleOfferedBy);
    }

    function _playerAddr(Game storage g, address sender) internal view returns (address) {
        require(sender == g.playerA || sender == g.playerB, "not a player");
        return sender;
    }

    function _initBoard(Game storage g) internal {
        g.board[0] = 2;
        g.board[11] = 5;
        g.board[16] = 3;
        g.board[18] = 5;

        g.board[23] = -2;
        g.board[12] = -5;
        g.board[7] = -3;
        g.board[5] = -5;
    }

    // ---------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------

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

    /// @notice Emergency stop: blocks new games, joins, doubles, rolls, and
    /// moves. Deliberately does NOT block resign/claimTimeout/declineDouble
    /// so players in an active game can always get their funds out instead
    /// of being trapped by a pause.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
