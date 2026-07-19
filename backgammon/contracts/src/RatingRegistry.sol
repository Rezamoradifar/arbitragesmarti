// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * RatingRegistry
 * -----------------------------------------------------------------------
 * Minimal on-chain ELO-style rating store. BackgammonCore (or any
 * authorized reporter contract) calls reportResult() after each finished
 * game so rankings stay verifiable on-chain instead of living only in a
 * centralized database.
 * -----------------------------------------------------------------------
 */
contract RatingRegistry is Ownable {
    mapping(address => uint32) public rating;       // default 1000 on first game
    mapping(address => uint32) public gamesPlayed;
    mapping(address => bool) public authorizedReporters;

    uint32 public constant DEFAULT_RATING = 1000;
    uint32 public constant K_FACTOR = 32;

    event RatingUpdated(address indexed player, uint32 newRating);
    event ReporterAuthorized(address indexed reporter, bool allowed);

    constructor() Ownable(msg.sender) {}

    modifier onlyReporter() {
        require(authorizedReporters[msg.sender], "not authorized reporter");
        _;
    }

    function setReporter(address reporter, bool allowed) external onlyOwner {
        authorizedReporters[reporter] = allowed;
        emit ReporterAuthorized(reporter, allowed);
    }

    function reportResult(address winner, address loser) external onlyReporter {
        uint32 rw = rating[winner] == 0 ? DEFAULT_RATING : rating[winner];
        uint32 rl = rating[loser] == 0 ? DEFAULT_RATING : rating[loser];

        (uint32 newRw, uint32 newRl) = _elo(rw, rl);
        rating[winner] = newRw;
        rating[loser] = newRl;
        gamesPlayed[winner] += 1;
        gamesPlayed[loser] += 1;

        emit RatingUpdated(winner, newRw);
        emit RatingUpdated(loser, newRl);
    }

    /// @dev Fixed-point approximation of the ELO expected-score formula,
    /// avoiding floating point (unsupported in Solidity).
    function _elo(uint32 rw, uint32 rl) internal pure returns (uint32, uint32) {
        int256 diff = int256(uint256(rl)) - int256(uint256(rw));
        // expected score for winner, scaled by 1000: 1 / (1 + 10^(diff/400))
        int256 expWinnerScaled = _expectedScoreScaled(diff);
        int256 expLoserScaled = 1000 - expWinnerScaled;

        int256 deltaW = (int256(uint256(K_FACTOR)) * (1000 - expWinnerScaled)) / 1000;
        int256 deltaL = (int256(uint256(K_FACTOR)) * (0 - expLoserScaled)) / 1000;

        int256 newRw = int256(uint256(rw)) + deltaW;
        int256 newRl = int256(uint256(rl)) + deltaL;
        if (newRl < 100) newRl = 100; // floor so ratings can't go absurdly low

        return (uint32(uint256(newRw)), uint32(uint256(newRl)));
    }

    /// @dev Approximates 1000 / (1 + 10^(diff/400)) using a small lookup-based
    /// approximation. Good enough for ranking purposes; not cryptographically
    /// exact.
    function _expectedScoreScaled(int256 diff) internal pure returns (int256) {
        if (diff <= -400) return 909;
        if (diff <= -200) return 760;
        if (diff <= -100) return 640;
        if (diff <= 0) return 570;
        if (diff <= 100) return 500;
        if (diff <= 200) return 360;
        if (diff <= 400) return 240;
        return 91;
    }
}
