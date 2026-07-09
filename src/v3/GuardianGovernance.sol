// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title GuardianGovernance
 * @notice A 5-of-5 guardian consensus module with mandatory 24-hour timelock
 *         and replay protection, used to gate the highest-trust actions in
 *         ArbiSmartV3: triggering the emergency fund-recovery path, replacing
 *         a guardian, and approving a RecoveryVault migration target.
 *
 * @dev Deliberately independent of `owner()` — guardians are five distinct
 *      addresses (enforced at construction to differ from the owner and
 *      from each other), and every action here requires ALL FIVE to approve.
 *      The owner cannot propose, approve, or execute a guardian action, and
 *      cannot be a guardian. This is the "owner alone can never move user
 *      deposits" guarantee: fund-moving emergency power is structurally
 *      outside the owner's control.
 */
abstract contract GuardianGovernance {
    enum GuardianActionType {
        TriggerEmergency,
        ReplaceGuardian,
        ApproveMigrationTarget
    }

    struct GuardianProposal {
        GuardianActionType actionType;
        bytes data;
        string reason;
        uint256 createdAt;
        uint256 approvals;
        uint256 readyAt; // 0 until 5/5 reached; then execution unlocks at readyAt
        bool executed;
    }

    uint256 public constant GUARDIAN_TIMELOCK_DELAY = 24 hours;
    uint256 public constant REQUIRED_GUARDIAN_APPROVALS = 5;

    address[5] public guardians;

    mapping(uint256 => GuardianProposal) private _proposals;
    mapping(uint256 => mapping(address => bool)) public guardianApproved;
    uint256 public guardianProposalCount;

    event GuardianProposalCreated(
        uint256 indexed proposalId, GuardianActionType indexed actionType, address indexed proposer, string reason
    );
    event GuardianProposalApproved(uint256 indexed proposalId, address indexed guardian, uint256 approvals);
    event GuardianProposalReady(uint256 indexed proposalId, uint256 readyAt);
    event GuardianProposalExecuted(uint256 indexed proposalId);
    event GuardianReplaced(address indexed oldGuardian, address indexed newGuardian);

    error NotGuardian();
    error AlreadyApproved();
    error ProposalNotFound();
    error ProposalAlreadyExecuted();
    error NotReadyForApprovalYet();
    error GuardianTimelockNotElapsed();
    error InvalidGuardianSet();
    error GuardianCannotBeOwner();

    modifier onlyGuardian() {
        if (!_isGuardian(msg.sender)) revert NotGuardian();
        _;
    }

    constructor(address[5] memory _guardians, address ownerAddress) {
        for (uint256 i = 0; i < 5; i++) {
            if (_guardians[i] == address(0)) revert InvalidGuardianSet();
            if (_guardians[i] == ownerAddress) revert GuardianCannotBeOwner();
            for (uint256 j = i + 1; j < 5; j++) {
                if (_guardians[i] == _guardians[j]) revert InvalidGuardianSet();
            }
        }
        guardians = _guardians;
    }

    function _isGuardian(address account) internal view returns (bool) {
        for (uint256 i = 0; i < 5; i++) {
            if (guardians[i] == account) return true;
        }
        return false;
    }

    function getGuardians() external view returns (address[5] memory) {
        return guardians;
    }

    function getGuardianProposal(uint256 proposalId)
        external
        view
        returns (
            GuardianActionType actionType,
            bytes memory data,
            string memory reason,
            uint256 createdAt,
            uint256 approvals,
            uint256 readyAt,
            bool executed
        )
    {
        GuardianProposal storage p = _proposals[proposalId];
        if (p.createdAt == 0) revert ProposalNotFound();
        return (p.actionType, p.data, p.reason, p.createdAt, p.approvals, p.readyAt, p.executed);
    }

    /// @notice Any guardian may propose a guardian-level action. Recording a
    ///         `reason` on-chain is mandatory for auditability.
    function proposeGuardianAction(GuardianActionType actionType, bytes calldata data, string calldata reason)
        external
        onlyGuardian
        returns (uint256 proposalId)
    {
        proposalId = ++guardianProposalCount;
        GuardianProposal storage p = _proposals[proposalId];
        p.actionType = actionType;
        p.data = data;
        p.reason = reason;
        p.createdAt = block.timestamp;
        emit GuardianProposalCreated(proposalId, actionType, msg.sender, reason);

        // The proposer's approval counts immediately — saves one transaction.
        _approve(proposalId, msg.sender);
    }

    /// @notice Approve a pending guardian proposal. Each guardian may approve
    ///         a given proposal exactly once (replay protection).
    function approveGuardianAction(uint256 proposalId) external onlyGuardian {
        GuardianProposal storage p = _proposals[proposalId];
        if (p.createdAt == 0) revert ProposalNotFound();
        if (p.executed) revert ProposalAlreadyExecuted();
        _approve(proposalId, msg.sender);
    }

    function _approve(uint256 proposalId, address guardian) private {
        if (guardianApproved[proposalId][guardian]) revert AlreadyApproved();
        guardianApproved[proposalId][guardian] = true;

        GuardianProposal storage p = _proposals[proposalId];
        p.approvals += 1;
        emit GuardianProposalApproved(proposalId, guardian, p.approvals);

        if (p.approvals == REQUIRED_GUARDIAN_APPROVALS) {
            p.readyAt = block.timestamp + GUARDIAN_TIMELOCK_DELAY;
            emit GuardianProposalReady(proposalId, p.readyAt);
        }
    }

    /// @notice Executes a fully-approved (5/5) proposal once its 24-hour
    ///         timelock has elapsed. Callable by anyone (not just guardians)
    ///         once ready, since the consensus has already been reached —
    ///         this just triggers the already-authorized effect.
    function executeGuardianAction(uint256 proposalId) external {
        GuardianProposal storage p = _proposals[proposalId];
        if (p.createdAt == 0) revert ProposalNotFound();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (p.readyAt == 0) revert NotReadyForApprovalYet();
        if (block.timestamp < p.readyAt) revert GuardianTimelockNotElapsed();

        p.executed = true;

        if (p.actionType == GuardianActionType.ReplaceGuardian) {
            (uint256 index, address newGuardian) = abi.decode(p.data, (uint256, address));
            _replaceGuardian(index, newGuardian);
        } else {
            _dispatchGuardianAction(proposalId, p.actionType, p.data);
        }

        emit GuardianProposalExecuted(proposalId);
    }

    function _replaceGuardian(uint256 index, address newGuardian) private {
        if (index >= 5 || newGuardian == address(0)) revert InvalidGuardianSet();
        for (uint256 i = 0; i < 5; i++) {
            if (guardians[i] == newGuardian) revert InvalidGuardianSet();
        }
        address old = guardians[index];
        guardians[index] = newGuardian;
        emit GuardianReplaced(old, newGuardian);
    }

    /// @dev Implemented by the inheriting contract to handle
    ///      `TriggerEmergency` / `ApproveMigrationTarget` (and any future
    ///      action types) — kept virtual so this module stays reusable and
    ///      independent of ArbiSmartV3's specific storage layout.
    function _dispatchGuardianAction(uint256 proposalId, GuardianActionType actionType, bytes memory data)
        internal
        virtual;
}
