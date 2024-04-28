// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// Interfaces
import {IPool} from "./interface/IPool.sol";
import {IERC20} from "./interface/IERC20.sol";
/// Libraries
import "./library/ConstantsLib.sol";
import {EventsLib} from "./library/EventsLib.sol";
import {ErrorsLib} from "./library/ErrorsLib.sol";
import {PoolAdminLib} from "./library/PoolAdminLib.sol";
import {PoolDetailLib} from "./library/PoolDetailLib.sol";
import {PoolBalanceLib} from "./library/PoolBalanceLib.sol";
import {ParticipantDetailLib} from "./library/ParticipantDetailLib.sol";
import {WinnerDetailLib} from "./library/WinnerDetailLib.sol";
import {UtilsLib} from "./library/UtilsLib.sol";
import {SafeTransferLib} from "./library/SafeTransferLib.sol";

/// Dependencies
import {Owned} from "solmate/auth/Owned.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract Pool is IPool, Owned, Pausable {
    using UtilsLib for address;
    using SafeTransferLib for IERC20;
    using PoolAdminLib for IPool.PoolAdmin;
    using PoolDetailLib for IPool.PoolDetail;
    using PoolBalanceLib for IPool.PoolBalance;
    using ParticipantDetailLib for IPool.ParticipantDetail;
    using WinnerDetailLib for IPool.WinnerDetail;

    uint256 public latestPoolId; // Start from 1, 0 is invalid

    /// @dev Pool specific mappings
    mapping(uint256 => PoolAdmin) public poolAdmin;
    mapping(uint256 => PoolDetail) public poolDetail;
    mapping(uint256 => IERC20) public poolToken;
    mapping(uint256 => PoolBalance) public poolBalance;
    mapping(uint256 => POOLSTATUS) public poolStatus;
    mapping(uint256 => address[]) public participants;
    mapping(uint256 => address[]) public winners;

    /// @dev Pool admin specific mappings
    mapping(address => uint256[]) public createdPools;
    mapping(address => mapping(uint256 => bool)) public isHost;

    /// @dev User specific mappings
    mapping(address => uint256[]) public joinedPools;
    mapping(address => mapping(uint256 => bool)) public isParticipant;
    mapping(address => mapping(uint256 => ParticipantDetail)) public participantDetail;
    mapping(address => mapping(uint256 => WinnerDetail)) public winnerDetail;

    /// @notice Modifier to check if user is host
    modifier onlyHost(uint256 poolId) {
        if (!isHost[msg.sender][poolId]) {
            revert ErrorsLib.Unauthorized(msg.sender);
        }
        _;
    }

    constructor() Owned(msg.sender) {}

    // ----------------------------------------------------------------------------
    // Participant Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Deposit tokens into a pool
     * @param poolId The pool id
     * @param amount The amount to deposit
     * @dev Pool status must be DEPOSIT_ENABLED
     * @dev Pool must not have started
     * @dev User must not be a participant
     * @dev Amount must be equal to depositAmountPerPerson
     * @dev Emits Deposit event
     */
    function deposit(uint256 poolId, uint256 amount) external whenNotPaused returns (bool) {
        require(poolStatus[poolId] == POOLSTATUS.DEPOSIT_ENABLED, "Deposit not enabled");
        require(block.timestamp <= poolDetail[poolId].getTimeStart(), "Pool started");
        require(isParticipant[msg.sender][poolId] == false, "Already in pool");
        uint256 amountPerPerson = poolDetail[poolId].getDepositAmountPerPerson();
        require(amount >= amountPerPerson, "Incorrect amount");

        // Transfer tokens from user to pool
        poolToken[poolId].safeTransferFrom(msg.sender, address(this), amount);

        // Excess as extra donation
        if (amount > amountPerPerson) {
            poolBalance[poolId].extraBalance += amount - amountPerPerson;
        }
        // Update pool details
        poolBalance[poolId].totalDeposits += amount;
        poolBalance[poolId].balance += amount;
        participantDetail[msg.sender][poolId].setParticipantIndex(participants[poolId].length);
        participants[poolId].push(msg.sender);

        // Update participant details
        participantDetail[msg.sender][poolId].setJoinedPoolsIndex(joinedPools[msg.sender].length);
        joinedPools[msg.sender].push(poolId);
        isParticipant[msg.sender][poolId] = true;
        participantDetail[msg.sender][poolId].deposit = amountPerPerson;
        if (participantDetail[msg.sender][poolId].hasRefunded()) {
            participantDetail[msg.sender][poolId].refunded = false; // Edge case for rejoin
        }

        emit EventsLib.Deposit(poolId, msg.sender, amount);
        return true;
    }

    /**
     * @notice Claim winning from a pool
     * @param poolId The pool id
     * @dev Pool status must be ENDED
     * @dev User must be a winner
     * @dev User must not have claimed
     * @dev Emits WinningClaimed event
     */
    function claimWinning(uint256 poolId, address winner) public whenNotPaused {
        require(poolStatus[poolId] == POOLSTATUS.ENDED, "Pool not ended");
        require(!winnerDetail[winner][poolId].hasClaimed(), "Already claimed");

        uint256 amount = winnerDetail[winner][poolId].getAmountWon();
        winnerDetail[winner][poolId].claimed = true;

        poolToken[poolId].safeTransfer(winner, amount);

        emit EventsLib.WinningClaimed(poolId, winner, amount);
    }

    /// @notice Claim winnings from multiple pools
    function claimWinnings(uint256[] calldata poolIds, address[] calldata _winners) external whenNotPaused {
        require(poolIds.length == poolIds.length, "Invalid input");
        for (uint256 i = 0; i < poolIds.length; i++) {
            claimWinning(poolIds[i], _winners[i]);
        }
    }

    /**
     * @notice Self refund from a pool
     * @param poolId The pool id
     * @dev Pool status must not be ENDED
     * @dev User must be a participant
     * @dev User must not have been refunded
     * @dev Emits Refund event
     */
    function selfRefund(uint256 poolId) external whenNotPaused {
        require(poolStatus[poolId] != POOLSTATUS.ENDED, "Pool already ended");
        require(isParticipant[msg.sender][poolId], "Not a participant");
        require(participantDetail[msg.sender][poolId].hasRefunded() == false, "Already refunded");

        // Apply fees if pool is not deleted
        if (poolStatus[poolId] != POOLSTATUS.DELETED) {
            _applyFees(poolId);
        }
        _refund(poolId, msg.sender);
    }

    // ----------------------------------------------------------------------------
    // Host Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Create a new pool
     * @param timeStart The start time of the pool
     * @param timeEnd The end time of the pool
     * @param poolName The name of the pool
     * @param depositAmountPerPerson The amount to deposit per person
     * @param penaltyFeeRate The penalty fee rate
     * @param token The token to use for the pool
     * @dev Pool status will be INACTIVE
     * @dev Emits PoolCreated event
     */
    function createPool(
        uint40 timeStart,
        uint40 timeEnd,
        string calldata poolName,
        uint256 depositAmountPerPerson, // Can be 0 in case of sponsored pool
        uint16 penaltyFeeRate, // 10000 = 100%
        address token
    ) external whenNotPaused returns (uint256) {
        require(timeStart < timeEnd, "Invalid timing");
        require(penaltyFeeRate <= FEES_PRECISION, "Invalid fees rate");
        require(token.isContract(), "Token not contract");

        // Increment pool id
        latestPoolId++;

        // Pool details
        poolDetail[latestPoolId].setTimeStart(timeStart);
        poolDetail[latestPoolId].setTimeEnd(timeEnd);
        poolDetail[latestPoolId].setPoolName(poolName);
        poolDetail[latestPoolId].setDepositAmountPerPerson(depositAmountPerPerson);

        // Pool admin details
        poolAdmin[latestPoolId].setPenaltyFeeRate(penaltyFeeRate);
        poolAdmin[latestPoolId].setHost(msg.sender);
        isHost[msg.sender][latestPoolId] = true;
        createdPools[msg.sender].push(latestPoolId);

        // Pool token
        poolToken[latestPoolId] = IERC20(token);

        emit EventsLib.PoolCreated(latestPoolId, msg.sender, poolName);
        return latestPoolId;
    }

    /**
     * @notice Enable deposit for a pool
     * @param poolId The pool id
     * @dev Only the host can enable deposit
     * @dev Pool status must be INACTIVE
     * @dev Pool status will be changed to DEPOSIT_ENABLED
     * @dev Emits PoolStatusChanged event
     */
    function enableDeposit(uint256 poolId) external onlyHost(poolId) whenNotPaused {
        require(poolStatus[poolId] == POOLSTATUS.INACTIVE, "Pool already active");

        poolStatus[poolId] = POOLSTATUS.DEPOSIT_ENABLED;
        emit EventsLib.PoolStatusChanged(poolId, POOLSTATUS.DEPOSIT_ENABLED);
    }

    /**
     * @notice Start a pool
     * @param poolId The pool id
     * @dev Only the host can start the pool
     * @dev Pool status must be DEPOSIT_ENABLED
     * @dev Pool status will be changed to STARTED
     * @dev Emits PoolStatusChanged event
     */
    function startPool(uint256 poolId) external onlyHost(poolId) whenNotPaused {
        require(poolStatus[poolId] == POOLSTATUS.DEPOSIT_ENABLED, "Deposit not enabled yet");

        poolStatus[poolId] = POOLSTATUS.STARTED;
        poolDetail[poolId].setTimeStart(uint40(block.timestamp)); // update actual start time
        emit EventsLib.PoolStatusChanged(poolId, POOLSTATUS.STARTED);
    }

    /**
     * @notice End a pool
     * @param poolId The pool id
     * @dev Only the host can end the pool
     * @dev Pool status must be STARTED
     * @dev Pool status will be changed to ENDED
     * @dev Emits PoolStatusChanged event
     */
    function endPool(uint256 poolId) external onlyHost(poolId) whenNotPaused {
        require(poolStatus[poolId] == POOLSTATUS.STARTED, "Pool not started");

        poolStatus[poolId] = POOLSTATUS.ENDED;
        poolDetail[poolId].setTimeEnd(uint40(block.timestamp)); // update actual end time
        emit EventsLib.PoolStatusChanged(poolId, POOLSTATUS.ENDED);
    }

    /**
     * @notice Delete a pool
     * @param poolId The pool id
     * @dev Only the host can delete the pool
     * @dev Pool status will be changed to DELETED
     * @dev Emits PoolStatusChanged event
     */
    function deletePool(uint256 poolId) external onlyHost(poolId) whenNotPaused {
        poolStatus[poolId] = POOLSTATUS.DELETED;

        emit EventsLib.PoolStatusChanged(poolId, POOLSTATUS.DELETED);
    }

    /**
     * @notice Set winner of pool
     * @param poolId The pool id
     * @param winner The winner address
     * @param amount The amount to set as winner
     * @dev Only the host can set the winner
     * @dev Winner must be a participant
     * @dev Amount must be greater than or equal to pool balance
     * @dev Emits WinnerSet event
     */
    function setWinner(uint256 poolId, address winner, uint256 amount) public onlyHost(poolId) whenNotPaused {
        require(isParticipant[winner][poolId], "Not a participant");
        require(amount <= poolBalance[poolId].getBalance(), "Not enough balance");

        // Update pool balance
        poolBalance[poolId].balance -= amount;

        // Update winner details
        winnerDetail[winner][poolId].setAmountWon(amount);
        winners[poolId].push(winner);

        emit EventsLib.WinnerSet(poolId, winner, amount);
    }

    /// @notice Set multiple winners of pool
    function setWinners(uint256 poolId, address[] calldata _winners, uint256[] calldata amounts) external onlyHost(poolId) whenNotPaused {
        require(_winners.length == amounts.length, "Invalid input");

        for (uint256 i = 0; i < _winners.length; i++) {
            setWinner(poolId, _winners[i], amounts[i]);
        }
    }

    /**
     * @notice Refund a participant
     * @param poolId The pool id
     * @param participant The participant address
     * @dev Only the host can refund a participant
     * @dev Pool status must be STARTED
     * @dev Participant must be a participant
     * @dev Participant must not be refunded
     * @dev Pool balance must be greater than 0
     * @dev Emits Refund event
     */
    function refundParticipant(uint256 poolId, address participant) external onlyHost(poolId) whenNotPaused {
        require(isParticipant[participant][poolId], "Not a participant");
        require(participantDetail[participant][poolId].hasRefunded() == false, "Already refunded");
        require(poolBalance[poolId].getBalance() > 0, "No balance");

        _refund(poolId, participant);
    }

    /**
     * @notice Collect fees
     * @param poolId The pool id
     * @dev Only send to host
     * @dev Emits FeesCollected event
     */
    function collectFees(uint256 poolId) external whenNotPaused {
        // Transfer fees to host
        uint256 fees = poolBalance[poolId].getFeesAccumulated() - poolBalance[poolId].getFeesCollected();
        poolBalance[poolId].balance -= fees;
        poolBalance[poolId].feesCollected += fees;

        address host = poolAdmin[poolId].getHost();
        poolToken[poolId].safeTransfer(host, fees);

        emit EventsLib.FeesCollected(poolId, host, fees);
    }

    /**
     * @notice Collect remaining balance if any
     * @param poolId The pool id
     * @dev Only send to host
     * @dev Emits RemainingBalanceCollected event
     */
    function collectRemainingBalance(uint256 poolId) external onlyHost(poolId) whenNotPaused {
        require(poolStatus[poolId] == POOLSTATUS.ENDED, "Pool not ended");
        uint256 amount = poolBalance[poolId].getBalance();
        require(amount > 0, "Nothing to withdraw");

        poolBalance[poolId].balance = 0;
        address host = poolAdmin[poolId].getHost();
        poolToken[poolId].safeTransfer(host, amount);

        emit EventsLib.RemainingBalanceCollected(poolId, host, amount);
    }

    // ----------------------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Get host of a pool
     * @param poolId The pool id
    */
    function getHost(uint256 poolId) external view returns (address) {
        return poolAdmin[poolId].getHost();
    }

    /**
     * @notice Get pool balance
     * @param poolId The pool id
     * @return balance The balance of the pool
     */
    function getPoolBalance(uint256 poolId) external view returns (uint256) {
        return poolBalance[poolId].getBalance();
    }

    /** 
     * @notice Get created pools by a host
     * @param host The host address
     * @return poolIds The pool ids created by the host
     */
    function getPoolsCreatedBy(address host) external view returns (uint256[] memory) {
        return createdPools[host];
    }

    /**
     * @notice Get joined pools by a participant
     * @param participant The participant address
     * @return poolIds The pool ids joined by the participant
     */
    function getPoolsJoinedBy(address participant) external view returns (uint256[] memory) {
        return joinedPools[participant];
    }

    /**
     * @notice Get participants list of a pool
     * @param poolId The pool id
     * @return participants The list of participants
     */
    function getParticipants(uint256 poolId) external view returns (address[] memory) {
        return participants[poolId];
    }

    /**
     * @notice Get deposit amount of a participant
     * @param participant The participant address
     * @param poolId The pool id
     * @return deposit The deposit amount of the participant
     */
    function getParticipantDeposit(address participant, uint256 poolId) public view returns (uint256) {
        return ParticipantDetailLib.getDeposit(participantDetail, participant, poolId);
    }

    /**
     * @notice Check if a participant is a winner
     * @param poolId The pool id
     * @return isWinner True if participant is a winner
     */
    function isWinner(uint256 poolId, address winner) external view returns (bool) {
        return winnerDetail[winner][poolId].getAmountWon() > 0;
    }

    /**
     * @notice Get winning amount of a winner
     * @param poolId The pool id
     * @return amountWon The amount won by the winner
     */
    function getWinningAmount(uint256 poolId, address winner) external view returns (uint256) {
        return winnerDetail[winner][poolId].getAmountWon();
    }

    /**
     * @notice Get winners of a pool
     * @param poolId The pool id
     * @return winners The list of winners
     */
    function getWinners(uint256 poolId) external view returns (address[] memory) {
        return winners[poolId];
    }

    /**
     * @notice Get fees rate of late refund
     * @param poolId The pool id
     * @return penaltyFeeRate The penalty fee rate
     */
    function getPoolFeeRate(uint256 poolId) public view returns (uint16) {
        return poolAdmin[poolId].getPenaltyFeeRate();
    }

    /**
     * @notice Get fees accumulated
     * @param poolId The pool id
     * @return feesAccumulated The fees accumulated
     */
    function getFeesAccumulated(uint256 poolId) external view returns (uint256) {
        return poolBalance[poolId].getFeesAccumulated();
    }

    /**
     * @notice Get fees collected
     * @param poolId The pool id
     * @return feesAccumulated The fees collected
     */
    function getFeesCollected(uint256 poolId) external view returns (uint256) {
        return poolBalance[poolId].getFeesCollected();
    }

    /**
     * @notice Get extra balance if any sponsors / donations received
     * @param poolId The pool id
     * @return extraBalance The extra balance
     */
    function getExtraBalance(uint256 poolId) external view returns (uint256) {
        return poolBalance[poolId].getExtraBalance();
    }

    // ----------------------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------------------

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(IERC20 token, uint256 amount) external onlyOwner whenPaused {
        token.safeTransfer(msg.sender, amount);
    }

    // ----------------------------------------------------------------------------
    // Internal Functions
    // ----------------------------------------------------------------------------

    /**
     * @dev refund a participant
     * @param poolId The pool id
     * @param participant The participant address
     */
    function _refund(uint256 poolId, address participant) internal {
        uint256 amount = ParticipantDetailLib.getDeposit(participantDetail, participant, poolId)
            - ParticipantDetailLib.getFeesCharged(participantDetail, participant, poolId);

        // Update participant details
        participantDetail[participant][poolId].refunded = true;
        participantDetail[participant][poolId].deposit = 0;

        // Update pool balance
        poolBalance[poolId].balance -= amount;
        poolBalance[poolId].totalDeposits -= amount;

        // Delete participant from pool
        ParticipantDetailLib.removeParticipantFromPool(
            participantDetail, participants, isParticipant, participant, poolId
        );

        // Delete pool from participant
        ParticipantDetailLib.removeFromJoinedPool(participantDetail, joinedPools, participant, poolId);

        poolToken[poolId].safeTransfer(participant, amount);

        emit EventsLib.Refund(poolId, participant, amount);
    }

    /**
     * @notice Apply fees to a participant
     * @param poolId The pool id
     */
    function _applyFees(uint256 poolId) internal {
        // Charge fees if event is < 24 hours to start or started
		uint40 timeStart = poolDetail[poolId].getTimeStart();
        if (
            block.timestamp >= timeStart - 1 days
                && block.timestamp <= timeStart
        ) {
            uint256 fees = (getPoolFeeRate(poolId) * getParticipantDeposit(msg.sender, poolId)) / FEES_PRECISION;
            participantDetail[msg.sender][poolId].feesCharged += fees;
            poolBalance[poolId].feesAccumulated += fees;

            emit EventsLib.FeesCharged(poolId, msg.sender, fees, false);
        } else if (block.timestamp > timeStart) {
            uint256 fees = getParticipantDeposit(msg.sender, poolId);
            participantDetail[msg.sender][poolId].feesCharged += fees;
            poolBalance[poolId].feesAccumulated += fees;

            emit EventsLib.FeesCharged(poolId, msg.sender, fees, true);
        }
    }
}
