// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {DonationPool} from "../src/DonationPool.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";
import {IDonationPool} from "../src/interface/IDonationPool.sol";

contract DonationPoolScript is Script {
    DonationPool public donationPool;
    MockERC20 public token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        donationPool = new DonationPool();
        vm.stopBroadcast();
    }

    function run_withMock() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        donationPool = new DonationPool();
        token = new MockERC20("Test Token", "TST", 18);
        vm.stopBroadcast();
    }

    function run_createCampaign() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address signer = vm.addr(vm.envUint("PRIVATE_KEY"));

        // Address should be replaced with actual deployed contract address
        donationPool = DonationPool(0x0000000000000000000000000000000000000000);
        token = MockERC20(0x0000000000000000000000000000000000000000);

        uint256 amount = 20e18;
        if (token.balanceOf(signer) == 0) {
            token.mint(signer, 1000e18);
        }

        // Create a test campaign
        uint256 poolId = donationPool.createCampaign(
            uint40(block.timestamp + 2 days),
            uint40(block.timestamp + 2 days + 6 hours),
            "Test Campaign",
            "This is a test donation campaign",
            "https://example.com",
            "https://example.com/image.jpg",
            100e18, // funding goal
            IDonationPool.FUNDINGMODEL.ALL_OR_NOTHING,
            address(token)
        );

        // Make a donation to the campaign
        token.approve(address(donationPool), amount);
        donationPool.donate(poolId, amount);

        vm.stopBroadcast();
    }
}
