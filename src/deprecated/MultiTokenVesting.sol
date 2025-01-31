// contracts/TokenVesting.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TokenVesting} from "../TokenVesting.sol";

/// @title MultiTokenVesting - Wrapper extention of TokenVesting contract to allow the querying of vesting token balance from multiple vesting contracts

contract MultiTokenVesting is TokenVesting {
    /**
     * @notice An array of external vesting contracts
     */
    address[] public externalVestingContracts;

    /// EVENTS ///
    event ExternalVestingContractAdded(address indexed externalVestingContracts);
    event ExternalVestingContractRemoved(address indexed externalVestingContracts);

    /// ERRORS ///
    error ContractAlreadyAdded();
    error ContractNotFound();

    /// CONSTRUCTOR ///

    /**
     * @notice Creates a vesting contract.
     * @param _underlyingToken address of the ERC20 base token contract
     * @param _name name of the virtual token
     * @param _symbol symbol of the virtual token
     * @param _vestingCreator address of the vesting creator
     * @param _externalVestingContract address of the external vesting contract
     */
    constructor(
        IERC20Metadata _underlyingToken,
        string memory _name,
        string memory _symbol,
        address _vestingCreator,
        address _externalVestingContract
    ) TokenVesting(_underlyingToken, _name, _symbol, _vestingCreator) {
        externalVestingContracts.push(_externalVestingContract);
    }

    /// FUNCTIONS ///

    /**
     * @notice Returns the amount of virtual tokens in existence
     */
    function totalSupply() public view override returns (uint256) {
        uint256 total = vestingSchedulesTotalAmount;
        for (uint256 i = 0; i < externalVestingContracts.length; i++) {
            total += TokenVesting(externalVestingContracts[i]).totalSupply();
        }
        return total;
    }

    /**
     * @notice Returns the sum of virtual tokens for a user
     * @param user The user for whom the balance is calculated
     * @return Balance of the user
     */
    function balanceOf(address user) public view override returns (uint256) {
        uint256 balance = holdersVestedAmount[user];
        for (uint256 i = 0; i < externalVestingContracts.length; i++) {
            balance += TokenVesting(externalVestingContracts[i]).balanceOf(user);
        }
        return balance;
    }

    /// Setter ///

    /**
     * @dev Function to add an external vesting contract address
     * @param _externalVestingContract of the external vesting contract
     */
    function addExternalVestingContract(address _externalVestingContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < externalVestingContracts.length; i++) {
            if (externalVestingContracts[i] == _externalVestingContract) {
                revert ContractAlreadyAdded();
            }
        }
        externalVestingContracts.push(_externalVestingContract);
        emit ExternalVestingContractAdded(_externalVestingContract);
    }

    /**
     * @dev Function to remove an external vesting contract address
     * @param _externalVestingContract of the external vesting contract
     */
    function removeExternalVestingContract(address _externalVestingContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < externalVestingContracts.length; i++) {
            if (externalVestingContracts[i] == _externalVestingContract) {
                // Remove the contract from the array by moving the last element to the deleted spot
                externalVestingContracts[i] = externalVestingContracts[externalVestingContracts.length - 1];
                // Remove the last element
                externalVestingContracts.pop();
                emit ExternalVestingContractRemoved(_externalVestingContract);
                return;
            }
        }
        revert ContractNotFound();
    }
}
