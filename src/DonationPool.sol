// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// Interfaces
import {IDonationPool} from "./interface/IDonationPool.sol";
import {IERC20} from "./interface/IERC20.sol";

/// Libraries
import {FEES_PRECISION, DEFAULT_PLATFORM_FEE, MIN_FUNDING_PERIOD, MAX_FUNDING_PERIOD, MIN_FUNDING_GOAL, REFUND_GRACE_PERIOD, DISPUTE_RESOLUTION_PERIOD} from "./library/DonationConstantsLib.sol";
import {DonationEventsLib} from "./library/DonationEventsLib.sol";
import {DonationErrorsLib} from "./library/DonationErrorsLib.sol";
import {DonationPoolAdminLib} from "./library/DonationPoolAdminLib.sol";
import {DonationPoolDetailLib} from "./library/DonationPoolDetailLib.sol";
import {DonationPoolBalanceLib} from "./library/DonationPoolBalanceLib.sol";
import {DonorDetailLib} from "./library/DonorDetailLib.sol";
import {UtilsLib} from "./library/UtilsLib.sol";
import {SafeTransferLib} from "./library/SafeTransferLib.sol";

/// Dependencies
import {Ownable2Step} from "./dependency/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract DonationPool is IDonationPool, Ownable2Step, AccessControl, Pausable {
    using SafeTransferLib for IERC20;
    using DonationPoolAdminLib for IDonationPool.PoolAdmin;
    using DonationPoolDetailLib for IDonationPool.PoolDetail;
    using DonationPoolBalanceLib for IDonationPool.PoolBalance;
    using DonorDetailLib for IDonationPool.DonorDetail;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public latestPoolId; // Start from 1, 0 is invalid
    uint16 public platformFeeRate; // Default platform fee rate

    /// @dev Pool specific mappings
    mapping(uint256 => PoolAdmin) public poolAdmin;
    mapping(uint256 => PoolDetail) public poolDetail;
    mapping(uint256 => IERC20) public poolToken;
    mapping(uint256 => PoolBalance) public poolBalance;
    mapping(uint256 => POOLSTATUS) public poolStatus;
    mapping(uint256 => address[]) public donors;

    /// @dev Creator specific mappings
    mapping(address => uint256[]) public createdProjects;
    mapping(address => mapping(uint256 poolId => bool)) public isCreator;

    /// @dev Donor specific mappings
    mapping(address => uint256[]) public donatedProjects;
    mapping(address => mapping(uint256 poolId => bool)) public isDonor;
    mapping(address => mapping(uint256 poolId => DonorDetail))
        public donorDetail;

    /// @dev Mapping for tracking collected platform fees by token
    mapping(address => uint256) public platformFeesCollected;

    /// @notice Modifier to check if caller is creator
    modifier onlyCreator(uint256 poolId) {
        if (msg.sender != poolAdmin[poolId].getCreator()) {
            revert DonationErrorsLib.OnlyCreator(
                msg.sender,
                poolAdmin[poolId].getCreator()
            );
        }
        _;
    }

    /// @notice Modifier to check if project is not disputed
    modifier notDisputed(uint256 poolId) {
        if (poolAdmin[poolId].isDisputed()) {
            revert DonationErrorsLib.ProjectDisputed(poolId);
        }
        _;
    }

    /// @notice Constructor sets up the initial state
    constructor() Ownable2Step(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        platformFeeRate = DEFAULT_PLATFORM_FEE;
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
    function donate(
        uint256 poolId,
        uint256 amount
    ) external whenNotPaused notDisputed(poolId) returns (bool) {
        if (amount == 0) {
            revert DonationErrorsLib.InvalidAmount(amount);
        }

        if (poolStatus[poolId] != POOLSTATUS.ACTIVE) {
            revert DonationErrorsLib.ProjectNotActive(poolId);
        }

        // Calculate platform fee
        uint256 feeAmount = (amount * platformFeeRate) / FEES_PRECISION;

        // Update pool balance
        poolBalance[poolId].addDonation(amount, feeAmount);

        // Update donor details
        if (!isDonor[msg.sender][poolId]) {
            donors[poolId].push(msg.sender);
            donatedProjects[msg.sender].push(poolId);
            isDonor[msg.sender][poolId] = true;
        }

        DonorDetailLib.addDonation(donorDetail, msg.sender, poolId, amount);

        // Transfer tokens from donor to contract
        poolToken[poolId].safeTransferFrom(msg.sender, address(this), amount);

        // Check if funding goal is reached
        if (
            poolBalance[poolId].getTotalDonations() >=
            poolDetail[poolId].getFundingGoal() &&
            poolStatus[poolId] == POOLSTATUS.ACTIVE
        ) {
            poolStatus[poolId] = POOLSTATUS.SUCCESSFUL;
            emit DonationEventsLib.ProjectStatusChanged(
                poolId,
                POOLSTATUS.SUCCESSFUL
            );
            emit DonationEventsLib.FundingGoalReached(
                poolId,
                poolBalance[poolId].getTotalDonations()
            );
        }

        emit DonationEventsLib.DonationReceived(poolId, msg.sender, amount);

        return true;
    }

    /**
     * @notice Claim refund for failed ALL_OR_NOTHING project
     * @param poolId The pool id
     */
    function claimRefund(uint256 poolId) external whenNotPaused {
        // Check project status and funding model
        if (poolStatus[poolId] != POOLSTATUS.FAILED) {
            // Project must be in FAILED state
            if (
                poolDetail[poolId].hasFundingModel(
                    FUNDINGMODEL.ALL_OR_NOTHING
                ) &&
                poolDetail[poolId].hasEnded() &&
                poolBalance[poolId].getTotalDonations() <
                poolDetail[poolId].getFundingGoal()
            ) {
                // Automatically mark as failed if conditions are met
                poolStatus[poolId] = POOLSTATUS.FAILED;
                emit DonationEventsLib.ProjectStatusChanged(
                    poolId,
                    POOLSTATUS.FAILED
                );
                emit DonationEventsLib.FundingFailed(
                    poolId,
                    poolBalance[poolId].getTotalDonations(),
                    poolDetail[poolId].getFundingGoal()
                );
            } else {
                revert DonationErrorsLib.NoRefundAvailable(poolId, msg.sender);
            }
        }

        // Ensure this is a refundable project
        if (!poolDetail[poolId].hasFundingModel(FUNDINGMODEL.ALL_OR_NOTHING)) {
            revert DonationErrorsLib.NoRefundAvailable(poolId, msg.sender);
        }

        // Check if user has donated and hasn't already refunded
        if (
            !DonorDetailLib.hasDonated(donorDetail, msg.sender, poolId) ||
            DonorDetailLib.hasRefunded(donorDetail, msg.sender, poolId)
        ) {
            revert DonationErrorsLib.NoRefundAvailable(poolId, msg.sender);
        }

        // Get the end time for this project
        uint40 endTime = poolDetail[poolId].getEndTime();

        // Check if refund grace period is still valid using safe comparison
        // If current time is past the refund deadline (end time + grace period), revert
        if (
            block.timestamp > endTime &&
            (block.timestamp - endTime) > REFUND_GRACE_PERIOD
        ) {
            revert DonationErrorsLib.RefundPeriodExpired(
                poolId,
                endTime + REFUND_GRACE_PERIOD
            );
        }

        // Get total amount donated by user
        uint256 totalDonated = donorDetail[msg.sender][poolId].totalDonated;
        uint256 refundClaimed = donorDetail[msg.sender][poolId].refundClaimed;

        // Calculate the actual refundable amount (accounting for fees)
        uint16 feeRate = poolAdmin[poolId].getPlatformFeeRate();
        uint256 feeAmount = (totalDonated * feeRate) / FEES_PRECISION;
        uint256 refundAmount = totalDonated - feeAmount - refundClaimed;

        if (refundAmount == 0) {
            revert DonationErrorsLib.NoRefundAvailable(poolId, msg.sender);
        }

        // Update state
        DonorDetailLib.markAsRefunded(
            donorDetail,
            msg.sender,
            poolId,
            refundAmount
        );
        poolBalance[poolId].deductFromBalance(refundAmount);

        // Send refund
        poolToken[poolId].safeTransfer(msg.sender, refundAmount);

        emit DonationEventsLib.RefundClaimed(poolId, msg.sender, refundAmount);
    }

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
    ) external whenNotPaused returns (uint256) {
        // Validation
        if (startTime >= endTime) {
            revert DonationErrorsLib.InvalidTimeframe(startTime, endTime);
        }

        if (
            endTime - startTime < MIN_FUNDING_PERIOD ||
            endTime - startTime > MAX_FUNDING_PERIOD
        ) {
            revert DonationErrorsLib.InvalidTimeframe(startTime, endTime);
        }

        if (fundingGoal < MIN_FUNDING_GOAL) {
            revert DonationErrorsLib.InvalidFundingGoal(fundingGoal);
        }

        if (!UtilsLib.isContract(token)) {
            revert DonationErrorsLib.InvalidToken(token);
        }

        // Increment pool id
        latestPoolId++;

        // Pool details
        poolDetail[latestPoolId].setStartTime(startTime);
        poolDetail[latestPoolId].setEndTime(endTime);
        poolDetail[latestPoolId].setProjectName(projectName);
        poolDetail[latestPoolId].setProjectDescription(projectDescription);
        poolDetail[latestPoolId].setProjectUrl(projectUrl);
        poolDetail[latestPoolId].setImageUrl(imageUrl);
        poolDetail[latestPoolId].fundingGoal = fundingGoal;
        poolDetail[latestPoolId].fundingModel = fundingModel;

        // Pool admin details
        poolAdmin[latestPoolId].setCreator(msg.sender);
        poolAdmin[latestPoolId].setPlatformFeeRate(platformFeeRate);
        isCreator[msg.sender][latestPoolId] = true;
        createdProjects[msg.sender].push(latestPoolId);

        // Pool token
        poolToken[latestPoolId] = IERC20(token);

        // Set pool status
        poolStatus[latestPoolId] = POOLSTATUS.ACTIVE;

        emit DonationEventsLib.ProjectCreated(
            latestPoolId,
            msg.sender,
            projectName,
            fundingGoal,
            token,
            fundingModel
        );

        emit DonationEventsLib.ProjectStatusChanged(
            latestPoolId,
            POOLSTATUS.ACTIVE
        );

        return latestPoolId;
    }

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
    ) external whenNotPaused onlyCreator(poolId) notDisputed(poolId) {
        if (poolStatus[poolId] != POOLSTATUS.ACTIVE) {
            revert DonationErrorsLib.ProjectNotActive(poolId);
        }

        poolDetail[poolId].setProjectName(projectName);
        poolDetail[poolId].setProjectDescription(projectDescription);
        poolDetail[poolId].setProjectUrl(projectUrl);
        poolDetail[poolId].setImageUrl(imageUrl);

        emit DonationEventsLib.ProjectDetailsUpdated(
            poolId,
            projectName,
            projectDescription,
            projectUrl,
            imageUrl
        );
    }

    /**
     * @notice Change the end time of a project
     * @param poolId The pool id
     * @param endTime New end time
     */
    function changeEndTime(
        uint256 poolId,
        uint40 endTime
    ) external whenNotPaused onlyCreator(poolId) notDisputed(poolId) {
        if (poolStatus[poolId] != POOLSTATUS.ACTIVE) {
            revert DonationErrorsLib.ProjectNotActive(poolId);
        }

        uint40 startTime = poolDetail[poolId].getStartTime();

        if (endTime <= block.timestamp) {
            revert DonationErrorsLib.InvalidTimeframe(startTime, endTime);
        }

        if (
            endTime - startTime < MIN_FUNDING_PERIOD ||
            endTime - startTime > MAX_FUNDING_PERIOD
        ) {
            revert DonationErrorsLib.InvalidTimeframe(startTime, endTime);
        }

        poolDetail[poolId].setEndTime(endTime);

        emit DonationEventsLib.ProjectEndTimeChanged(poolId, endTime);
    }

    /**
     * @notice Withdraw funds from a successful project or KEEP_WHAT_YOU_RAISE project after deadline
     * @param poolId The pool id
     */
    function withdrawFunds(
        uint256 poolId
    ) external whenNotPaused onlyCreator(poolId) notDisputed(poolId) {
        bool canWithdraw = false;

        // For successful projects (reached funding goal)
        if (poolStatus[poolId] == POOLSTATUS.SUCCESSFUL) {
            canWithdraw = true;
        }
        // For KEEP_WHAT_YOU_RAISE projects after deadline
        else if (
            poolDetail[poolId].hasFundingModel(
                FUNDINGMODEL.KEEP_WHAT_YOU_RAISE
            ) && poolDetail[poolId].hasEnded()
        ) {
            canWithdraw = true;
        }

        if (!canWithdraw) {
            if (!poolDetail[poolId].hasEnded()) {
                revert DonationErrorsLib.DeadlineNotReached(
                    poolId,
                    poolDetail[poolId].getEndTime()
                );
            } else if (
                poolDetail[poolId].hasFundingModel(
                    FUNDINGMODEL.ALL_OR_NOTHING
                ) &&
                poolBalance[poolId].getTotalDonations() <
                poolDetail[poolId].getFundingGoal()
            ) {
                revert DonationErrorsLib.FundingGoalNotReached(
                    poolId,
                    poolBalance[poolId].getTotalDonations(),
                    poolDetail[poolId].getFundingGoal()
                );
            }
        }

        uint256 amount = poolBalance[poolId].getBalance();
        if (amount == 0) {
            revert DonationErrorsLib.NoFundsToWithdraw(poolId);
        }

        // Update state
        poolBalance[poolId].deductFromBalance(amount);

        // Send funds to creator
        poolToken[poolId].safeTransfer(msg.sender, amount);

        emit DonationEventsLib.FundsWithdrawn(poolId, msg.sender, amount);
    }

    /**
     * @notice Cancel a project (only if no donations received)
     * @param poolId The pool id
     */
    function cancelProject(
        uint256 poolId
    ) external whenNotPaused onlyCreator(poolId) {
        if (poolStatus[poolId] != POOLSTATUS.ACTIVE) {
            revert DonationErrorsLib.ProjectNotActive(poolId);
        }

        if (poolBalance[poolId].getTotalDonations() > 0) {
            revert DonationErrorsLib.ProjectHasDonations(
                poolId,
                poolBalance[poolId].getTotalDonations()
            );
        }

        poolStatus[poolId] = POOLSTATUS.DELETED;

        emit DonationEventsLib.ProjectCancelled(poolId, msg.sender);
        emit DonationEventsLib.ProjectStatusChanged(poolId, POOLSTATUS.DELETED);
    }

    // ----------------------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Get project creator
     * @param poolId The pool id
     * @return creator The creator address
     */
    function getProjectCreator(uint256 poolId) external view returns (address) {
        return poolAdmin[poolId].getCreator();
    }

    /**
     * @notice Get project details
     * @param poolId The pool id
     * @return details The project details
     */
    function getProjectDetails(
        uint256 poolId
    ) external view returns (PoolDetail memory) {
        return poolDetail[poolId];
    }

    /**
     * @notice Get project balance
     * @param poolId The pool id
     * @return balance The current balance of the project
     */
    function getProjectBalance(uint256 poolId) external view returns (uint256) {
        return poolBalance[poolId].getBalance();
    }

    /**
     * @notice Get funding progress
     * @param poolId The pool id
     * @return progress The current funding progress (0-100%)
     */
    function getFundingProgress(
        uint256 poolId
    ) external view returns (uint256) {
        uint256 goal = poolDetail[poolId].getFundingGoal();
        if (goal == 0) return 0;

        return (poolBalance[poolId].getTotalDonations() * 100) / goal;
    }

    /**
     * @notice Get projects created by an address
     * @param creator The creator address
     * @return poolIds The project IDs created by this address
     */
    function getProjectsCreatedBy(
        address creator
    ) external view returns (uint256[] memory) {
        return createdProjects[creator];
    }

    /**
     * @notice Get projects donated to by an address
     * @param donor The donor address
     * @return poolIds The project IDs donated to by this address
     */
    function getProjectsDonatedToBy(
        address donor
    ) external view returns (uint256[] memory) {
        return donatedProjects[donor];
    }

    /**
     * @notice Get donation details for a donor
     * @param poolId The pool id
     * @param donor The donor address
     * @return details The donation details
     */
    function getDonationDetails(
        uint256 poolId,
        address donor
    ) external view returns (DonorDetail memory) {
        return donorDetail[donor][poolId];
    }

    /**
     * @notice Get all donors for a project
     * @param poolId The pool id
     * @return donors The list of donor addresses
     */
    function getProjectDonors(
        uint256 poolId
    ) external view returns (address[] memory) {
        return donors[poolId];
    }

    /**
     * @notice Check if a project is successful (reached its funding goal)
     * @param poolId The pool id
     * @return isSuccessful Whether the project reached its funding goal
     */
    function isProjectSuccessful(uint256 poolId) external view returns (bool) {
        return
            poolStatus[poolId] == POOLSTATUS.SUCCESSFUL ||
            (poolBalance[poolId].getTotalDonations() >=
                poolDetail[poolId].getFundingGoal());
    }

    /**
     * @notice Check if a project has failed (deadline reached without meeting goal)
     * @param poolId The pool id
     * @return hasFailed Whether the project has failed
     */
    function hasProjectFailed(uint256 poolId) external view returns (bool) {
        return
            poolStatus[poolId] == POOLSTATUS.FAILED ||
            (poolDetail[poolId].hasEnded() &&
                poolDetail[poolId].hasFundingModel(
                    FUNDINGMODEL.ALL_OR_NOTHING
                ) &&
                poolBalance[poolId].getTotalDonations() <
                poolDetail[poolId].getFundingGoal());
    }

    /**
     * @notice Get all details about a project
     * @param poolId The pool id
     * @return _poolAdmin The pool admin details
     * @return _poolDetail The pool details
     * @return _poolBalance The pool balance details
     * @return _poolStatus The pool status
     * @return _poolToken The pool token address
     * @return _donors The list of donors
     */
    function getAllProjectInfo(
        uint256 poolId
    )
        external
        view
        returns (
            IDonationPool.PoolAdmin memory _poolAdmin,
            IDonationPool.PoolDetail memory _poolDetail,
            IDonationPool.PoolBalance memory _poolBalance,
            IDonationPool.POOLSTATUS _poolStatus,
            address _poolToken,
            address[] memory _donors
        )
    {
        return (
            poolAdmin[poolId],
            poolDetail[poolId],
            poolBalance[poolId],
            poolStatus[poolId],
            address(poolToken[poolId]),
            donors[poolId]
        );
    }

    // ----------------------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Pause all contract operations (admin only)
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause contract operations (admin only)
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Flag a project as disputed (admin only)
     * @param poolId The pool id
     */
    function flagProjectAsDisputed(
        uint256 poolId
    ) external onlyRole(ADMIN_ROLE) {
        if (poolAdmin[poolId].isDisputed()) {
            return; // Already disputed
        }

        poolAdmin[poolId].setDisputed(true);

        emit DonationEventsLib.ProjectDisputed(poolId, msg.sender);
    }

    /**
     * @notice Resolve a disputed project (admin only)
     * @param poolId The pool id
     * @param resolveInFavorOfCreator Whether to resolve in favor of the creator
     */
    function resolveDispute(
        uint256 poolId,
        bool resolveInFavorOfCreator
    ) external onlyRole(ADMIN_ROLE) {
        if (!poolAdmin[poolId].isDisputed()) {
            return; // Not disputed
        }

        poolAdmin[poolId].setDisputed(false);

        if (!resolveInFavorOfCreator) {
            // If not resolved in favor of creator, set status to FAILED to allow refunds
            poolStatus[poolId] = POOLSTATUS.FAILED;
            emit DonationEventsLib.ProjectStatusChanged(
                poolId,
                POOLSTATUS.FAILED
            );
        }

        emit DonationEventsLib.DisputeResolved(poolId, resolveInFavorOfCreator);
    }

    /**
     * @notice Set platform fee rate (admin only)
     * @param newFeeRate The new platform fee rate (0.01% to 100%)
     */
    function setPlatformFeeRate(
        uint16 newFeeRate
    ) external onlyRole(ADMIN_ROLE) {
        if (newFeeRate > FEES_PRECISION) {
            revert DonationErrorsLib.InvalidFeeRate(newFeeRate);
        }

        uint16 oldRate = platformFeeRate;
        platformFeeRate = newFeeRate;

        emit DonationEventsLib.PlatformFeeRateChanged(oldRate, newFeeRate);
    }

    /**
     * @notice Collect platform fees (admin only)
     * @param token The token to collect fees for
     */
    function collectPlatformFees(IERC20 token) external onlyRole(ADMIN_ROLE) {
        uint256 feesToCollect = 0;

        // Collect fees from all pools using this token
        for (uint256 i = 1; i <= latestPoolId; i++) {
            if (address(poolToken[i]) == address(token)) {
                uint256 poolFeesToCollect = poolBalance[i].getFeesToCollect();
                if (poolFeesToCollect > 0) {
                    poolBalance[i].collectFees(poolFeesToCollect);
                    feesToCollect += poolFeesToCollect;
                }
            }
        }

        if (feesToCollect == 0) {
            return;
        }

        // Update tracking
        platformFeesCollected[address(token)] += feesToCollect;

        // Transfer fees to admin
        token.safeTransfer(msg.sender, feesToCollect);

        emit DonationEventsLib.PlatformFeeCollected(
            address(token),
            feesToCollect
        );
    }

    /**
     * @notice Emergency withdraw in case of critical issues (admin only, when paused)
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function emergencyWithdraw(
        IERC20 token,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) whenPaused {
        token.safeTransfer(msg.sender, amount);

        emit DonationEventsLib.EmergencyWithdraw(address(token), amount);
    }

    // ----------------------------------------------------------------------------
    // Access Control Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Add an admin (owner only)
     * @param account The account to grant admin role
     */
    function addAdmin(address account) external onlyOwner {
        _grantRole(ADMIN_ROLE, account);
    }

    /**
     * @notice Remove an admin (owner only)
     * @param account The account to revoke admin role
     */
    function removeAdmin(address account) external onlyOwner {
        _revokeRole(ADMIN_ROLE, account);
    }
}
