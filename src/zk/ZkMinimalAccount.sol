// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// Zk era imports
import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {Transaction, MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS, DEPLOYER_SYSTEM_CONTRACT} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";

// OZ imports
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
    @title ZkMinimalAccount
    @author @0xError
    @notice This is a minimal account contract for zksync.
    @dev There are 2 phases we're going to perform on a lifecycle of an account abstraction transaction (AA AKA type 113 (0x71))
    @dev When sending a transaction of type 113, the msg.sender is the bootloader system contract. (think of it as super admin or equivalent to entryPoint contract on ETH).
    1. Phase 1: Validation => happens on the light nodes of zkSync
        - The user sends the transaction to the "zkSync API client" (sort of a light node).
        - The zkSync API client checks to see that the nonce is unique by querying the NonceHolder system contract. 
            - This system has the nonce of every single account on the zksync chain.
        - The zkSync API client calls validateTrasaction, which MUST update the nonce.
        - The zkSync API client checks the nonce is updated.
        - The zkSync API client calls payForTransaction, or prepareForPaymaster & validateAndPayForPaymasterTransaction.
        - The zkSync API client verifiees that the bootloader gets paid. (Similar to how entryPoint on ethereum gets paid)
    2. Phase 2: Execution => happens on the main nodes / sequencer of zkSync
        - executeTransaction is called by the main node.
        - If a paymaster is used, the postTransaction is called.
 */

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    // =============================== Errors ===============================
    error ZkMinimalAccount__InsufficientBalance();
    error ZkMinimalAccount__NotBootloader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__NotBootloaderOrOwner();
    error ZkMinimalAccount__FailedToPayBootloader();

    // =============================== Modifiers ===============================
    modifier onlyBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotBootloader();
        }
        _;
    }

    modifier onlyBootloaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotBootloaderOrOwner();
        }
        _;
    }

    // =============================== Constructor ===============================
    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    // =============================== External Functions ===============================
    /**
     * @notice This function is very similar to the validateUserOp function in the account-abstraction library
     * @notice but zksync is saying validateTransaction because it is built in on zksync ecosystem.
     * @notice must increase the nonce
     * @notice must validate the transaction (check the owner signed the transaction)
     * @notice also check to see if we have enough money in our contract (because we are not using a paymaster)
     */
    function validateTransaction(
        bytes32 /*_txHash*/,
        bytes32 /*_suggestedSignedHash*/,
        Transaction memory _transaction
    ) external payable onlyBootloader returns (bytes4 magic) {
        return _validateTransaction(_transaction);
    }

    /**
     * @notice Admin calling => This function is very similar to the executeTransaction function in the account-abstraction library
     * @notice but zksync is saying executeTransaction because it is built in on zksync ecosystem.
     */
    function executeTransaction(
        bytes32 /*_txHash*/,
        bytes32 /*_suggestedSignedHash*/,
        Transaction memory _transaction
    ) external payable onlyBootloaderOrOwner {
        _executeTransaction(_transaction);
    }

    /**
     * @notice This is a function where an example of it's usage is you sign a tx and send it to your friend,
     * @notice a friend of yours can send the signed tx by calling this function
     */
    function executeTransactionFromOutside(
        Transaction memory _transaction
    ) external payable {
        _validateTransaction(_transaction);
        _executeTransaction(_transaction);
    }

    /**
     * @notice payprefun equivalent of minimal account
     */
    function payForTransaction(
        bytes32 /*_txHash*/,
        bytes32 /*_suggestedSignedHash*/,
        Transaction memory _transaction
    ) external payable {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZkMinimalAccount__FailedToPayBootloader();
        }
    }

    /**
     * @notice a function you call before payForTransaction function if and only if you have a paymaster
     */
    function prepareForPaymaster(
        bytes32 _txHash,
        bytes32 _possibleSignedHash,
        Transaction memory _transaction
    ) external payable {}

    // =============================== Internal Functions ===============================
    /**
     * @notice This function is very similar to the validateUserOp function in the account-abstraction library
     * @notice but zksync is saying validateTransaction because it is built in on zksync ecosystem.
     * @notice must increase the nonce
     * @notice must validate the transaction (check the owner signed the transaction)
     * @notice also check to see if we have enough money in our contract (because we are not using a paymaster)
     */
    function _validateTransaction(
        Transaction memory _transaction
    ) internal returns (bytes4 magic) {
        // call the nonceHolder system contract to update the nonce
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(
                INonceHolder.incrementMinNonceIfEquals,
                (_transaction.nonce)
            )
        );

        // check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__InsufficientBalance();
        }

        // check the signature
        bytes32 txHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }

        return magic;
    }

    /**
     * @notice Admin calling => This function is very similar to the executeTransaction function in the account-abstraction library
     * @notice but zksync is saying executeTransaction because it is built in on zksync ecosystem.
     */
    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        // we MIGHT wanna send this to a system contract and system contract receives a uint128 value
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        // if the transaction is supposed to deploy a contract, we can't just send the transaction, we need to call the deployer system contract instead
        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(
                gas,
                to,
                value,
                data
            );
        } else {
            bool success;
            // call, staticCall and delegateCalls work differently in zksync so we need to use assembly to call the function
            assembly {
                success := call(
                    gas(),
                    to,
                    value,
                    add(data, 0x20),
                    mload(data),
                    0,
                    0
                )
            }
            if (!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }
}
