// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAresTreasury} from "../interfaces/IAresTreasury.sol";
import {IAuthorization} from "../interfaces/IAuthorization.sol";
import {AresLib, ReentrancyGuard} from "../libraries/AresLib.sol";


contract ProposalModule is IAresTreasury, ReentrancyGuard {
    IAuthorization public immutable AUTHORIZATION;

    uint256 public proposalCount;

    mapping(uint256 => Proposal) public proposals;

    mapping(uint256 => bytes32) public proposalCommits;

    mapping(uint256 => mapping(address => bool)) public hasApproved;

    uint256 public constant MIN_DELAY = 48 hours;

    uint256 public constant EXECUTION_WINDOW = 7 days;

    uint256 public constant COMMIT_PHASE = 24 hours;

    uint256 public minApprovals = 2;

    address public governance;

    address public treasury;

    mapping(address => bool) public approvers;

    bytes32 public constant APPROVAL_TYPEHASH =
        keccak256(
            "ProposalApproval(uint256 proposalId,uint8 propType,address target,uint256 amount,bytes32 dataHash,uint256 nonce,uint256 expiry,address approver)"
        );

    error ProposalNotFound();

    error InvalidProposalState();

    error CommitPhaseNotComplete();

    error ExecutionWindowExpired();

    error InsufficientApprovals();

    error AlreadyApproved();
    error Unauthorized();
    error InvalidCommitHash();
    error TreasuryNotSet();

    constructor(address _authorization, address _governance) {
        AUTHORIZATION = IAuthorization(_authorization);
        governance = _governance;
        approvers[_governance] = true;
    }

    function createProposal( ProposalType _propType, address _target, uint256 _amount, bytes calldata _data ) external returns (uint256) {
        return _createProposal(msg.sender, _propType, _target, _amount, _data);
    }

    function commitProposal(uint256 _proposalId, bytes32 _commitHash) external {
        _commitProposal(_proposalId, _commitHash, msg.sender);
    }

    function commitProposalFromTreasury( uint256 _proposalId, bytes32 _commitHash, address _committer ) external {
        if (msg.sender != treasury) revert Unauthorized();
        _commitProposal(_proposalId, _commitHash, _committer);
    }

    function createProposalFromTreasury( address _proposer, ProposalType _propType, address _target, uint256 _amount, bytes calldata _data ) external returns (uint256) {
        if (msg.sender != treasury) revert Unauthorized();
        return _createProposal(_proposer, _propType, _target, _amount, _data);
    }

    function approveProposalFromTreasury( uint256 _proposalId, IAuthorization.SignatureData calldata _sigData, address _approver) external {
        if (msg.sender != treasury) revert Unauthorized();
        _approveProposal(_proposalId, _sigData, _approver);
    }

    function queueProposalFromTreasury(uint256 _proposalId) external {
        if (msg.sender != treasury) revert Unauthorized();
        _queueProposal(_proposalId);
    }

    function cancelProposalFromTreasury(uint256 _proposalId, address _caller) external {
        if (msg.sender != treasury) revert Unauthorized();
        _cancelProposal(_proposalId, _caller);
    }

    function _commitProposal(uint256 _proposalId, bytes32 _commitHash, address _committer) internal {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.state != ProposalState.Pending) revert InvalidProposalState();
        if (_committer != proposal.proposer) revert Unauthorized();
        if (proposal.commitHash != bytes32(0)) revert InvalidProposalState();

        bytes32 expected = computeCommitHash(_proposalId);
        if (_commitHash != expected) revert InvalidCommitHash();

        proposal.commitHash = _commitHash;
        proposal.commitTime = block.timestamp;
        proposal.state = ProposalState.Committed;

        emit ProposalCommitted(_proposalId, _commitHash);
    }

    function approveProposal(uint256 _proposalId, IAuthorization.SignatureData calldata _sigData ) external {
        _approveProposal(_proposalId, _sigData, msg.sender);
    }

    function queueProposal(uint256 _proposalId) external {
        _queueProposal(_proposalId);
    }

    function _queueProposal(uint256 _proposalId) internal {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.state != ProposalState.Committed) revert InvalidProposalState();

        if (block.timestamp < proposal.commitTime + COMMIT_PHASE) {
            revert CommitPhaseNotComplete();
        }
        if (proposal.currentApprovals < proposal.requiredApprovals) {
            revert InsufficientApprovals();
        }

        proposal.queueTime = block.timestamp;
        proposal.executeAfter = block.timestamp + MIN_DELAY;
        proposal.executeDeadline = block.timestamp + EXECUTION_WINDOW;
        proposal.state = ProposalState.Queued;

        emit ProposalQueued(_proposalId, proposal.executeAfter);
    }

    function executeProposal(uint256 _proposalId) external nonReentrant {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.state != ProposalState.Queued) revert InvalidProposalState();

        if (block.timestamp < proposal.executeAfter) {
            revert("Execution time not reached");
        }

        if (block.timestamp > proposal.executeDeadline) {
            proposal.state = ProposalState.Expired;
            revert ExecutionWindowExpired();
        }

        proposal.state = ProposalState.Ready;
    }

    function cancelProposal(uint256 _proposalId) external {
        _cancelProposal(_proposalId, msg.sender);
    }

    function getProposalState(uint256 _proposalId) external view returns (ProposalState) {
        Proposal storage proposal = proposals[_proposalId];
        if (proposal.id == 0) return ProposalState.Cancelled;

        if (
            (proposal.state == ProposalState.Queued || proposal.state == ProposalState.Ready)
            && block.timestamp > proposal.executeDeadline
        ) {
            return ProposalState.Expired;
        }

        return proposal.state;
    }

    function getProposal(uint256 _proposalId) external view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    function setMinApprovals(uint256 _min) external {
        require(msg.sender == governance, "Unauthorized");
        require(_min > 0, "Invalid approvals");
        minApprovals = _min;
    }

    function setTreasury(address _treasury) external {
        if (msg.sender != governance) revert Unauthorized();
        if (treasury != address(0)) revert InvalidProposalState();
        if (_treasury == address(0)) revert TreasuryNotSet();
        treasury = _treasury;
    }

    function setApprover(address _approver, bool _allowed) external {
        if (msg.sender != governance) revert Unauthorized();
        approvers[_approver] = _allowed;
    }

    function markExecuted(uint256 _proposalId, bool _success) external {
        if (msg.sender != treasury) revert Unauthorized();
        Proposal storage proposal = proposals[_proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.state != ProposalState.Ready) revert InvalidProposalState();
        proposal.state = ProposalState.Executed;
        emit ProposalExecuted(_proposalId, _success);
    }

    function computeApprovalStructHash( uint256 _proposalId, address _approver, uint256 _nonce, uint256 _expiry ) public view returns (bytes32) {
        Proposal storage proposal = proposals[_proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
        bytes32 dataHash = AresLib.hashBytes(proposal.data);
        return AresLib.hashBytes(
            abi.encode(
                APPROVAL_TYPEHASH,
                _proposalId,
                uint8(proposal.propType),
                proposal.target,
                proposal.amount,
                dataHash,
                _nonce,
                _expiry,
                _approver
            )
        );
    }

    function computeApprovalDigest( uint256 _proposalId, address _approver, uint256 _nonce, uint256 _expiry ) external view returns (bytes32) {
        bytes32 structHash = computeApprovalStructHash(_proposalId, _approver, _nonce, _expiry);
        return AresLib.hashBytes(abi.encodePacked("\x19\x01", AUTHORIZATION.domainSeparator(), structHash));
    }

    function computeCommitHash(uint256 _proposalId) public view returns (bytes32) {
        Proposal storage proposal = proposals[_proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
        bytes32 dataHash = AresLib.hashBytes(proposal.data);
        return AresLib.hashBytes(
            abi.encode(
                proposal.id,
                proposal.proposer,
                proposal.propType,
                proposal.target,
                proposal.amount,
                dataHash
            )
        );
    }

    function _approveProposal( uint256 _proposalId, IAuthorization.SignatureData calldata _sigData, address _approver ) internal {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.state != ProposalState.Committed) revert InvalidProposalState();
        if (!approvers[_approver]) revert Unauthorized();
        if (hasApproved[_proposalId][_approver]) revert AlreadyApproved();

        bytes32 structHash = computeApprovalStructHash(
            _proposalId,
            _approver,
            _sigData.nonce,
            _sigData.expiry
        );
        AUTHORIZATION.verifySignature(structHash, _sigData, _approver);

        hasApproved[_proposalId][_approver] = true;
        proposal.currentApprovals++;

        emit ApprovalGranted(_proposalId, _approver);
    }

    function _createProposal( address _proposer, ProposalType _propType, address _target, uint256 _amount, bytes calldata _data) internal returns (uint256) {
        proposalCount++;
        uint256 proposalId = proposalCount;

        bytes32 dataHash = AresLib.hashBytes(_data);

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: _proposer,
            propType: _propType,
            target: _target,
            amount: _amount,
            data: _data,
            commitTime: 0,
            queueTime: 0,
            executeAfter: 0,
            executeDeadline: 0,
            commitHash: bytes32(0),
            state: ProposalState.Pending,
            requiredApprovals: minApprovals,
            currentApprovals: 0
        });

        emit ProposalCreated(proposalId, _proposer, dataHash);

        return proposalId;
    }

    function _cancelProposal(uint256 _proposalId, address _caller) internal {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.id == 0) revert ProposalNotFound();
        if (proposal.state == ProposalState.Executed) revert InvalidProposalState();

    
        if (_caller != proposal.proposer && _caller != governance) {
            revert("Unauthorized");
        }

        proposal.state = ProposalState.Cancelled;

        emit ProposalCancelled(_proposalId, _caller);
    }

    receive() external payable {}
}
