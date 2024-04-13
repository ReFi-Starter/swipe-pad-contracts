// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Owned} from "solmate/auth/Owned.sol";

contract Pool is Owned {
	enum POOLSTATUS {
		INACTIVE,
		DEPOSIT_ENABLED,
		DEPOSIT_DISABLED,
		FUND_DISTRIBUTED
	}

	struct PoolDetails {
		// Pool status
		POOLSTATUS status;

		// Pool timing
		uint40 timeStart;
		uint40 timeEnd;

		// Pool addresses
		address host;
		address cohost;
		address token;

		// Pool details
		string poolName;

		// Pool balances
		uint256 totalDeposits;
		uint256 balance;
	}

	uint256 public latestPoolId;

	mapping (uint256 => PoolDetails) public pools;
	mapping (address => uint256[]) public createdPools;

	event PoolCreated(uint256 poolId, address host, address token);
	event PoolStatusChanged(uint256 poolId, POOLSTATUS status);

	constructor(address _owner) Owned(_owner) {}

	/// @notice Create a new pool
	/// @param poolName The name of the pool
	/// @param token The token address
	/// @param cohost The cohost address
	/// @param timeStart The start time of the pool
	/// @param timeEnd The end time of the pool
	/// @return poolId The pool id
	/// @dev Pool status will be INACTIVE
	/// @dev Pool will be added to createdPools mapping
	/// @dev Emits PoolCreated event
	function createPool(
		string calldata poolName,
		address token,
		address cohost,
		uint40 timeStart,
		uint40 timeEnd
	) external returns (uint256 poolId) {
		require(timeStart < timeEnd, "Invalid timing");
		require(token != address(0), "Invalid token");
		poolId = latestPoolId;

		pools[poolId] = PoolDetails({
			status: POOLSTATUS.INACTIVE,
			timeStart: timeStart,
			timeEnd: timeEnd,
			host: msg.sender,
			cohost: cohost,
			token: token,
			poolName: poolName,
			totalDeposits: 0,
			balance: 0
		});
		emit PoolCreated(poolId, msg.sender, token);

		createdPools[msg.sender].push(poolId);
		latestPoolId++;
	}

	/// @notice Enable deposit for a pool
	/// @param poolId The pool id
	/// @dev Only the host or cohost can enable deposit
	/// @dev Pool status must be INACTIVE
	/// @dev Pool timing must be within the deposit window
	/// @dev Pool status will be changed to DEPOSIT_ENABLED
	/// @dev Emits PoolStatusChanged event
	function enableDeposit(uint256 poolId) external {
		PoolDetails memory pool = pools[poolId];
		require(msg.sender == pool.host || msg.sender == pool.cohost, "Unauthorized");
		require(pool.status == POOLSTATUS.INACTIVE, "Deposit already enabled");

		pools[poolId].status = POOLSTATUS.DEPOSIT_ENABLED;
		emit PoolStatusChanged(poolId, POOLSTATUS.DEPOSIT_ENABLED);
	}

	function deposit(uint256 poolId, uint256 amount) external {
		PoolDetails memory pool = pools[poolId];
		require(pool.status == POOLSTATUS.DEPOSIT_ENABLED, "Deposit not enabled");
		require(block.timestamp <= pool.timeStart, "Deposit not allowed");

		// Transfer tokens from user to pool
		pool.token.transferFrom(msg.sender, address(this), amount);

		pools[poolId].totalDeposits += amount;
		pools[poolId].balance += amount;
	}

	// ----------------------------------------------------------------------------
	// View Functions
	// ----------------------------------------------------------------------------

	function getPoolsCreatedBy(address host) external view returns (uint256[] memory) {
		return createdPools[host];
	}
}