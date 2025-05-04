// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "./IERC20.sol";

interface IDonationPool {
    enum POOLSTATUS {
        ACTIVE, // Pool is active and accepting donations
        SUCCESSFUL, // Funding goal reached
        FAILED, // Deadline reached without meeting goal
        DELETED // Pool deleted by admin
    }

    enum FUNDINGMODEL {
        ALL_OR_NOTHING, // Funds only released if goal is reached
        KEEP_WHAT_YOU_RAISE // Funds released regardless of goal
    }

    struct PoolAdmin {
        address creator; // Project creator
        uint16 platformFeeRate; // Fee rate for platform (0.01% to 100%)
        bool disputed; // Flag for disputed projects
    }

    struct PoolDetail {
        uint40 startTime; // Start time for the donation period
        uint40 endTime; // End time for the donation period
        string projectName; // Name of the project
        string projectDescription; // Description of the project
        string projectUrl; // URL for more information
        string imageUrl; // URL for project image
        uint256 fundingGoal; // Target amount to raise
        FUNDINGMODEL fundingModel; // Funding model for the project
    }

    struct PoolBalance {
        uint256 totalDonations; // Total donations received
        uint256 feesAccumulated; // Platform fees accumulated
        uint256 feesCollected; // Platform fees collected
        uint256 balance; // Current balance in the pool
    }

    struct DonorDetail {
        uint256 totalDonated; // Total amount donated by this donor
        uint256 refundClaimed; // Amount of refund claimed (for ALL_OR_NOTHING model)
        bool hasRefunded; // Whether donor has claimed refund
    }

    // ----------------------------------------------------------------------------
    // Donor Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Donate to a project
     * @param poolId The pool id
     * @param amount The amount to donate
     * @return success Whether the donation was successful
     */
    function donate(uint256 poolId, uint256 amount) external returns (bool);

    /**
     * @notice Claim refund for failed ALL_OR_NOTHING project
     * @param poolId The pool id
     */
    function claimRefund(uint256 poolId) external;

    // ----------------------------------------------------------------------------
    // Creator Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Create a new donation project
     * @param startTime When the donation period starts
     * @param endTime When the donation period ends
     * @param projectName Name of the project
     * @param projectDescription Description of the project
     * @param projectUrl URL for more information
     * @param imageUrl URL for project image
     * @param fundingGoal Target amount to raise
     * @param fundingModel Funding model (ALL_OR_NOTHING or KEEP_WHAT_YOU_RAISE)
     * @param token Token used for donations (e.g., cUSD)
     * @return poolId The ID of the created project
     */
    function createProject(
        uint40 startTime,
        uint40 endTime,
        string calldata projectName,
        string calldata projectDescription,
        string calldata projectUrl,
        string calldata imageUrl,
        uint256 fundingGoal,
        FUNDINGMODEL fundingModel,
        address token
    ) external returns (uint256);

    /**
     * @notice Update project details
     * @param poolId The pool id
     * @param projectName New name for the project
     * @param projectDescription New description for the project
     * @param projectUrl New URL for more information
     * @param imageUrl New URL for project image
     */
    function updateProjectDetails(
        uint256 poolId,
        string calldata projectName,
        string calldata projectDescription,
        string calldata projectUrl,
        string calldata imageUrl
    ) external;

    /**
     * @notice Change the end time of a project
     * @param poolId The pool id
     * @param endTime New end time
     */
    function changeEndTime(uint256 poolId, uint40 endTime) external;

    /**
     * @notice Withdraw funds from a successful project or KEEP_WHAT_YOU_RAISE project after deadline
     * @param poolId The pool id
     */
    function withdrawFunds(uint256 poolId) external;

    /**
     * @notice Cancel a project (only if no donations received)
     * @param poolId The pool id
     */
    function cancelProject(uint256 poolId) external;

    // ----------------------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Get project creator
     * @param poolId The pool id
     * @return creator The creator address
     */
    function getProjectCreator(uint256 poolId) external view returns (address);

    /**
     * @notice Get project details
     * @param poolId The pool id
     * @return details The project details
     */
    function getProjectDetails(
        uint256 poolId
    ) external view returns (PoolDetail memory);

    /**
     * @notice Get project balance
     * @param poolId The pool id
     * @return balance The current balance of the project
     */
    function getProjectBalance(uint256 poolId) external view returns (uint256);

    /**
     * @notice Get funding progress
     * @param poolId The pool id
     * @return progress The current funding progress (0-100%)
     */
    function getFundingProgress(uint256 poolId) external view returns (uint256);

    /**
     * @notice Get projects created by an address
     * @param creator The creator address
     * @return poolIds The project IDs created by this address
     */
    function getProjectsCreatedBy(
        address creator
    ) external view returns (uint256[] memory);

    /**
     * @notice Get projects donated to by an address
     * @param donor The donor address
     * @return poolIds The project IDs donated to by this address
     */
    function getProjectsDonatedToBy(
        address donor
    ) external view returns (uint256[] memory);

    /**
     * @notice Get donation details for a donor
     * @param poolId The pool id
     * @param donor The donor address
     * @return details The donation details
     */
    function getDonationDetails(
        uint256 poolId,
        address donor
    ) external view returns (DonorDetail memory);

    /**
     * @notice Get all donors for a project
     * @param poolId The pool id
     * @return donors The list of donor addresses
     */
    function getProjectDonors(
        uint256 poolId
    ) external view returns (address[] memory);

    /**
     * @notice Check if a project is successful (reached its funding goal)
     * @param poolId The pool id
     * @return isSuccessful Whether the project reached its funding goal
     */
    function isProjectSuccessful(uint256 poolId) external view returns (bool);

    /**
     * @notice Check if a project has failed (deadline reached without meeting goal)
     * @param poolId The pool id
     * @return hasFailed Whether the project has failed
     */
    function hasProjectFailed(uint256 poolId) external view returns (bool);

    // ----------------------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Pause all contract operations (admin only)
     */
    function pause() external;

    /**
     * @notice Unpause contract operations (admin only)
     */
    function unpause() external;

    /**
     * @notice Flag a project as disputed (admin only)
     * @param poolId The pool id
     */
    function flagProjectAsDisputed(uint256 poolId) external;

    /**
     * @notice Resolve a disputed project (admin only)
     * @param poolId The pool id
     * @param resolveInFavorOfCreator Whether to resolve in favor of the creator
     */
    function resolveDispute(
        uint256 poolId,
        bool resolveInFavorOfCreator
    ) external;

    /**
     * @notice Set platform fee rate (admin only)
     * @param newFeeRate The new platform fee rate (0.01% to 100%)
     */
    function setPlatformFeeRate(uint16 newFeeRate) external;

    /**
     * @notice Collect platform fees (admin only)
     * @param token The token to collect fees for
     */
    function collectPlatformFees(IERC20 token) external;

    /**
     * @notice Emergency withdraw in case of critical issues (admin only, when paused)
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function emergencyWithdraw(IERC20 token, uint256 amount) external;
}
