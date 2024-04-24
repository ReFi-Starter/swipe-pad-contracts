// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";
import "../src/library/ConstantsLib.sol";

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

        // Create a pool
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
        pool.enableDeposit(1);

        // Deposit to the pool
        uint256 amount = 100e18;
        token.mint(alice, amount);
        vm.startPrank(alice);
        token.approve(address(pool), amount);
        pool.deposit(1, amount);
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
        address res = pool.getHost(2);

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
        uint256 amount = 100e18;
        alice = vm.addr(3); // reset address
        token.mint(alice, amount);

        vm.startPrank(alice);
        token.approve(address(pool), amount);
        pool.deposit(1, amount);
        uint256 res = pool.getParticipantDeposit(alice, 1);

        assertEq(res, amount);
        vm.stopPrank();
    }

    function test_deposit_withoutEnablingDeposit() external {
        // Reset enableDeposit to false
        vm.store(address(pool), 0x3e5fec24aa4dc4e5aee2e025e51e1392c72a2500577559fae9665c6d52bd6a31, 0);
        
        uint256 amount = 100e18;
        token.mint(alice, amount);

        vm.startPrank(alice);
        token.approve(address(pool), amount);
        vm.expectRevert();
        pool.deposit(1, amount);
        vm.stopPrank();
    }

    function test_selfRefund() external {
        uint256 amountDeposited = 100e18;

        vm.startPrank(alice);
        pool.selfRefund(1);
        uint256 res = token.balanceOf(alice);

        assertEq(res, amountDeposited);
        vm.stopPrank();
    }

    function test_selfRefund_withFeesDeducted() external {
        uint256 amountDeposited = 100e18;

        vm.startPrank(alice);
        vm.warp(block.timestamp + 9 days); // 24 hours Before pool start time
        pool.selfRefund(1);
        uint256 res = token.balanceOf(alice);

        uint256 expected = amountDeposited - (amountDeposited * pool.getPoolFeeRate(1)) / FEES_PRECISION;
        assertEq(res, expected);
        vm.stopPrank();
    }

    function test_selfRefund_withAllFeesDeducted() external {
        vm.startPrank(alice);
        vm.warp(block.timestamp + 10 days + 1); // After pool start time
        pool.selfRefund(1);
        uint256 res = token.balanceOf(alice);

        assertEq(res, 0);
        vm.stopPrank();
    }

    function test_deposit_afterStartPool() external {
        uint256 amount = 100e18;
        token.mint(alice, amount);

        vm.startPrank(host);
        pool.startPool(1);

        vm.startPrank(alice);
        token.approve(address(pool), amount);
        vm.expectRevert();
        pool.deposit(1, amount);
        vm.stopPrank();
    }
}
