// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IPool {
	enum POOLSTATUS {
		INACTIVE,
		DEPOSIT_ENABLED,
		STARTED,
		ENDED,
		DELETED
	}

	struct PoolAdmin {
		address host;
		uint16 penaltyFeeRate; // 0.01% (1) to 100% (10000)
		address[] cohosts;
	}

	struct PoolDetail {
		uint40 timeStart;
		uint40 timeEnd;
		string poolName;
		uint256 depositAmountPerPerson;
	}

	struct PoolBalance {
		uint256 totalDeposits;
		uint256 feesAccumulated;
		uint256 feesCollected;
		uint256 balance;
	}

	struct ParticipantDetail {
		uint256 deposit; // used for isParticipant too
		uint256 feesCharged;
		uint256 toClaim; // winnings
		bool claimed;
		bool refunded;
	}	
}