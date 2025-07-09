// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "src/eth/MinimalAccount.sol";
import {DeployMinimal} from "script/DeployMinimal.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MinimalAccountTest is Test {
    HelperConfig public helperConfig;
    MinimalAccount public minimalAccount;
    ERC20Mock usdc;
    uint256 constant AMOUNT = 1e18;
    address public randomUser = makeAddr("randomUser");

    function setUp() public {
        DeployMinimal deployMinimal = new DeployMinimal();
        (helperConfig, minimalAccount) = deployMinimal.deployMinimalAccount();
        usdc = new ERC20Mock();
    }

    function testOwnerCanExecute() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory funcData = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(minimalAccount),
            AMOUNT
        );
        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, funcData);
        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testNonOwnerCannotExecute() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory funcData = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(minimalAccount),
            AMOUNT
        );
        // Act
        vm.prank(randomUser);
        vm.expectRevert(
            MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector
        );
        minimalAccount.execute(dest, value, funcData);
        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
    }
}
