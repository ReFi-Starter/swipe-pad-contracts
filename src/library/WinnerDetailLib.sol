// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "../interface/IPool.sol";
import {EventsLib} from "./EventsLib.sol";

library WinnerDetailLib {
	function setAmountWon(
		IPool.WinnerDetail storage self,
		uint256 amount
	) internal {
		self.amountWon = amount;
	}

	function getAmountWon(
		IPool.WinnerDetail storage self
	) internal view returns (uint256) {
		return self.amountWon;
	}

	function hasClaimed(
		IPool.WinnerDetail storage self
	) internal view returns (bool) {
		return self.claimed;
	}
}