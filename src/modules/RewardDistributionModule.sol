// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {AresLib, ReentrancyGuard} from "../libraries/AresLib.sol";

contract RewardDistributionModule is IRewardDistributor, ReentrancyGuard {
    address public immutable REWARD_TOKEN;

    address public treasury;

    address public governance;

    uint256 public currentRoundId;

    mapping(uint256 => DistributionRound) public distributionRounds;

    mapping(uint256 => mapping(uint256 => bool)) public claims;

    error InvalidRound();
    error InvalidTreasury();

    error RoundNotActive();

    error AlreadyClaimed();

    error InvalidProof();

    error InsufficientBalance();

    error Unauthorized();

    constructor(address _rewardToken, address _governance) {
        REWARD_TOKEN = _rewardToken;
        governance = _governance;
        currentRoundId = 0;
    }

    function createDistributionRound( bytes32 _merkleRoot, uint256 _totalAmount, uint256 _duration ) external returns (uint256) {
        if (msg.sender != treasury) revert Unauthorized();

        currentRoundId++;
        uint256 roundId = currentRoundId;

        distributionRounds[roundId] = DistributionRound({
            roundId: roundId,
            merkleRoot: _merkleRoot,
            totalAmount: _totalAmount,
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            isActive: true,
            isCancelled: false
        });

        emit DistributionRoundCreated(roundId, _merkleRoot, _totalAmount);

        return roundId;
    }

    function claimReward(DistributionRound calldata _round, MerkleProof calldata _proof) external nonReentrant {
        DistributionRound storage round = distributionRounds[_round.roundId];

        if (round.roundId == 0) revert InvalidRound();
        if (!round.isActive || round.isCancelled) revert RoundNotActive();
        if (block.timestamp > round.endTime) revert RoundNotActive();
        if (claims[_round.roundId][_proof.index]) revert AlreadyClaimed();

        bytes32 leaf = AresLib.createMerkleLeaf(_proof.index, _proof.recipient, _proof.amount);
        if (!AresLib.verifyMerkleProof(_round.merkleRoot, leaf, _proof.proof)) {
            revert InvalidProof();
        }

        claims[_round.roundId][_proof.index] = true;

        _transferReward(_proof.recipient, _proof.amount);

        emit RewardClaimed(_round.roundId, _proof.recipient, _proof.amount);
    }

    function cancelDistributionRound(uint256 _roundId) external {
        if (msg.sender != treasury) revert Unauthorized();

        DistributionRound storage round = distributionRounds[_roundId];

        if (round.roundId == 0) revert InvalidRound();

        round.isCancelled = true;
        round.isActive = false;

        emit MerkleRootUpdated(_roundId, round.merkleRoot, bytes32(0));
    }

    function isClaimed(uint256 _roundId, uint256 _index) external view returns (bool) {
        return claims[_roundId][_index];
    }

    function getCurrentRoundId() external view returns (uint256) {
        return currentRoundId;
    }

    function getDistributionRound(uint256 _roundId) external view returns (DistributionRound memory) {
        return distributionRounds[_roundId];
    }

    function updateMerkleRoot(uint256 _roundId, bytes32 _newRoot) external {
        if (msg.sender != treasury) revert Unauthorized();

        DistributionRound storage round = distributionRounds[_roundId];
        if (round.roundId == 0) revert InvalidRound();

        bytes32 oldRoot = round.merkleRoot;
        round.merkleRoot = _newRoot;

        emit MerkleRootUpdated(_roundId, oldRoot, _newRoot);
    }

    function _transferReward(address _recipient, uint256 _amount) internal {
        
        (bool success, bytes memory data) = REWARD_TOKEN.call(
            abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount)
        );

        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert("Transfer failed");
        }
    }

    function setTreasury(address _treasury) external {
        if (msg.sender != governance) revert Unauthorized();
        if (treasury != address(0)) revert InvalidTreasury();
        if (_treasury == address(0)) revert InvalidTreasury();
        treasury = _treasury;
    }
}
