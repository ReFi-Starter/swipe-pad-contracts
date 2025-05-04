// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDonationPool} from "../interface/IDonationPool.sol";

library DonationPoolDetailLib {
    function getStartTime(
        IDonationPool.PoolDetail storage detail
    ) internal view returns (uint40) {
        return detail.startTime;
    }

    function getEndTime(
        IDonationPool.PoolDetail storage detail
    ) internal view returns (uint40) {
        return detail.endTime;
    }

    function getFundingGoal(
        IDonationPool.PoolDetail storage detail
    ) internal view returns (uint256) {
        return detail.fundingGoal;
    }

    function getFundingModel(
        IDonationPool.PoolDetail storage detail
    ) internal view returns (IDonationPool.FUNDINGMODEL) {
        return detail.fundingModel;
    }

    function getProjectName(
        IDonationPool.PoolDetail storage detail
    ) internal view returns (string memory) {
        return detail.projectName;
    }

    function setStartTime(
        IDonationPool.PoolDetail storage detail,
        uint40 startTime
    ) internal {
        detail.startTime = startTime;
    }

    function setEndTime(
        IDonationPool.PoolDetail storage detail,
        uint40 endTime
    ) internal {
        detail.endTime = endTime;
    }

    function setProjectName(
        IDonationPool.PoolDetail storage detail,
        string memory projectName
    ) internal {
        detail.projectName = projectName;
    }

    function setProjectDescription(
        IDonationPool.PoolDetail storage detail,
        string memory projectDescription
    ) internal {
        detail.projectDescription = projectDescription;
    }

    function setProjectUrl(
        IDonationPool.PoolDetail storage detail,
        string memory projectUrl
    ) internal {
        detail.projectUrl = projectUrl;
    }

    function setImageUrl(
        IDonationPool.PoolDetail storage detail,
        string memory imageUrl
    ) internal {
        detail.imageUrl = imageUrl;
    }

    function isActive(
        IDonationPool.PoolDetail storage detail
    ) internal view returns (bool) {
        return
            block.timestamp >= detail.startTime &&
            block.timestamp < detail.endTime;
    }

    function hasEnded(
        IDonationPool.PoolDetail storage detail
    ) internal view returns (bool) {
        return block.timestamp >= detail.endTime;
    }

    function hasFundingModel(
        IDonationPool.PoolDetail storage detail,
        IDonationPool.FUNDINGMODEL model
    ) internal view returns (bool) {
        return detail.fundingModel == model;
    }
}
