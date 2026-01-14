//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    error Vault__RedeemFailed();
    // Vault contract code goes here
    IRebaseToken private immutable i_rebaseToken;

    event Vault__Deposit(address indexed user, uint256 amount);
    event Vault__Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
        // Initialize the vault with the RebaseToken address
    }

    receive() external payable {
        // Accept ETH deposits
    }

    /**
     * @notice Deposits ETH into the vault and mints RebaseTokens to the user
     * @dev The amount of RebaseTokens minted is equal to the amount of ETH deposited
     */
    function deposit() external payable {
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Vault__Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeems RebaseTokens for ETH from the vault
     * @param _amount The amount of RebaseTokens to redeem
     * @dev Burns the RebaseTokens from the user and sends the equivalent amount of ETH
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Vault__Redeem(msg.sender, _amount);
    }

    /**
     * @notice Gets the address of the RebaseToken contract
     * @return The address of the RebaseToken contract
     */

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
