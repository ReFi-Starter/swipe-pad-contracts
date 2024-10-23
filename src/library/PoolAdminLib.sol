// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "../interface/IPool.sol";

library PoolAdminLib {
    function setHost(IPool.PoolAdmin storage self, address host) internal {
        self.host = host;
    }

    function getHost(IPool.PoolAdmin storage self) internal view returns (address) {
        return self.host;
    }
}
