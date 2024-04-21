// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Droplet is ERC20 {
    constructor() ERC20("Droplet", "DROP") {
        _mint(msg.sender, 1000000e18);
    }
}

contract PoolTest is Test {
    Pool public pool;
    Droplet public token;
    address public alice;

    function setUp() public {
        pool = new Pool();
        token = new Droplet();
        alice = vm.addr(1);
    }

    function test_create_pool() public {
        vm.startPrank(alice);
        address[] memory cohosts = new address[](0);
        uint16 feeRate = 10000;
        pool.createPool(
            uint40(block.timestamp),
            uint40(block.timestamp + 100),
            "PoolParty",
            100e18,
            feeRate,
            token,
            cohosts
        );
        address res = pool.getHost(1);
        assertEq(res, alice);
        vm.stopPrank();
    }
}
