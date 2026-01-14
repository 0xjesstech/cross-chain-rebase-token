//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author 0xJessTech
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate based on the global interest rate at the time of their deposit
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 public s_interestRate = (5 * PRECISION_FACTOR) / 1e8;

    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event RebaseToken__InterestRateUpdated(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Sets a new interest rate for the rebase token
     * @dev The interest rate can only decrease
     * @param _newInterestRate The new interest rate to be set
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (s_interestRate < _newInterestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit RebaseToken__InterestRateUpdated(_newInterestRate);
    }

    /**
     * @notice Mints new tokens to a user
     * @param _to The address of the user to mint tokens to
     * @param _amount The amount of tokens to mint
     * @dev Before minting, it mints any accrued interest for the user
     * @dev It then updates the user's interest rate to the current global interest rate
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Gets the balance of an account including accrued interest
     * @param _user The address of the account
     * @return The balance of the account including accrued interest
     */

    function balanceOf(address _user) public view override returns (uint256) {
        // Get current principle balance
        uint256 principleBalance = super.balanceOf(_user);
        // Multiply principle balance by user interest rate and time since last updated
        return principleBalance * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Calculates the user's accumulated interest since their last update
     * @param _user The address of the user
     * @return The user's accumulated interest since their last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256) {
        // get time since last updated
        uint256 timeSinceLastUpdated = block.timestamp - s_userLastUpdatedTimestamp[_user];
        uint256 userInterestRate = s_userInterestRates[_user];
        // calculate interest accrued since last updated
        uint256 interestAccrued = userInterestRate * timeSinceLastUpdated;
        // 0.01 * 5 mins = 0.05
        // 10 * )
        // return 1 + interest accrued
        uint256 linearInterest = PRECISION_FACTOR + interestAccrued;
        return linearInterest;
    }

    /**
     * @notice Mints any accrued interest to the user
     * @param _user The address of the user
     */
    function _mintAccruedInterest(address _user) internal {
        // get users current balance of RBT (principle balance)
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // get users current balance including any interest -> recorded in balanceOf
        uint256 currentBalanceWithInterest = balanceOf(_user);
        // calc number of tokens that need to be minted to the user
        uint256 interestToMint = currentBalanceWithInterest - previousPrincipleBalance;
        // set the users last updated timestamp to now
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint the interest tokens to the user
        if (interestToMint > 0) {
            _mint(_user, interestToMint); //there is an event emitted within this function
        }
    }

    /**
     * @notice Burns tokens from a user
     * @param _from The address of the user to burn tokens from
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Transfers tokens from the caller to a recipient
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return A boolean value indicating whether the operation succeeded
     * @dev Before transferring, it mints any accrued interest for both the sender and recipient
     * @dev If the recipient has a zero balance, it sets their interest rate to the sender's interest rate
     */

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfers tokens from a sender to a recipient
     * @param _sender The address of the sender
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return A boolean value indicating whether the operation succeeded
     * @dev Before transferring, it mints any accrued interest for both the sender and recipient
     * @dev If the recipient has a zero balance, it sets their interest rate to the sender's interest rate
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Gets the user's interest rate
     * @param _user The address of the user
     * @return The user's interest rate
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Gets the principle balance of a user (this is the number of tokens minted to the user, so doesnt include any interest earnt since they user last made an action)
     * @param _user The address of the user
     * @return The principle balance of the user
     */
    function getPrincipleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }
}
