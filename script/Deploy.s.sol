// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AresTreasury} from "../src/core/AresTreasury.sol";
import {ProposalModule} from "../src/modules/ProposalModule.sol";
import {AuthorizationModule} from "../src/modules/AuthorizationModule.sol";
import {RewardDistributionModule} from "../src/modules/RewardDistributionModule.sol";
import {GovernanceDefenseModule} from "../src/modules/GovernanceDefenseModule.sol";

contract AresTreasuryDeploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");
        address rewardToken = vm.envAddress("REWARD_TOKEN");

        vm.startBroadcast(deployerPrivateKey);

        AuthorizationModule authModule = new AuthorizationModule();

        GovernanceDefenseModule defenseModule = new GovernanceDefenseModule(governance);

        RewardDistributionModule rewardModule = new RewardDistributionModule(
            rewardToken,
            governance
        );

        ProposalModule proposalModule = new ProposalModule(
            address(authModule),
            governance
        );

        AresTreasury treasury = new AresTreasury(
            address(authModule),
            payable(address(proposalModule)),
            address(rewardModule),
            address(defenseModule)
        );

        defenseModule.setTreasury(address(treasury));
        rewardModule.setTreasury(address(treasury));
        proposalModule.setTreasury(address(treasury));

        console.log("ARES Protocol Deployed");
        console.logAddress(address(treasury));
        console.logAddress(address(authModule));
        console.logAddress(address(proposalModule));
        console.logAddress(address(rewardModule));
        console.logAddress(address(defenseModule));

        vm.stopBroadcast();
    }
}

contract AresTreasuryDeployLocal is Script {
    function run() external {
        address deployer = msg.sender;
        address governance = deployer;
        address rewardToken = address(0x1234); 

        vm.startBroadcast(deployer);

        AuthorizationModule authModule = new AuthorizationModule();

        GovernanceDefenseModule defenseModule = new GovernanceDefenseModule(governance);

        RewardDistributionModule rewardModule = new RewardDistributionModule(
            rewardToken,
            governance
        );

        ProposalModule proposalModule = new ProposalModule(
            address(authModule),
            governance
        );

        AresTreasury treasury = new AresTreasury(
            address(authModule),
            payable(address(proposalModule)),
            address(rewardModule),
            address(defenseModule)
        );

        defenseModule.setTreasury(address(treasury));
        rewardModule.setTreasury(address(treasury));
        proposalModule.setTreasury(address(treasury));

        console.log("ARES Protocol Deployed (Local)");
        console.log("Treasury:", address(treasury));
        console.log("Auth Module:", address(authModule));
        console.log("Proposal Module:", address(proposalModule));
        console.log("Reward Module:", address(rewardModule));
        console.log("Defense Module:", address(defenseModule));

        vm.stopBroadcast();
    }
}
