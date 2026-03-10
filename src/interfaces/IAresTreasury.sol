// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface IAresTreasury {
    enum ProposalState {
        Pending,
        Committed,
        Queued,
        Ready,
        Executed,
        Cancelled,
        Expired
    }

    enum ProposalType {
        Transfer,
        Call,
        Upgrade
    }

    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType propType;
        address target;
        uint256 amount;
        bytes data;
        uint256 commitTime;
        uint256 queueTime;
        uint256 executeAfter;
        uint256 executeDeadline;
        bytes32 commitHash;
        ProposalState state;
        uint256 requiredApprovals;
        uint256 currentApprovals;
    }

   
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, bytes32 commitHash);

   
    event ProposalCommitted(uint256 indexed proposalId, bytes32 commitHash);

    event ProposalQueued(uint256 indexed proposalId, uint256 executeAfter);

    event ProposalExecuted(uint256 indexed proposalId, bool success);

    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);

    event ApprovalGranted(uint256 indexed proposalId, address indexed approver);

    function createProposal( ProposalType _propType, address _target, uint256 _amount, bytes calldata _data
    ) external returns (uint256);

    function commitProposal(uint256 _proposalId, bytes32 _commitHash) external;

    function queueProposal(uint256 _proposalId) external;

    function executeProposal(uint256 _proposalId) external;

    function cancelProposal(uint256 _proposalId) external;

    function getProposalState(uint256 _proposalId) external view returns (ProposalState);

    function getProposal(uint256 _proposalId) external view returns (Proposal memory);
}
