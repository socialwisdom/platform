// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

contract GnosisERC1155 {
    mapping(uint256 => mapping(address => uint256)) internal _balances;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;
}

contract GnosisCTF is GnosisERC1155 {
    mapping(bytes32 => uint256[]) internal _payoutNumerators;
    mapping(bytes32 => uint256) internal _payoutDenominator;
}

contract GnosisCTFProxy is IConditionalTokens, GnosisCTF {
    address public immutable implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    /* @dev: IERC165 functions */

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return IERC165(implementation).supportsInterface(interfaceId);
    }

    /* @dev: IERC1155 functions */

    function balanceOf(address owner, uint256 id) public view returns (uint256) {
        require(owner != address(0), "ERC1155: balance query for the zero address");
        return _balances[id][owner];
    }

    function balanceOfBatch(address[] memory owners, uint256[] memory ids) public view returns (uint256[] memory) {
        require(owners.length == ids.length, "ERC1155: owners and IDs must have same lengths");

        uint256[] memory batchBalances = new uint256[](owners.length);

        for (uint256 i = 0; i < owners.length; ++i) {
            require(owners[i] != address(0), "ERC1155: some address in batch balance query is zero");
            batchBalances[i] = _balances[ids[i]][owners[i]];
        }

        return batchBalances;
    }

    function setApprovalForAll(address, bool) external {
        _delegate();
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function safeTransferFrom(address, address, uint256, uint256, bytes calldata) external {
        _delegate();
    }

    function safeBatchTransferFrom(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external {
        _delegate();
    }

    /* @dev: ConditionalTokensFramework functions */

    function payoutNumerators(bytes32 conditionId, uint256 index) external view returns (uint256) {
        return _payoutNumerators[conditionId][index];
    }

    function payoutDenominator(bytes32 conditionId) external view returns (uint256) {
        return _payoutDenominator[conditionId];
    }

    function prepareCondition(address, bytes32, uint256) external virtual {
        _delegate();
    }

    function reportPayouts(bytes32, uint256[] calldata) external virtual {
        _delegate();
    }

    function splitPosition(IERC20, bytes32, bytes32, uint256[] calldata, uint256) external {
        _delegate();
    }

    function mergePositions(IERC20, bytes32, bytes32, uint256[] calldata, uint256) external virtual {
        _delegate();
    }

    function redeemPositions(IERC20, bytes32, bytes32, uint256[] calldata) external {
        _delegate();
    }

    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256) {
        return _payoutNumerators[conditionId].length;
    }

    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        external
        view
        returns (bytes32)
    {
        return IConditionalTokens(implementation).getCollectionId(parentCollectionId, conditionId, indexSet);
    }

    function getPositionId(IERC20 collateralToken, bytes32 collectionId) external pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }

    /* @dev: Proxy functions */

    function _delegate() internal {
        address impl = implementation;

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0x00, 0x00, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), impl, 0x00, calldatasize(), 0x00, 0x00)

            // Copy the returned data.
            returndatacopy(0x00, 0x00, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0x00, returndatasize())
            }
            default {
                return(0x00, returndatasize())
            }
        }
    }
}

contract ConditionalTokens is Ownable, GnosisCTFProxy {
    constructor(address _impl) Ownable(msg.sender) GnosisCTFProxy(_impl) {}

    // @dev: Patched with onlyOwner access control to restrict condition preparation.
    function prepareCondition(address, bytes32, uint256) external override onlyOwner {
        _delegate();
    }

    // @dev: Patched to include a winner fee.
    function reportPayouts(bytes32, uint256[] calldata) external override {
        // FIXME: implement fee logic here
        _delegate();
    }

    // @dev: Patched to forbid merging positions after payouts have been reported.
    function mergePositions(IERC20, bytes32, bytes32 conditionId, uint256[] calldata, uint256) external override {
        require(_payoutDenominator[conditionId] == 0, "Cannot merge positions after payouts are reported");
        _delegate();
    }
}
