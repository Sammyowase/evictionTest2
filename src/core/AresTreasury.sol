// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAresTreasury} from "../interfaces/IAresTreasury.sol";
import {IAuthorization} from "../interfaces/IAuthorization.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {ProposalModule} from "../modules/ProposalModule.sol";
import {AuthorizationModule} from "../modules/AuthorizationModule.sol";
import {RewardDistributionModule} from "../modules/RewardDistributionModule.sol";
import {GovernanceDefenseModule} from "../modules/GovernanceDefenseModule.sol";
import {ReentrancyGuard} from "../libraries/AresLib.sol";


contract AresTreasury is ReentrancyGuard {
   
    string public constant VERSION = "1.0.0";

    ProposalModule public immutable PROPOSAL_MODULE;

    AuthorizationModule public immutable AUTHORIZATION_MODULE;

    RewardDistributionModule public immutable REWARD_MODULE;

    GovernanceDefenseModule public immutable DEFENSE_MODULE;

    error InsufficientBalance();

    error TransferFailed();

    error Paused();
    error InvalidProposalState();
    error ExecutionFailed();

    event Deposited(address indexed from, uint256 amount);

    event Withdrawn(address indexed to, uint256 amount);

    constructor(
        address _authorization,
        address payable _proposal,
        address _reward,
        address _defense
    ) {
        AUTHORIZATION_MODULE = AuthorizationModule(_authorization);
        PROPOSAL_MODULE = ProposalModule(_proposal);
        REWARD_MODULE = RewardDistributionModule(_reward);
        DEFENSE_MODULE = GovernanceDefenseModule(_defense);
    }

    function deposit() external payable nonReentrant {
        if (DEFENSE_MODULE.isPaused()) revert Paused();

        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount, address _to) external nonReentrant {
        if (msg.sender != DEFENSE_MODULE.governance()) revert("Unauthorized");
        if (DEFENSE_MODULE.isPaused()) revert Paused();
        if (address(this).balance < _amount) revert InsufficientBalance();

        (bool success,) = _to.call{value: _amount}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(_to, _amount);
    }

    function getTreasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function execute(uint256 _proposalId) external nonReentrant {
        if (DEFENSE_MODULE.isPaused()) revert Paused();

        ProposalModule.Proposal memory proposal = PROPOSAL_MODULE.getProposal(_proposalId);

        if (proposal.state == IAresTreasury.ProposalState.Queued) {
            PROPOSAL_MODULE.executeProposal(_proposalId);
            proposal = PROPOSAL_MODULE.getProposal(_proposalId);
        }

        if (proposal.state != IAresTreasury.ProposalState.Ready) revert InvalidProposalState();
        if (block.timestamp > proposal.executeDeadline) revert InvalidProposalState();

        uint256 balanceBefore = address(this).balance;
        if (balanceBefore < proposal.amount) revert InsufficientBalance();

        DEFENSE_MODULE.validateTransactionLimit(proposal.amount, balanceBefore);

        bool success = _executeAction(proposal);
        if (!success) revert ExecutionFailed();

        PROPOSAL_MODULE.markExecuted(_proposalId, true);

        if (proposal.amount > 0) {
            DEFENSE_MODULE.recordLargeTransaction(proposal.amount, balanceBefore);
        }
    }

    function createProposal( IAresTreasury.ProposalType _type, address _target, uint256 _amount, bytes calldata _data ) external returns (uint256) {
        if (DEFENSE_MODULE.isPaused()) revert Paused();
        DEFENSE_MODULE.checkHoldingPeriod(msg.sender);

        return PROPOSAL_MODULE.createProposalFromTreasury(msg.sender, _type, _target, _amount, _data);
    }

    function commit(uint256 _proposalId, bytes32 _commitHash) external {
        PROPOSAL_MODULE.commitProposalFromTreasury(_proposalId, _commitHash, msg.sender);
    }

    function approve( uint256 _proposalId, IAuthorization.SignatureData calldata _sigData ) external {
        PROPOSAL_MODULE.approveProposalFromTreasury(_proposalId, _sigData, msg.sender);
    }

    function queue(uint256 _proposalId) external {
        PROPOSAL_MODULE.queueProposalFromTreasury(_proposalId);
    }

    function cancel(uint256 _proposalId) external {
        PROPOSAL_MODULE.cancelProposalFromTreasury(_proposalId, msg.sender);
    }

    function createRewardRound( bytes32 _merkleRoot, uint256 _totalAmount, uint256 _duration ) external returns (uint256) {
        if (msg.sender != DEFENSE_MODULE.governance()) revert("Unauthorized");
        return REWARD_MODULE.createDistributionRound(_merkleRoot, _totalAmount, _duration);
    }

    function claimReward( IRewardDistributor.DistributionRound calldata _round, IRewardDistributor.MerkleProof calldata _proof ) external {
        REWARD_MODULE.claimReward(_round, _proof);
    }

    function isClaimed(uint256 _roundId, uint256 _index) external view returns (bool) {
        return REWARD_MODULE.isClaimed(_roundId, _index);
    }

    function getProposalState(uint256 _proposalId) external view returns (IAresTreasury.ProposalState) {
        return PROPOSAL_MODULE.getProposalState(_proposalId);
    }

    function getProposal(uint256 _proposalId) external view returns (IAresTreasury.Proposal memory) {
        return PROPOSAL_MODULE.getProposal(_proposalId);
    }

    function getNonce(address _signer) external view returns (uint256) {
        return AUTHORIZATION_MODULE.getNonce(_signer);
    }

    receive() external payable {
        if (DEFENSE_MODULE.isPaused()) revert Paused();
        emit Deposited(msg.sender, msg.value);
    }

    function _executeAction(ProposalModule.Proposal memory _proposal) internal returns (bool) {
        if (_proposal.propType == IAresTreasury.ProposalType.Transfer) {
            (bool success,) = _proposal.target.call{value: _proposal.amount}("");
            return success;
        } else if (_proposal.propType == IAresTreasury.ProposalType.Call) {
            (bool success,) = _proposal.target.call{value: _proposal.amount}(_proposal.data);
            return success;
        } else if (_proposal.propType == IAresTreasury.ProposalType.Upgrade) {
            return false;
        }
        return false;
    }
}
