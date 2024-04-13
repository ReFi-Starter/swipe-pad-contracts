// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Owned} from "solmate/auth/Owned.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract Pool is Owned {
	enum POOLSTATUS {
		INACTIVE,
		DEPOSIT_ENABLED,
		DEPOSIT_DISABLED,
		FUND_DISTRIBUTED
	}

	struct Participant {
		address participant;
		uint256 deposit;
		uint256 feesCharged;
	}

	struct PoolDetails {
		// Pool status
		POOLSTATUS status;

		// Pool timing
		uint40 timeStart;
		uint40 timeEnd;

		// Pool fees
		uint16 penaltyFeesRate;	// 0.01% to 100% (10000)

		// Pool capacity
		uint32 maxParticipants;
		uint32 numParticipantsJoined;

		// Pool addresses
		address host;
		address cohost;
		IERC20 token;

		// Pool details
		string poolName;
		uint256 amountToDeposit;

		// Pool balances
		uint256 totalDeposits;
		uint256 feesCollected;
		uint256 balance;

		Participant[] participants;
	}
	
	uint16 constant public FEES_PRECISION = 10000;

	uint256 public latestPoolId;

	mapping (uint256 => PoolDetails) public pools;
	mapping (address => uint256[]) public createdPools;

	event PoolCreated(uint256 poolId, address host, PoolDetails poolDetails);
	event PoolStatusChanged(uint256 poolId, POOLSTATUS status);
	event Deposit(uint256 poolId, address participant, uint256 amount);

	constructor(address _owner) Owned(_owner) {}

	/// @notice Create a new pool
	/// @param poolName The name of the pool
	/// @param token The token address
	/// @param cohost The cohost address
	/// @param timeStart The start time of the pool
	/// @param timeEnd The end time of the pool
	/// @param penaltyFeesRate The penalty fees rate
	/// @return poolId The pool id
	/// @dev Pool status will be INACTIVE
	/// @dev Pool will be added to createdPools mapping
	/// @dev Emits PoolCreated event
	function createPool(
		string calldata poolName,
		IERC20 token,
		address cohost,
		uint40 timeStart,
		uint40 timeEnd,
		uint16 penaltyFeesRate,
		uint32 maxParticipants,
		uint256 amountToDeposit
	) external returns (uint256 poolId) {
		require(timeStart < timeEnd, "Invalid timing");
		require(address(token) != address(0), "Invalid token");
		require(penaltyFeesRate <= FEES_PRECISION, "Invalid fees rate");
		require(amountToDeposit > 0, "Invalid deposit amount");
		poolId = latestPoolId;

		pools[poolId].timeStart = timeStart;
		pools[poolId].timeEnd = timeEnd;
		pools[poolId].penaltyFeesRate = penaltyFeesRate;
		pools[poolId].host = msg.sender;
		pools[poolId].token = token;
		pools[poolId].poolName = poolName;
		pools[poolId].amountToDeposit = amountToDeposit;
		if (cohost != address(0)) {
			pools[poolId].cohost = cohost;
		}
		if (maxParticipants == 0) {
			pools[poolId].maxParticipants = type(uint32).max;
		} else {
			pools[poolId].maxParticipants = maxParticipants;
		}
		emit PoolCreated(poolId, msg.sender, pools[poolId]);

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
		require(amount == pool.amountToDeposit, "Deposit amount not correct");

		// Transfer tokens from user to pool
		bool success = pool.token.transferFrom(msg.sender, address(this), amount);
		require(success, "Transfer failed");

		// Update pool details
		Participant memory participant;
		participant.deposit = amount;
		participant.participant = msg.sender;
		pools[poolId].participants.push(participant);
		pools[poolId].numParticipantsJoined++;
		pools[poolId].totalDeposits += amount;
		pools[poolId].balance += amount;

		emit Deposit(poolId, msg.sender, amount);
	}

	// ----------------------------------------------------------------------------
	// View Functions
	// ----------------------------------------------------------------------------

	function getPoolsCreatedBy(address host) external view returns (uint256[] memory) {
		return createdPools[host];
	}
}