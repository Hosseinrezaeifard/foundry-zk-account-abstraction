// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IAccount} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {Transaction} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";

contract ZkMinimalAccount is IAccount {
    // @notice This function is very similar to the validateUserOp function in the account-abstraction library
    // but zksync is saying validateTransaction because it is built in on zksync ecosystem.
    function validateTransaction(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction memory _transaction
    ) external payable returns (bytes4 magic) {}

    // @notice Admin calling => This function is very similar to the executeTransaction function in the account-abstraction library
    // but zksync is saying executeTransaction because it is built in on zksync ecosystem.
    function executeTransaction(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction memory _transaction
    ) external payable {}

    // @notice This is a function where an example of it's usage is you sign a tx and send it to your friend,
    // a friend of yours can send the signed tx by calling this function
    function executeTransactionFromOutside(
        Transaction memory _transaction
    ) external payable {}

    // @notice payprefun equivalent of minimal account
    function payForTransaction(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction memory _transaction
    ) external payable {}

    // @notice a function you call before payForTransaction function if and only if you have a paymaster
    function prepareForPaymaster(
        bytes32 _txHash,
        bytes32 _possibleSignedHash,
        Transaction memory _transaction
    ) external payable {}
}
