// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    function run() public {}

    function generateSignedUserOp(
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address minimalAccount
    ) public returns (PackedUserOperation memory) {
        uint256 nonce = vm.getNonce(minimalAccount) - 1;
        // 1. Generate the unsigned data
        // flow is gonna be like this;
        // 1. User signs UserOp
        // 2. Bundler collets UserOp
        // 3. Bundler calls Entrypoint.handleOps
        // 4. Entrypoint calls MinimalAccount.validateUserOp
        // 5. MinimalAccount validates signature
        // 6. Entrypoint calls MinimalAccount.execute
        // 7. MinimalAccount executes the actual transaction
        // Account Abstraction way:
        // Alice signs a PackedUserOperation
        // sender field = Alice's MinimalAccount contract (0xAliceWallet...)
        // EntryPoint calls Alice's MinimalAccount
        // MinimalAccount sends USDC to Bob
        // msg.sender in the USDC contract = 0xAliceWallet...

        PackedUserOperation memory userOp = _generateUnsignedUserOp(
            callData,
            minimalAccount,
            nonce
        );

        // 2. Get the userOpHash
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(
            userOp
        );
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // 3. Sign it
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        if (block.chainid == 31337) {
            (v, r, s) = vm.sign(ANVIL_DEFAULT_KEY, digest);
        } else {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(config.account, digest);
        }
        userOp.signature = abi.encodePacked(r, s, v);
        return userOp;
    }

    function _generateUnsignedUserOp(
        bytes memory callData,
        address sender,
        uint256 nonce
    ) internal pure returns (PackedUserOperation memory) {
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;
        return
            PackedUserOperation({
                sender: sender,
                nonce: nonce,
                initCode: hex"",
                callData: callData,
                accountGasLimits: bytes32(
                    (uint256(verificationGasLimit) << 128) | callGasLimit
                ),
                preVerificationGas: verificationGasLimit,
                gasFees: bytes32(
                    (uint256(maxPriorityFeePerGas) << 128) | maxFeePerGas
                ),
                paymasterAndData: hex"",
                signature: hex""
            });
    }
}
