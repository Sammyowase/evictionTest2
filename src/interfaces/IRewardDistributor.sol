// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface IRewardDistributor {
    struct MerkleProof {
        bytes32[] proof;
        uint256 index;
        uint256 amount;
        address recipient;
    }

    struct DistributionRound {
        uint256 roundId;
        bytes32 merkleRoot;
        uint256 totalAmount;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isCancelled;
    }

    event DistributionRoundCreated(uint256 indexed roundId, bytes32 merkleRoot, uint256 totalAmount);

    event RewardClaimed(uint256 indexed roundId, address indexed recipient, uint256 amount);

    event MerkleRootUpdated(uint256 indexed roundId, bytes32 oldRoot, bytes32 newRoot);

    function createDistributionRound( bytes32 _merkleRoot, uint256 _totalAmount, uint256 _duration
    ) external returns (uint256);

    function claimReward(DistributionRound calldata _round, MerkleProof calldata _proof) external;

    function cancelDistributionRound(uint256 _roundId) external;

    function isClaimed(uint256 _roundId, uint256 _index) external view returns (bool);

    function getCurrentRoundId() external view returns (uint256);
}
