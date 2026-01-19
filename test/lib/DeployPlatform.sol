// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Platform} from "../../src/Platform.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

library DeployPlatform {
    function deploy(address owner) internal returns (Platform) {
        Platform impl = new Platform();
        bytes memory data = abi.encodeCall(Platform.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        return Platform(address(proxy));
    }
}
