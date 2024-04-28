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
    }

    struct PoolDetail {
        uint40 timeStart;
        uint40 timeEnd;
        string poolName;
        uint256 depositAmountPerPerson;
    }

    struct PoolBalance {
        uint256 totalDeposits; // total deposit amount (won't reduce, for record)
        uint256 feesAccumulated;
        uint256 feesCollected;
        uint256 balance; // real current balance of pool
        uint256 extraBalance;
    }

    struct ParticipantDetail {
        uint256 deposit; // used for assertion and isParticipant
        uint256 feesCharged;
        uint120 participantIndex; // store index for easy removal
        uint120 joinedPoolsIndex; // store index for easy removal
        bool refunded;
    }

    struct WinnerDetail {
        uint256 amountWon;
        bool claimed;
    }
}
