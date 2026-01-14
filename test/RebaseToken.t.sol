//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public OWNER = makeAddr("OWNER");
    address public USER = makeAddr("USER");

    function setUp() public {
        vm.startPrank(OWNER);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 _rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: _rewardAmount}("");
    }

    function testDepositLinear(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.startPrank(USER);
        vm.deal(USER, _amount);
        vault.deposit{value: _amount}();

        // Check initial balance
        uint256 initialBalance = rebaseToken.balanceOf(USER);
        console2.log("Initial balance:", initialBalance);
        assertEq(initialBalance, _amount);

        // Fast forward time by 1 year
        vm.warp(block.timestamp + 365 days);
        uint256 balanceAfterOneYear = rebaseToken.balanceOf(USER);
        console2.log("Balance after one year:", balanceAfterOneYear);
        assert(balanceAfterOneYear > initialBalance);

        // Fast forward time by 1 year
        vm.warp(block.timestamp + 365 days);
        uint256 balanceAfterTwoYears = rebaseToken.balanceOf(USER);
        console2.log("Balance after two years:", balanceAfterTwoYears);
        assert(balanceAfterTwoYears > balanceAfterOneYear);

        assertApproxEqAbs(balanceAfterOneYear - initialBalance, balanceAfterTwoYears - balanceAfterOneYear, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.startPrank(USER);
        vm.deal(USER, _amount);

        // Deposit into the vault
        vault.deposit{value: _amount}();

        // Check balance before redeeming
        uint256 balanceBeforeRedeem = rebaseToken.balanceOf(USER);
        console2.log("Balance before redeem:", balanceBeforeRedeem);
        assertEq(balanceBeforeRedeem, _amount);

        // Redeem immediately
        vault.redeem(type(uint256).max);

        // Check balance after redeeming
        uint256 balanceAfterRedeem = rebaseToken.balanceOf(USER);
        console2.log("Balance after redeem:", balanceAfterRedeem);
        assertEq(balanceAfterRedeem, 0);
        assertEq(address(USER).balance, _amount);

        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 _depositAmount, uint256 _timePassed) public {
        _depositAmount = bound(_depositAmount, 1e5, type(uint96).max);
        _timePassed = bound(_timePassed, 1000, type(uint96).max);

        vm.deal(USER, _depositAmount);
        vm.prank(USER);
        // Deposit into the vault
        vault.deposit{value: _depositAmount}();

        // Fast forward time by _timePassed seconds
        vm.warp(block.timestamp + _timePassed);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(USER);
        console2.log("Balance before redeem:", balanceAfterSomeTime);

        //Add the rewards to the vault
        vm.deal(OWNER, balanceAfterSomeTime - _depositAmount);
        vm.prank(OWNER);
        addRewardsToVault(balanceAfterSomeTime - _depositAmount);

        // Redeem all tokens
        vm.prank(USER);
        vault.redeem(type(uint256).max);

        // Check balance after redeeming
        uint256 balanceAfterRedeem = rebaseToken.balanceOf(USER);
        console2.log("Balance after redeem:", balanceAfterRedeem);
        assertEq(balanceAfterRedeem, 0);

        vm.stopPrank();
    }

    function testTransfer(uint256 _amount, uint256 _amountToSend) public {
        _amount = bound(_amount, 1e5 + 1e5, type(uint96).max);
        _amountToSend = bound(_amountToSend, 1e5, _amount - 1e5);

        //deposit
        vm.deal(USER, _amount);
        vm.prank(USER);
        vault.deposit{value: _amount}();

        // Make another user
        address RECEIVER = makeAddr("RECEIVER");
        uint256 userBalance = rebaseToken.balanceOf(USER);
        uint256 receiverBalance = rebaseToken.balanceOf(RECEIVER);

        // Check initial balance
        assertEq(userBalance, _amount);
        assertEq(receiverBalance, 0);

        // Reduce interest rate
        vm.prank(OWNER);
        rebaseToken.setInterestRate(4e10);

        // Transfer some tokens to USER2
        vm.prank(USER);
        rebaseToken.transfer(RECEIVER, _amountToSend);
        uint256 userBalanceAfter = rebaseToken.balanceOf(USER);
        uint256 receiverBalanceAfter = rebaseToken.balanceOf(RECEIVER);
        assertEq(receiverBalanceAfter - receiverBalance, _amountToSend);
        assertEq(userBalance - userBalanceAfter, _amountToSend);

        // Check user interest rates
        uint256 userInterestRate = rebaseToken.getUserInterestRate(USER);
        uint256 receiverInterestRate = rebaseToken.getUserInterestRate(RECEIVER);
        assertEq(userInterestRate, 5e10);
        assertEq(receiverInterestRate, 5e10);
    }

    function testCannotSetInterestRateIfNotOwner(uint256 _newInterestRate) public {
        vm.prank(USER);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(_newInterestRate);
    }

    function testCannotCallMintAndBurnIfNotVault() public {
        vm.startPrank(USER);
        uint256 interestRate = rebaseToken.getInterestRate();
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(USER, 1000, interestRate);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(USER, 1000);
        vm.stopPrank();
    }

    function testGetPrincipleAmount(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);

        // Deposit into the vault
        vm.startPrank(USER);
        vm.deal(USER, _amount);
        vault.deposit{value: _amount}();

        // Check principle amount
        uint256 principleAmount = rebaseToken.getPrincipleBalanceOf(USER);
        console2.log("Principle amount:", principleAmount);
        assertEq(principleAmount, _amount);

        // Check again after some time
        vm.warp(block.timestamp + 100 days);
        uint256 principleAmountAfterTime = rebaseToken.getPrincipleBalanceOf(USER);
        console2.log("Principle amount after time:", principleAmountAfterTime);
        assertEq(principleAmountAfterTime, _amount);

        vm.stopPrank();
    }

    function testGetRebaseTokenAddress() public view {
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        assertEq(rebaseTokenAddress, address(rebaseToken));
    }

    function testCannotIncreaseInterestRate(uint256 _newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.s_interestRate();
        _newInterestRate = bound(_newInterestRate, initialInterestRate + 1, type(uint96).max);
        vm.prank(OWNER);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(_newInterestRate);
    }
}
