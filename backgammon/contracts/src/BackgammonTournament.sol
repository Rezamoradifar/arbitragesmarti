// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * BackgammonTournament
 * -----------------------------------------------------------------------
 * Handles entry fees and prize-pool distribution for tournaments whose
 * matches are played through BackgammonCore. Bracket pairing / match
 * scheduling is intentionally kept OFF-CHAIN (in the backend/frontend),
 * because on-chain bracket logic for many-player elimination trees is
 * expensive and adds little trust benefit -- what actually needs to be
 * trustless is the prize pool and payout, which this contract handles.
 *
 * Flow:
 *  1. Organizer creates a tournament with entry fee + payout splits.
 *  2. Players register and pay the entry fee (held in escrow here).
 *  3. Matches happen off-chain via BackgammonCore game IDs (recorded for
 *     auditability) or fully off-chain bracket software.
 *  4. Organizer (or a DAO/multisig in production) finalizes standings.
 *  5. Winners claim their share directly from this contract.
 * -----------------------------------------------------------------------
 */
contract BackgammonTournament is ReentrancyGuard, Ownable {
    struct Tournament {
        address organizer;
        address token; // address(0) = native BNB
        uint256 entryFee;
        uint256 maxPlayers;
        uint16[] payoutBpsByRank; // e.g. [6000, 3000, 1000] = 60/30/10%
        bool registrationOpen;
        bool finalized;
        address[] players;
        mapping(address => bool) registered;
        address[] ranking; // set at finalize, index 0 = 1st place
        mapping(address => bool) claimed;
        uint256 pool;
    }

    uint256 public nextTournamentId;
    mapping(uint256 => Tournament) private tournaments;

    event TournamentCreated(uint256 indexed id, address organizer, uint256 entryFee, uint256 maxPlayers);
    event PlayerRegistered(uint256 indexed id, address player);
    event TournamentFinalized(uint256 indexed id, address[] ranking);
    event PrizeClaimed(uint256 indexed id, address player, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function createTournament(
        address token,
        uint256 entryFee,
        uint256 maxPlayers,
        uint16[] calldata payoutBpsByRank
    ) external returns (uint256 id) {
        uint256 total;
        for (uint256 i = 0; i < payoutBpsByRank.length; i++) total += payoutBpsByRank[i];
        require(total == 10000, "payout splits must total 100%");

        id = nextTournamentId++;
        Tournament storage t = tournaments[id];
        t.organizer = msg.sender;
        t.token = token;
        t.entryFee = entryFee;
        t.maxPlayers = maxPlayers;
        t.payoutBpsByRank = payoutBpsByRank;
        t.registrationOpen = true;

        emit TournamentCreated(id, msg.sender, entryFee, maxPlayers);
    }

    function register(uint256 id) external payable {
        Tournament storage t = tournaments[id];
        require(t.registrationOpen, "registration closed");
        require(!t.registered[msg.sender], "already registered");
        require(t.players.length < t.maxPlayers, "tournament full");

        if (t.entryFee > 0) {
            if (t.token == address(0)) {
                require(msg.value == t.entryFee, "bad BNB entry fee");
            } else {
                require(msg.value == 0, "no BNB expected");
                IERC20(t.token).transferFrom(msg.sender, address(this), t.entryFee);
            }
            t.pool += t.entryFee;
        }

        t.registered[msg.sender] = true;
        t.players.push(msg.sender);
        emit PlayerRegistered(id, msg.sender);
    }

    function closeRegistration(uint256 id) external {
        Tournament storage t = tournaments[id];
        require(msg.sender == t.organizer || msg.sender == owner(), "not authorized");
        t.registrationOpen = false;
    }

    /// @notice Organizer submits final standings once all off-chain matches conclude.
    function finalize(uint256 id, address[] calldata ranking) external {
        Tournament storage t = tournaments[id];
        require(msg.sender == t.organizer || msg.sender == owner(), "not authorized");
        require(!t.finalized, "already finalized");
        require(ranking.length == t.payoutBpsByRank.length, "ranking length mismatch");
        for (uint256 i = 0; i < ranking.length; i++) {
            require(t.registered[ranking[i]], "not a registered player");
        }

        t.ranking = ranking;
        t.finalized = true;
        t.registrationOpen = false;
        emit TournamentFinalized(id, ranking);
    }

    function claimPrize(uint256 id) external nonReentrant {
        Tournament storage t = tournaments[id];
        require(t.finalized, "not finalized");
        require(!t.claimed[msg.sender], "already claimed");

        uint256 rank = type(uint256).max;
        for (uint256 i = 0; i < t.ranking.length; i++) {
            if (t.ranking[i] == msg.sender) {
                rank = i;
                break;
            }
        }
        require(rank != type(uint256).max, "not a prize winner");

        uint256 amount = (t.pool * t.payoutBpsByRank[rank]) / 10000;
        t.claimed[msg.sender] = true;

        if (t.token == address(0)) {
            (bool s, ) = payable(msg.sender).call{value: amount}("");
            require(s, "payout failed");
        } else {
            IERC20(t.token).transfer(msg.sender, amount);
        }
        emit PrizeClaimed(id, msg.sender, amount);
    }

    function getPlayers(uint256 id) external view returns (address[] memory) {
        return tournaments[id].players;
    }

    function getRanking(uint256 id) external view returns (address[] memory) {
        return tournaments[id].ranking;
    }
}
