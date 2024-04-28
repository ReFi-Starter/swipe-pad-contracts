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

    function setUp() public {
        pool = new Pool();
        token = new Droplet();
        host = vm.addr(1);
        alice = vm.addr(2);
        vm.warp(1713935623);

        // Create a pool
        vm.startPrank(host);
        uint16 feeRate = 3000; // 30% fees
        pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            100e18,
            feeRate,
            address(token)
        );
        pool.enableDeposit(1);

        // Deposit to the pool
        uint256 amount = 100e18;
        token.mint(alice, amount);
        vm.startPrank(alice);
        token.approve(address(pool), amount);
        pool.deposit(1, amount);
    }

	function test_pause() external {
		vm.startPrank(address(this));
		pool.pause();
		bool paused = pool.paused();
		assertEq(paused, true);
		vm.stopPrank();
	}

	function test_pause_nonAdmin() external {
		vm.startPrank(host);
		vm.expectRevert();
		pool.pause();
		vm.stopPrank();
	}

	function test_unpause() external {
		// Setup
		vm.startPrank(address(this));
		pool.pause();

		// Unpause contract
		pool.unpause();
		bool paused = pool.paused();
		assertEq(paused, false);
		vm.stopPrank();
	}

	function test_unpause_nonAdmin() external {
		// Setup
		vm.startPrank(address(this));
		pool.pause();

		// Should fail
		vm.startPrank(host);
		vm.expectRevert();
		pool.unpause();
		vm.stopPrank();
	}
}