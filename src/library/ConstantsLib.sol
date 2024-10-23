// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev 2 decimals precision in percentage for fees.
/// @dev 0.01% to 100%.
/// @dev 1 to 10000.
uint16 constant FEES_PRECISION = 10000;

/// @dev Timelock for admin to forfeit winnings.
uint40 constant FORFEIT_WINNINGS_TIMELOCK = 5 days;

bytes32 constant WHITELISTED_HOST = 0xd4b8aa22b7d8e3cd5d1a213163a89192d1a63c6abcb930b02aa1c2d6efc32625; // keccak256("WHITELISTED_HOST");
bytes32 constant WHITELISTED_SPONSOR = 0x2627ca8cd6e046054c92b9f4142ed371232f275c03fa515989dd56fa92f98e40; // keccak256("WHITELISTED_SPONSOR");
bytes32 constant FEES_MANAGER = 0xad51469fd38cb9e4028f769761e769052a9f1f331b57ad921ac8a45c7903db28; // keccak256("FEES_MANAGER");