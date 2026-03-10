// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AresTreasury} from "../src/core/AresTreasury.sol";
import {IAuthorization} from "../src/interfaces/IAuthorization.sol";
import {IAresTreasury} from "../src/interfaces/IAresTreasury.sol";
import {IRewardDistributor} from "../src/interfaces/IRewardDistributor.sol";
import {ProposalModule} from "../src/modules/ProposalModule.sol";
import {AuthorizationModule} from "../src/modules/AuthorizationModule.sol";
import {RewardDistributionModule} from "../src/modules/RewardDistributionModule.sol";
import {GovernanceDefenseModule} from "../src/modules/GovernanceDefenseModule.sol";
import {AresLib} from "../src/libraries/AresLib.sol";


contract AresTreasuryTest is Test {
  
    AresTreasury public treasury;
    ProposalModule public proposalModule;
    AuthorizationModule public authModule;
    RewardDistributionModule public rewardModule;
    GovernanceDefenseModule public defenseModule;

    
    address public mockToken = address(0x1234);

    
    address public governance = address(1);
    address public proposer = address(2);
    address public approver1;
    address public approver2;
    address public contributor = address(5);
    address public attacker = address(6);
    address public recipient = address(7);

  
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant PROPOSAL_AMOUNT = 10 ether;
    uint256 public constant APPROVER1_PK = 0xA11CE;
    uint256 public constant APPROVER2_PK = 0xB0B;

    function setUp() public {
        approver1 = vm.addr(APPROVER1_PK);
        approver2 = vm.addr(APPROVER2_PK);

      
        authModule = new AuthorizationModule();
        
        defenseModule = new GovernanceDefenseModule(governance);
        
        rewardModule = new RewardDistributionModule(mockToken, governance);
        
        proposalModule = new ProposalModule(address(authModule), governance);

        
        treasury = new AresTreasury(
            address(authModule),
            payable(address(proposalModule)),
            address(rewardModule),
            address(defenseModule)
        );

        vm.startPrank(governance);
        defenseModule.setTreasury(address(treasury));
        rewardModule.setTreasury(address(treasury));
        proposalModule.setTreasury(address(treasury));
        proposalModule.setApprover(approver1, true);
        proposalModule.setApprover(approver2, true);
        defenseModule.recordTokenAcquisition(proposer);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        
        vm.deal(address(treasury), INITIAL_BALANCE);

        vm.startPrank(governance);
        proposalModule.setMinApprovals(2);
        vm.stopPrank();
    }
  
    function testRevertDoubleClaim() public {
        bytes32 leaf = AresLib.createMerkleLeaf(0, contributor, 100 ether);
        bytes32[] memory proof = new bytes32[](0);

        vm.startPrank(governance);
        treasury.createRewardRound(leaf, 100 ether, 30 days);
        vm.stopPrank();

        IRewardDistributor.DistributionRound memory round = rewardModule.getDistributionRound(1);
        IRewardDistributor.MerkleProof memory merkleProof = IRewardDistributor.MerkleProof({
            proof: proof,
            index: 0,
            amount: 100 ether,
            recipient: contributor
        });

        vm.startPrank(contributor);
        rewardModule.claimReward(round, merkleProof);
        // Second claim should fail
        vm.expectRevert();
        rewardModule.claimReward(round, merkleProof);
        vm.stopPrank();
    }


    function testRevertInvalidSignature() public {
        vm.startPrank(proposer);
        uint256 proposalId = treasury.createProposal(
            IAresTreasury.ProposalType.Transfer,
            recipient,
            PROPOSAL_AMOUNT,
            ""
        );
        treasury.commit(proposalId, proposalModule.computeCommitHash(proposalId));
        vm.stopPrank();

        // Create invalid signature (wrong signer)
        uint256 expiry = block.timestamp + 1 days;
        bytes32 digest = proposalModule.computeApprovalDigest(proposalId, approver1, 0, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(APPROVER2_PK, digest);
        IAuthorization.SignatureData memory sigData = IAuthorization.SignatureData({
            v: v,
            r: r,
            s: s,
            nonce: 0,
            chainId: block.chainid,
            expiry: expiry
        });

        vm.startPrank(approver1);
        // Should fail - signature doesn't match approver
        vm.expectRevert();
        treasury.approve(proposalId, sigData);
        vm.stopPrank();
    }

  
    function testRevertPrematureExecution() public {
        _createAndApproveProposal();
        vm.warp(block.timestamp + 25 hours);
        
        vm.startPrank(governance);
        treasury.queue(1);
        vm.expectRevert();
        treasury.execute(1);
        vm.stopPrank();
    }

    
    function testRevertUnauthorizedCancel() public {
        vm.startPrank(proposer);
        uint256 proposalId = treasury.createProposal(
            IAresTreasury.ProposalType.Transfer,
            recipient,
            PROPOSAL_AMOUNT,
            ""
        );
        vm.stopPrank();

        vm.startPrank(attacker);
        vm.expectRevert();
        treasury.cancel(proposalId);
        vm.stopPrank();
    }

    function testRevertExecutionWindowExpired() public {
        _createAndApproveProposal();
        vm.warp(block.timestamp + 25 hours);
        
        vm.startPrank(governance);
        treasury.queue(1);
        vm.stopPrank();

        // Skip past execution window
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(governance);
        vm.expectRevert();
        treasury.execute(1);
        vm.stopPrank();
    }

    
    function testRevertCommitPhaseBypass() public {
        vm.startPrank(proposer);
        uint256 proposalId = treasury.createProposal(
            IAresTreasury.ProposalType.Transfer,
            recipient,
            PROPOSAL_AMOUNT,
            ""
        );
        treasury.commit(proposalId, proposalModule.computeCommitHash(proposalId));
        vm.stopPrank();

        // Approve without waiting
        IAuthorization.SignatureData memory sigData = _buildSig(
            proposalId,
            approver1,
            0,
            block.timestamp + 1 days
        );

        vm.startPrank(approver1);
        treasury.approve(proposalId, sigData);
        vm.stopPrank();

        vm.startPrank(governance);
        vm.expectRevert();
        treasury.queue(proposalId);
        vm.stopPrank();
    }

    function testRevertInsufficientApprovals() public {
        vm.startPrank(proposer);
        uint256 proposalId = treasury.createProposal(
            IAresTreasury.ProposalType.Transfer,
            recipient,
            PROPOSAL_AMOUNT,
            ""
        );
        treasury.commit(proposalId, proposalModule.computeCommitHash(proposalId));
        vm.stopPrank();

        vm.warp(block.timestamp + 25 hours);

        // Only one approval when two required
        IAuthorization.SignatureData memory sigData = _buildSig(
            proposalId,
            approver1,
            0,
            block.timestamp + 1 days
        );

        vm.startPrank(approver1);
        treasury.approve(proposalId, sigData);
        vm.stopPrank();

        vm.startPrank(governance);
        vm.expectRevert();
        treasury.queue(proposalId);
        vm.stopPrank();
    }

    function testRevertFlashLoanGovernanceAttack() public {
        vm.startPrank(attacker);
        vm.expectRevert();
        treasury.createProposal(
            IAresTreasury.ProposalType.Transfer,
            attacker,
            INITIAL_BALANCE,
            ""
        );
        vm.stopPrank();
    }

    function _createAndApproveProposal() internal returns (uint256) {
        vm.startPrank(proposer);
        uint256 proposalId = treasury.createProposal(
            IAresTreasury.ProposalType.Transfer,
            recipient,
            PROPOSAL_AMOUNT,
            ""
        );
        treasury.commit(proposalId, proposalModule.computeCommitHash(proposalId));
        vm.stopPrank();

        _approveProposal(proposalId);

        return proposalId;
    }

    function _approveProposal(uint256 _proposalId) internal {
        IAuthorization.SignatureData memory sigData1 = _buildSig(
            _proposalId,
            approver1,
            0,
            block.timestamp + 1 days
        );

        vm.startPrank(approver1);
        treasury.approve(_proposalId, sigData1);
        vm.stopPrank();

        IAuthorization.SignatureData memory sigData2 = _buildSig(
            _proposalId,
            approver2,
            0,
            block.timestamp + 1 days
        );

        vm.startPrank(approver2);
        treasury.approve(_proposalId, sigData2);
        vm.stopPrank();
    }

    function _buildSig( uint256 _proposalId, address _approver, uint256 _nonce, uint256 _expiry) internal view returns (IAuthorization.SignatureData memory) {
        bytes32 digest = proposalModule.computeApprovalDigest(_proposalId, _approver, _nonce, _expiry);
        uint256 pk;
        if (_approver == approver1) {
            pk = APPROVER1_PK;
        } else if (_approver == approver2) {
            pk = APPROVER2_PK;
        } else {
            revert("Unknown approver");
        }
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        return IAuthorization.SignatureData({
            v: v,
            r: r,
            s: s,
            nonce: _nonce,
            chainId: block.chainid,
            expiry: _expiry
        });
    }
}


contract MaliciousContract {
    AresTreasury public treasury;
    bool public attacked;

    constructor(address _treasury) {
        treasury = AresTreasury(payable(_treasury));
    }

    function attack() external {
        if (!attacked) {
            attacked = true;
            treasury.execute(1);
        }
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            treasury.execute(1);
        }
    }
}
