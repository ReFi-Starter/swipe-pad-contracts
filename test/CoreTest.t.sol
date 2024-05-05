// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";
import "../src/library/ConstantsLib.sol";

contract CoreTest is Test {
    Pool public pool;
    Droplet public token;
    address public host;
    address public alice;
    uint256 public amountToDeposit;
    uint256 public poolId;

    modifier turnOffGasMetering() {
        vm.pauseGasMetering();
        _;
        vm.resumeGasMetering();
    }

    function setUp() public {
        pool = new Pool();
        token = new Droplet();
        host = vm.addr(1);
        alice = vm.addr(2);
    }

    function test_createPool() public {
        vm.startPrank(host);
        uint16 feeRate = 3000; // 30% fees

        poolId = pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            100e18,
            feeRate,
            address(token)
        );
        address res = pool.getHost(poolId);

        assertEq(res, host);
        vm.stopPrank();
    }

    function test_createPool_withInvalidFeeRate() external {
        vm.startPrank(host);
        uint16 feeRate = 10001; // 100.01% fees

        // Should fail
        vm.expectRevert();
        pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            100e18,
            feeRate,
            address(token)
        );
        vm.stopPrank();
    }

    function test_deposit() public {
        helper_createPool();

        token.mint(alice, amountToDeposit);
        vm.startPrank(alice);
        token.approve(address(pool), amountToDeposit);
        pool.deposit(poolId, amountToDeposit);
        uint256 res = pool.getParticipantDeposit(alice, poolId);

        assertEq(res, amountToDeposit);
        vm.stopPrank();
    }

    function test_deposit_withoutEnablingDeposit() external {
        helper_createPool();

        // Reset enableDeposit to false
        vm.store(address(pool), 0x3e5fec24aa4dc4e5aee2e025e51e1392c72a2500577559fae9665c6d52bd6a31, 0);

        // Try reset success
        token.mint(alice, amountToDeposit);
        vm.startPrank(alice);
        token.approve(address(pool), amountToDeposit);
        try pool.deposit(poolId, amountToDeposit) {
            // Should not reach here
            console.log("Should not reach here");
        } catch Error(string memory reason) {
            console.log(reason);
            console.log("Reset successfully");
        }

        // Real test
        vm.expectRevert();
        pool.deposit(poolId, amountToDeposit);
        vm.stopPrank();
    }

    function test_selfRefund() external {
        helper_createPool();
        helper_deposit();

        uint256 amountDeposited = 100e18;

        vm.startPrank(alice);
        pool.selfRefund(poolId);
        uint256 res = token.balanceOf(alice);

        assertEq(res, amountDeposited);
        vm.stopPrank();
    }

    function test_selfRefund_withFeesSetByHostDeducted() public {
        helper_createPool();
        helper_deposit();

        uint256 amountDeposited = 100e18;

        vm.startPrank(alice);
        vm.warp(block.timestamp + 9 days); // 24 hours Before pool start time
        pool.selfRefund(poolId);
        uint256 res = token.balanceOf(alice);

        uint256 expected = amountDeposited - (amountDeposited * pool.getPoolFeeRate(poolId)) / FEES_PRECISION;
        assertEq(res, expected);
        vm.stopPrank();
    }

    function test_selfRefund_with100PercentFeesDeducted() external {
        helper_createPool();
        helper_deposit();

        vm.startPrank(alice);
        vm.warp(block.timestamp + 10 days + 1); // After pool start time
        pool.selfRefund(poolId);
        uint256 res = token.balanceOf(alice);

        assertEq(res, 0);
        vm.stopPrank();
    }

    function test_deposit_afterStartPool() external {
        helper_createPool();

        token.mint(alice, amountToDeposit);

        // Start pool
        vm.startPrank(host);
        pool.startPool(poolId);

        // Should fail
        vm.startPrank(alice);
        token.approve(address(pool), amountToDeposit);
        vm.expectRevert();
        pool.deposit(poolId, amountToDeposit);
        vm.stopPrank();
    }

    function test_deposit_lesserAmount() external {
        helper_createPool();

        uint256 lesserAmount = amountToDeposit - 1;
        token.mint(alice, lesserAmount);

        // Should fail
        vm.startPrank(alice);
        token.approve(address(pool), lesserAmount);
        vm.expectRevert();
        pool.deposit(poolId, lesserAmount);
        vm.stopPrank();
    }

    function test_deposit_greaterAmount() external {
        helper_createPool();

        uint256 greaterAmount = amountToDeposit + 10000e18;
        token.mint(alice, greaterAmount);

        vm.startPrank(alice);
        token.approve(address(pool), greaterAmount);
        pool.deposit(poolId, greaterAmount);
        uint256 extra = pool.getExtraBalance(poolId);
        // Extra balance should be 10000e18
        assertEq(extra, 10000e18);
        vm.stopPrank();
    }

    function test_setWinner() external {
        helper_createPool();
        helper_deposit();

        uint256 winnings = 23e18;

        vm.startPrank(host);
        pool.startPool(poolId);
        pool.endPool(poolId);
        pool.setWinner(poolId, alice, winnings);
        uint256 res = pool.getWinningAmount(poolId, alice);

        assertEq(res, winnings);
        vm.stopPrank();
    }

    function test_setMultipleWinners_poolRemainingBalanceShouldBeZero() external {
        helper_createPool();
        helper_deposit();

        // Setup
        uint256 winning = 125e18; // 5 deposits divided by 4 winners
        uint256[] memory winnings = new uint256[](4);
        address[] memory winners = new address[](4);
        for (uint256 i = 0; i < 4; i++) {
            winners[i] = vm.addr(i + 4);
            winnings[i] = winning;
            token.mint(winners[i], amountToDeposit);
            vm.startPrank(winners[i]);
            token.approve(address(pool), amountToDeposit);
            pool.deposit(poolId, amountToDeposit);
        }
        vm.startPrank(host);
        pool.startPool(poolId);
        pool.endPool(poolId);
        pool.setWinners(
            poolId, 
            winners,
            winnings
        );
        uint256 res = pool.getPoolBalance(poolId);

        // Remaining balance should be 0
        assertEq(res, 0);
        vm.stopPrank();
    }

    function test_setWinner_participantNotDeposited() external {
        helper_createPool();
        helper_deposit();

        uint256 winning = amountToDeposit;
        vm.startPrank(host);
        pool.startPool(poolId);
        pool.endPool(poolId);

        // Should fail because participant has not deposited
        vm.expectRevert();
        pool.setWinner(
            poolId, 
            vm.addr(0xBEEF),
            winning
        );
        vm.stopPrank();
    }

    function test_setWinner_beforeStartPool() external {
        helper_createPool();
        helper_deposit();
            
        uint256 winning = amountToDeposit;

        // Should fail because pool is not started
        vm.expectRevert();
        pool.setWinner(
            poolId, 
            alice,
            winning
        );
    }

    function test_claimWinnings() external {
        helper_createPool();
        helper_deposit();

        uint256 winnings = 23e18;

        vm.startPrank(host);
        pool.startPool(poolId);
        pool.endPool(poolId);
        pool.setWinner(poolId, alice, winnings);

        vm.startPrank(alice);
        pool.claimWinning(poolId, alice);
        uint256 res = token.balanceOf(alice);

        assertEq(res, winnings);
        vm.stopPrank();
    }

    function test_collectFees() external {
        vm.pauseGasMetering();
        test_selfRefund_withFeesSetByHostDeducted();
        vm.resumeGasMetering();

        // Get fees accumulated
        uint256 fees = pool.getFeesAccumulated(poolId);
        uint256 balanceBefore = token.balanceOf(host);
        uint256 poolBalanceBefore = pool.getPoolBalance(poolId);

        // Check fees collected before calling collectFees
        assertEq(pool.getFeesCollected(poolId), 0);
        pool.collectFees(poolId);
        uint256 balanceAfter = token.balanceOf(host);
        uint256 poolBalanceAfter = pool.getPoolBalance(poolId);

        assertEq(balanceAfter - balanceBefore, fees);
        assertEq(pool.getFeesAccumulated(poolId) - pool.getFeesCollected(poolId), 0);
        assertEq(poolBalanceBefore - poolBalanceAfter, fees);
    }

    function test_collectRemainingBalance() external {
        helper_createPool();
        helper_deposit();

        vm.startPrank(host);
        pool.startPool(poolId);
        pool.endPool(poolId);

        uint256 remainingBalance = pool.getPoolBalance(poolId);
        uint256 balanceBefore = token.balanceOf(host);
        pool.collectRemainingBalance(poolId);
        uint256 balanceAfter = token.balanceOf(host);

        assertEq(balanceAfter - balanceBefore, remainingBalance);
        assertEq(pool.getPoolBalance(poolId), 0);
        vm.stopPrank();
    }

    function test_collectRemainingBalance_tryExploitOtherPoolByHost() external {
        helper_createPool();
        helper_deposit();

        // Set up another pool
        vm.pauseGasMetering();
        address bob = vm.addr(3);
        token.mint(bob, amountToDeposit);
        vm.startPrank(alice);
        uint256 newPoolId = pool.createPool(
            uint40(block.timestamp), 
            uint40(block.timestamp + 10 days), 
            "New", 
            amountToDeposit, 
            0, 
            address(token)
        );
        pool.enableDeposit(newPoolId);
        vm.startPrank(bob);
        token.approve(address(pool), amountToDeposit);
        pool.deposit(newPoolId, amountToDeposit);

        // Do self refund to accumulate fees
        vm.startPrank(alice);
        vm.warp(block.timestamp + 9 days); // 24 hours Before pool start time
        pool.selfRefund(poolId);

        vm.resumeGasMetering();

        vm.startPrank(host);
        pool.startPool(poolId);
        pool.endPool(poolId);

        // Get remaining balance
        uint256 remainingBalance = pool.getPoolBalance(poolId);
        uint256 balanceBefore = token.balanceOf(host);

        pool.collectRemainingBalance(poolId);
        uint256 balanceAfter = token.balanceOf(host);

        assertEq(balanceAfter - balanceBefore, remainingBalance);
        // PoolId balance should be 0
        assertEq(pool.getPoolBalance(poolId), 0);
        // Try collectFees after 0 balance since there's fees accumulated
        uint256 fees = pool.getFeesAccumulated(poolId) - pool.getFeesCollected(poolId);
        assert(fees > 0);
        vm.expectRevert();
        pool.collectFees(poolId);
        vm.stopPrank();
        // Overall pool balance should be 100e18 (Test cross pool withdrawal by host)
        assertEq(token.balanceOf(address(pool)), amountToDeposit);
    }

    function test_getAllPoolInfo() external {
        helper_createPool();
        helper_deposit();

        // Use -vvvv to check returns
        pool.getAllPoolInfo(poolId);
    }

    function test_refundParticipant() external {
        helper_createPool();
        helper_deposit();

        vm.startPrank(host);
        pool.startPool(poolId);
        pool.endPool(poolId);

        uint256 amountRefund = 25e18;
        uint256 balanceBefore = token.balanceOf(alice);
        pool.refundParticipant(poolId, alice, amountRefund);
        uint256 balanceAfter = token.balanceOf(alice);

        assertEq(balanceAfter - balanceBefore, amountRefund);
    }

    function test_forfeitWinnings() external {
        helper_createPool();
        helper_deposit();

        uint256 winnings = 23e18;

        vm.startPrank(host);
        pool.startPool(poolId);
        pool.endPool(poolId);
        vm.warp(block.timestamp + 1 days);
        pool.setWinner(poolId, alice, winnings);

        pool.forfeitWinnings(poolId, alice);
        uint256 res = token.balanceOf(alice);

        assertEq(res, 0);
        assert(pool.getWinningAmount(poolId, alice) == 0);
    }

    // ----------------------------------------------------------------------------
    // Helper Functions
    // ----------------------------------------------------------------------------

    function helper_createPool() private turnOffGasMetering {
        // Warp to random time
        vm.warp(1713935623);

        // Create a pool
        vm.startPrank(host);
        amountToDeposit = 100e18;
        uint16 feeRate = 3000; // 30% fees
        poolId = pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            amountToDeposit,
            feeRate,
            address(token)
        );
        pool.enableDeposit(poolId);
    }

    function helper_deposit() private turnOffGasMetering {
        // Deposit to the pool
        token.mint(alice, amountToDeposit);
        vm.startPrank(alice);
        token.approve(address(pool), amountToDeposit);
        pool.deposit(poolId, amountToDeposit);
    }
}
