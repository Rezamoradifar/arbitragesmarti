// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title OwnerTimelock
 * @notice A minimal, self-contained 24-hour schedule/execute timelock for
 *         owner-initiated configuration changes that do NOT touch user
 *         principal (fee wallets, arbitrage protocol whitelist, profit
 *         recipient/fee rate). Fund-moving emergency actions use the
 *         separate, stricter {GuardianGovernance} 5-of-5 module instead —
 *         this contract is intentionally not used for anything that can
 *         move a user's staked collateral.
 *
 * @dev Pattern: `schedule(actionHash)` records `block.timestamp`;
 *      `consume(actionHash)` reverts unless 24 hours have elapsed, then
 *      clears the record so it can't be replayed. The inheriting contract
 *      computes `actionHash` as `keccak256(abi.encode(selectorTag, ...params))`
 *      so that scheduling and execution must use identical parameters —
 *      changing a parameter between schedule and execute produces a
 *      different hash and simply isn't scheduled.
 */
abstract contract OwnerTimelock {
    uint256 public constant OWNER_TIMELOCK_DELAY = 24 hours;

    mapping(bytes32 => uint256) public scheduledAt;

    event ActionScheduled(bytes32 indexed actionHash, uint256 readyAt);
    event ActionCancelled(bytes32 indexed actionHash);

    error NotScheduled();
    error AlreadyScheduled();
    error TimelockNotElapsed();

    function _schedule(bytes32 actionHash) internal {
        if (scheduledAt[actionHash] != 0) revert AlreadyScheduled();
        scheduledAt[actionHash] = block.timestamp;
        emit ActionScheduled(actionHash, block.timestamp + OWNER_TIMELOCK_DELAY);
    }

    function _cancel(bytes32 actionHash) internal {
        delete scheduledAt[actionHash];
        emit ActionCancelled(actionHash);
    }

    function _consume(bytes32 actionHash) internal {
        uint256 at = scheduledAt[actionHash];
        // 0 is the sentinel for "never scheduled" (block.timestamp is
        // always > 0 in practice) — an exact check is correct, not a
        // manipulable-balance comparison.
        // slither-disable-next-line incorrect-equality
        if (at == 0) revert NotScheduled();
        if (block.timestamp < at + OWNER_TIMELOCK_DELAY) revert TimelockNotElapsed();
        delete scheduledAt[actionHash];
    }
}
