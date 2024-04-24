// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "../interface/IPool.sol";

library AdminLib {
	function setPenaltyFeeRate(IPool.PoolAdmin storage self, uint16 penaltyFeeRate) internal {
		self.penaltyFeeRate = penaltyFeeRate;
	}

	function getPenaltyFeeRate(IPool.PoolAdmin storage self) internal view returns (uint16) {
		return self.penaltyFeeRate;
	}

	function setHost(IPool.PoolAdmin storage self, address host) internal {
		self.host = host;
	}

	function getHost(IPool.PoolAdmin storage self) internal view returns (address) {
		return self.host;
	}

	function addCohost(
		mapping(uint256 => IPool.PoolAdmin) storage poolAdmin, 
		mapping(address => mapping(uint256 => uint256)) storage cohostIndex, 
		mapping(address => mapping(uint256 => bool)) storage isCohost,
		address cohost,
		uint256 poolId
		) internal {
		cohostIndex[cohost][poolId] = poolAdmin[poolId].cohosts.length;
		poolAdmin[poolId].cohosts.push(cohost);
		isCohost[cohost][poolId] = true;
	}

	function getCohosts(IPool.PoolAdmin storage self) internal view returns (address[] memory) {
		return self.cohosts;
	}

	function getCohost(
		IPool.PoolAdmin storage self,
		uint256 index
		) internal view returns (address) {
		return self.cohosts[index];
	}

	function removeCohost(
		mapping(uint256 => IPool.PoolAdmin) storage poolAdmin, 
		mapping(address => mapping(uint256 => uint256)) storage cohostIndex, 
		mapping(address => mapping(uint256 => bool)) storage isCohost,
		address cohost,
		uint256 poolId
		) internal {
		IPool.PoolAdmin memory pool = poolAdmin[poolId];
		uint256 i = cohostIndex[cohost][poolId];
		assert(cohost == pool.cohosts[i]);
		
		if (i < pool.cohosts.length - 1) {
			// Move last to replace current index
			address lastCohost = pool.cohosts[pool.cohosts.length - 1];
			poolAdmin[poolId].cohosts[i] = lastCohost;
			cohostIndex[lastCohost][poolId] = i;
		}
		poolAdmin[poolId].cohosts.pop();
		isCohost[cohost][poolId] = false;
	}
}