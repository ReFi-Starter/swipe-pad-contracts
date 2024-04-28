// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";

contract PoolScript is Script {
    Pool public pool;
    Droplet public token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        pool = new Pool();
        vm.stopBroadcast();
    }

    function run_withMock() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        pool = new Pool();
        token = new Droplet();
        vm.stopBroadcast();
    }
}
