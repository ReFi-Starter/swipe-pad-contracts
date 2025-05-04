// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDonationPool} from "../interface/IDonationPool.sol";

library DonationEventsLib {
    // Project creation and management events
    event ProjectCreated(
        uint256 indexed poolId,
        address indexed creator,
        string projectName,
        uint256 fundingGoal,
        address indexed token,
        IDonationPool.FUNDINGMODEL fundingModel
    );

    event ProjectDetailsUpdated(
        uint256 indexed poolId,
        string projectName,
        string projectDescription,
        string projectUrl,
        string imageUrl
    );

    event ProjectEndTimeChanged(uint256 indexed poolId, uint40 endTime);

    event ProjectStatusChanged(
        uint256 indexed poolId,
        IDonationPool.POOLSTATUS status
    );

    event ProjectCancelled(uint256 indexed poolId, address indexed creator);

    // Donation related events
    event DonationReceived(
        uint256 indexed poolId,
        address indexed donor,
        uint256 amount
    );

    event FundingGoalReached(uint256 indexed poolId, uint256 totalAmount);

    event FundingFailed(
        uint256 indexed poolId,
        uint256 totalAmount,
        uint256 goal
    );

    event RefundClaimed(
        uint256 indexed poolId,
        address indexed donor,
        uint256 amount
    );

    event FundsWithdrawn(
        uint256 indexed poolId,
        address indexed creator,
        uint256 amount
    );

    // Fee related events
    event PlatformFeeCollected(address indexed token, uint256 amount);

    event PlatformFeeRateChanged(uint16 oldRate, uint16 newRate);

    // Dispute resolution events
    event ProjectDisputed(uint256 indexed poolId, address indexed reporter);

    event DisputeResolved(
        uint256 indexed poolId,
        bool resolvedInFavorOfCreator
    );

    // Admin events
    event EmergencyWithdraw(address indexed token, uint256 amount);
}
