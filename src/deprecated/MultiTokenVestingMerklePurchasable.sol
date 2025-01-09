// contracts/vesting/TokenVestingMerklePurchasable.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.23;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { MultiTokenVesting } from "./MultiTokenVesting.sol";
import { TokenVestingMerklePurchasable } from "../TokenVestingMerklePurchasable.sol";
import { MerkleProofLib } from "@solady/utils/MerkleProofLib.sol";

/// @title MultiTokenVestingMerklePurchasable - Extension of TokenVestingMerklePurchasable contract to
/// using merkle tree for vesting schedule creation across several contracts
/// @author ElliottAnastassios (MTX Studio) - elliott@mtx.studio
/// @author Schmackofant - schmackofant@protonmail.com

contract MultiTokenVestingMerklePurchasable is MultiTokenVesting {
    /// @dev The Merkle Root
    bytes32 private merkleRoot;

    /// @dev Mapping for already used merkle leaves
    mapping(bytes32 => bool) private claimed;

    event MerkleRootUpdated(bytes32 indexed merkleRoot);
    event VTokenCostSet(uint256 vTokenCost);
    event PaymentReceiverSet(address paymentReceiver);

    /**
     * @notice cost amount for purchasing vesting schedule and claim tokens in wei
     */
    uint256 public vTokenCost;

    /**
     * @notice address of the payment receiver for vesting and claim purchases
     */
    address payable public paymentReceiver;

    /**
     * @notice Creates a vesting contract.
     * @param _token address of the ERC20 base token contract
     * @param _name name of the virtual token
     * @param _symbol symbol of the virtual token
     * @param _root merkle root
     * @param _paymentReceiver address of the payment receiver
     * @param _vTokenCost cost of the virtual token
     */
    constructor(
        IERC20Metadata _token,
        string memory _name,
        string memory _symbol,
        address payable _paymentReceiver,
        address _vestingCreator,
        uint256 _vTokenCost,
        bytes32 _root,
        address _externalVestingContract
    ) MultiTokenVesting(_token, _name, _symbol, _vestingCreator, _externalVestingContract) {
        merkleRoot = _root;
        vTokenCost = _vTokenCost;
        paymentReceiver = _paymentReceiver;
    }

    error InvalidProof();
    error AlreadyClaimed();
    error PayableInsufficient();
    error TransferToPaymentReceiverFailed();

    /**
     * @notice Claims a vesting schedule from a merkle tree
     * @param _proof merkle proof
     * @param _start start time of the vesting period
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revokable whether the vesting is revokable or not
     * @param _amount total amount of tokens to be released at the end of the vesting
     */
    function claimSchedule(
        bytes32[] calldata _proof,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revokable,
        uint256 _amount
    ) public payable whenNotPaused nonReentrant {
        // check if vesting schedule has been already claimed
        bytes32 leaf =
            keccak256(bytes.concat(keccak256(abi.encode(_msgSender(), _start, _cliff, _duration, _slicePeriodSeconds, _revokable, _amount))));
        if (!MerkleProofLib.verify(_proof, merkleRoot, leaf)) revert InvalidProof();
        if (scheduleClaimed(_msgSender(), _start, _cliff, _duration, _slicePeriodSeconds, _revokable, _amount)) revert AlreadyClaimed();

        // check if the msg.value is equal to the vTokenCost * _amount
        if (msg.value != vTokenCost * _amount / 1e18) revert PayableInsufficient();
        (bool success,) = paymentReceiver.call{ value: msg.value }("");
        if (!success) revert TransferToPaymentReceiverFailed();

        claimed[leaf] = true;
        _createVestingSchedule(_msgSender(), _start, _cliff, _duration, _slicePeriodSeconds, _revokable, _amount);
    }

    /**
     * @notice Returns whether a vesting schedule has been already claimed or not
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _start start time of the vesting period
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revokable whether the vesting is revokable or not
     * @param _amount total amount of tokens to be released at the end of the vesting
     * @return true if the vesting schedule has been claimed, false otherwise
     */
    function scheduleClaimed(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revokable,
        uint256 _amount
    ) public view returns (bool) {
        bytes32 leaf =
            keccak256(bytes.concat(keccak256(abi.encode(_beneficiary, _start, _cliff, _duration, _slicePeriodSeconds, _revokable, _amount))));
        if (claimed[leaf]) return true;

        for (uint256 i = 0; i < externalVestingContracts.length; i++) {
            if (
                TokenVestingMerklePurchasable(externalVestingContracts[i]).scheduleClaimed(
                    _beneficiary, _start, _cliff, _duration, _slicePeriodSeconds, _revokable, _amount
                )
            ) return true;
        }
        return false;
    }

    /// SETTERS ///

    /**
     * @notice Sets the cost of purchasing vTokens and therefore the vesting schedule
     * @param _vTokenCost cost of purchasing  vTokens
     * @dev _tokenCost should be between 0.01 ETH (1e16 Wei) and 0
     */
    function setVTokenCost(uint256 _vTokenCost) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_vTokenCost > 1e16) revert InvalidAmount();
        vTokenCost = _vTokenCost;
        emit VTokenCostSet(_vTokenCost);
    }

    /**
     * @notice Sets the payment receiver for the nominal purchase amount of the vesting and claim purchases
     * @param _receiver address of the payment receiver
     */
    function setPaymentReceiver(address payable _receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_receiver == address(0)) revert InvalidAddress();
        paymentReceiver = _receiver;
        emit PaymentReceiverSet(_receiver);
    }

    /**
     * @notice Updates the merkle root
     * @param _root new merkle root
     */
    function setMerkleRoot(bytes32 _root) public onlyRole(DEFAULT_ADMIN_ROLE) {
        merkleRoot = _root;
        emit MerkleRootUpdated(_root);
    }
}
