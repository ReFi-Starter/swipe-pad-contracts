// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";
import {WHITELISTED_HOST, WHITELISTED_SPONSOR} from "../src/library/ConstantsLib.sol";

contract PoolScript is Script {
    Pool public pool;
    Droplet public token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        pool = new Pool();
        vm.stopBroadcast();
    }

    function run_whitelist() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address toWhitelist = 0x2B7E209755760b4E47d56299535A4F239236e1eD;

        pool = Pool(0x5CA11740144513897Be27e3E82D75Aa75067F712);
        pool.grantRole(WHITELISTED_HOST, toWhitelist);
        pool.grantRole(WHITELISTED_SPONSOR, toWhitelist);
        
        vm.stopBroadcast();
    }

    function run_withMock() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        pool = new Pool();
        token = new Droplet();
        vm.stopBroadcast();
    }

    function run_withSetup() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address signer = vm.addr(vm.envUint("PRIVATE_KEY"));
        pool = new Pool();
        token = Droplet(0xfD2Ec58cE4c87b253567Ff98ce2778de6AF0101b);

        uint256 amount = 20e18;
        if (token.balanceOf(signer) == 0) {
            token.mint(signer, 1000e18);
        }
        pool.grantRole(WHITELISTED_HOST, signer);
        uint256 poolId = pool.createPool(
            uint40(block.timestamp + 2 days),
            uint40(block.timestamp + 2 days + 6 hours),
            "Test pool",
            amount,
            address(0xfD2Ec58cE4c87b253567Ff98ce2778de6AF0101b)
        );
        pool.enableDeposit(poolId);
        token.approve(address(pool), amount);
        pool.deposit(poolId, amount);
        vm.stopBroadcast();
    }
}
