// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IConditionalTokens} from "../../src/interfaces/IConditionalTokens.sol";
import {GnosisCTFAdapter} from "../../src/external/GnosisCTFAdapter.sol";
import {VmSafe} from "forge-std/Vm.sol";

library DeployCTFAdapter {
    VmSafe private constant VM = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));
    string private constant CTF_BYTECODE_PATH = "artifact/CTF-bytecode.json";

    function deploy() internal returns (IConditionalTokens) {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = VM.readFile(CTF_BYTECODE_PATH);
        bytes memory bytecode = VM.parseJsonBytes(json, ".bytecode");

        address implementation;

        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) { revert(0, 0) }
        }

        GnosisCTFAdapter adapter = new GnosisCTFAdapter(implementation);

        return IConditionalTokens(address(adapter));
    }
}
