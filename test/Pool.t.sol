// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";

contract PoolTest is Test {
    Pool public pool;
    Droplet public token;
    address public host;
    address public alice;

    function setUp() public {
        pool = new Pool();
        token = new Droplet();
        host = vm.addr(1);
        alice = vm.addr(2);
        vm.warp(1713935623);
    }

    function test_createPool() public {
        vm.startPrank(host);
        address[] memory cohosts = new address[](0);
        uint16 feeRate = 3000; // 30% fees

        pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            100e18,
            feeRate,
            token,
            cohosts
        );
        address res = pool.getHost(1);

        assertEq(res, host);
        vm.stopPrank();
    }

    function test_createPool_withInvalidFeeRate() external {
        vm.startPrank(host);
        address[] memory cohosts = new address[](0);
        uint16 feeRate = 10001; // 100.01% fees

        vm.expectRevert();
        pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            100e18,
            feeRate,
            token,
            cohosts
        );
        vm.stopPrank();
    }

    function test_deposit() public {
        test_createPool();
        uint256 amount = 100e18;
        token.mint(alice, amount);

        vm.startPrank(host);
        pool.enableDeposit(1);

        vm.startPrank(alice);
        token.approve(address(pool), amount);
        pool.deposit(1, amount);
        uint256 res = pool.getParticipantDeposit(alice, 1);

        assertEq(res, amount);
        vm.stopPrank();
    }

    function test_deposit_withoutEnablingDeposit() external {
        test_createPool();
        uint256 amount = 100e18;
        token.mint(alice, amount);

        vm.startPrank(alice);
        token.approve(address(pool), amount);
        vm.expectRevert();
        pool.deposit(1, amount);
        vm.stopPrank();
    }

    function test_selfRefund() external {
        test_deposit();
        uint256 amountDeposited = 100e18;

        vm.startPrank(alice);
        pool.selfRefund(1);
        uint256 res = token.balanceOf(alice);

        console.log(block.timestamp);
        assertEq(res, amountDeposited);
        vm.stopPrank();
    }
}
