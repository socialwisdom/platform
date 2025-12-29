// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GnosisCTFProxy} from "./GnosisProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// TODO: override necessary functions.
contract ConditionalTokens is Ownable, GnosisCTFProxy {
    constructor(address _impl) Ownable(msg.sender) GnosisCTFProxy(_impl) {}
}
