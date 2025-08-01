// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccount is IAccount, Ownable {
    /*////////////////////////////////////////////////////
                            ERRORS
    ////////////////////////////////////////////////////*/
    error MinimalAccount_NotFromEntryPoint();
    error MinimalAccount__NotFromEntryPointOrOwner();
    error MinimalAccount__CallFailed(bytes);
    /*////////////////////////////////////////////////////
                            STATE VARIABLES
    ////////////////////////////////////////////////////*/
    address private immutable i_entryPoint;

    /*////////////////////////////////////////////////////
                            MODIFIERS
    ////////////////////////////////////////////////////*/
    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint))
            revert MinimalAccount_NotFromEntryPoint();
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != address(i_entryPoint) && msg.sender != owner())
            revert MinimalAccount__NotFromEntryPointOrOwner();
        _;
    }

    /*////////////////////////////////////////////////////
                            FUNCTIONS
    ////////////////////////////////////////////////////*/
    constructor(address entryPoint) Ownable(msg.sender) {
        i_entryPoint = entryPoint;
    }

    receive() external payable {}

    /*////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////*/
    function execute(
        address dest,
        uint256 value,
        bytes calldata funcData
    ) external requireFromEntryPointOrOwner {
        (bool success, bytes memory result) = dest.call{value: value}(funcData);
        if (!success) {
            revert MinimalAccount__CallFailed(result);
        }
    }

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external requireFromEntryPoint returns (uint256 validationData) {
        _validateSignature(userOp, userOpHash);
        // _validateNonce() // ideally we would check the nonce here
        // payback money to the entrypoint => so basically missingAccountFunds is the amount of money that we need to pay back to whoever making this transaction
        // if you have a paymaster, you can add on to this to have the paymaster pay for this
        _payPrefund(missingAccountFunds);
    }

    /*////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////*/
    // EIP-191 version of the signed signature => we need to format this hash to a normal hash
    // This is gonna tell us who actually signed the message and who was the one to hash the all userOp data
    // All we're doing here is we're saying given the signature and the hash they gave us, let's verify the signature is the owner of the contract
    // This is where we get to say, make sure google verification is ok, or at least 3 friends signed something and all that cool stuff
    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view returns (uint256 validationData) {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            userOpHash
        );
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
        if (signer != owner()) return SIG_VALIDATION_FAILED;
        return SIG_VALIDATION_SUCCESS;
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds > 0) {
            (bool success, ) = payable(msg.sender).call{
                value: missingAccountFunds,
                gas: type(uint256).max
            }("");
            (success);
        }
    }

    /*////////////////////////////////////////////////////
                            GETTERS
    ////////////////////////////////////////////////////*/
    function getEntryPoint() external view returns (address) {
        return i_entryPoint;
    }
}
