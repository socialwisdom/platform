// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CTFAdapter} from "./CTFAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// TODO: override necessary functions.
contract ConditionalTokens is Ownable, CTFAdapter {
    constructor(address _impl) Ownable(msg.sender) CTFAdapter(_impl) {}
}
