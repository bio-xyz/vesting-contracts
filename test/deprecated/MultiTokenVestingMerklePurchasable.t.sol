// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Token} from "../TestToken.sol";
import {MultiTokenVestingMerklePurchasable} from "../../src/deprecated/MultiTokenVestingMerklePurchasable.sol";
import {TokenVestingMerklePurchasable} from "../../src/TokenVestingMerklePurchasable.sol";
import {MultiTokenVesting} from "../../src/deprecated/MultiTokenVesting.sol";
import {TokenVesting} from "../../src/TokenVesting.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract TokenVestingV2MerklePurchasableTest is Test {
    Token internal token;
    Token internal wrongToken;
    TokenVestingMerklePurchasable internal tokenVesting;
    MultiTokenVestingMerklePurchasable internal tokenVesting2;
    TokenVestingMerklePurchasable internal tokenVesting3;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address deployer = makeAddr("bighead");
    address vestingCreator = makeAddr("vestingCreator");

    address jane = makeAddr("jane");
    address john = makeAddr("john");

    uint256 constant tokenSupply = 1000000 ether;
    address payable paymentReceiver = payable(makeAddr("paymentReceiver"));
    uint256 constant vTokenCost = 1e8;
    uint256 constant claimableAmount = 20000 ether;
    uint256 purchasePrice = (vTokenCost * claimableAmount) / 1e18;

    bytes32[] aliceProof = new bytes32[](1);
    bytes32[] johnProof = new bytes32[](3);
    // merkleRoot of alice, bob, bighead
    bytes32 merkleRoot1 = 0xd3c242c647a293473133758815a38c34eaa471e529e85a9698d0954fea73de70;
    // merkleRoot of alice, bob, bighead, jane, john
    bytes32 merkleRoot2 = 0xdec85dd4681b9730081b74e7337159b996eae28b57448cec7cea8ec343f0d836;

    uint256 baseTime = 1622551248;
    uint256 cliff = 0;
    uint256 duration = 2630000;

    function setUp() public {
        emit log_address(alice);
        emit log_address(bob);
        emit log_address(deployer);
        emit log_address(jane);
        emit log_address(john);

        // Merkle Proof for alice
        aliceProof[0] = 0x94c5970130b08f3c5cb2b0c7d9a7040406a1b07a0fc164353f8ec0a58fb37199;

        // Merkle Proof for john after merkle tree update
        johnProof[0] = 0x016b280ba09a8a79cab7dd419cfc9c6c9f400281c831296f49921e466850b8d2;
        johnProof[1] = 0xeea2a014c525f58b4e9fce3e86bc73c6d6342780ec646d3ee57409062f8cf398;
        johnProof[2] = 0x0073bf0065a74349563adba072d420e370b60d49708a62141b166e5c493f223c;

        vm.startPrank(deployer);
        token = new Token("Test Token", "TT", 18, tokenSupply);

        // Initiate TokenVestingMerkle with the merkle root from the example MerkleTree `samples/merkleTree.json`
        tokenVesting = new TokenVestingMerklePurchasable(
            IERC20Metadata(token), "Virtual Test Token", "vTT", paymentReceiver, vestingCreator, vTokenCost, merkleRoot1
        );

        tokenVesting2 = new MultiTokenVestingMerklePurchasable(
            IERC20Metadata(token),
            "Virtual Test Token2",
            "vTT",
            paymentReceiver,
            vestingCreator,
            vTokenCost,
            merkleRoot1,
            address(tokenVesting)
        );

        tokenVesting3 = new TokenVestingMerklePurchasable(
            IERC20Metadata(token),
            "Virtual Test Token2",
            "vTT",
            paymentReceiver,
            vestingCreator,
            vTokenCost,
            merkleRoot1
        );

        token.transfer(address(tokenVesting), tokenSupply / 2);
        token.transfer(address(tokenVesting2), tokenSupply / 2);

        vm.stopPrank();

        vm.deal(alice, 1 ether);
        vm.deal(john, 1 ether);
    }

    // Merkle Testing

    function testCanClaimSchedule() public {
        vm.warp(1622551240);

        assertEq(tokenVesting.balanceOf(alice), 0);

        vm.startPrank(alice);
        tokenVesting.claimSchedule{value: purchasePrice}(
            aliceProof, baseTime, cliff, duration, 1, true, claimableAmount
        );
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), claimableAmount);
        assertEq(tokenVesting.scheduleClaimed(alice, baseTime, cliff, duration, 1, true, claimableAmount), true);

        //check if the paymentReceiver received the payment
        assertEq(paymentReceiver.balance, purchasePrice);
    }

    function testCanOnlyClaimOnce() public {
        vm.warp(1622551240);

        vm.startPrank(alice);
        tokenVesting.claimSchedule{value: purchasePrice}(
            aliceProof, baseTime, cliff, duration, 1, true, claimableAmount
        );
        vm.expectRevert(MultiTokenVestingMerklePurchasable.AlreadyClaimed.selector);
        tokenVesting.claimSchedule{value: purchasePrice}(
            aliceProof, baseTime, cliff, duration, 1, true, claimableAmount
        );
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), claimableAmount);
    }

    function testProofMustBeValid() public {
        vm.warp(1622551240);
        vm.startPrank(alice);

        // Pass wrong number of tokens
        vm.expectRevert(MultiTokenVestingMerklePurchasable.InvalidProof.selector);
        tokenVesting.claimSchedule{value: purchasePrice}(aliceProof, baseTime, cliff, duration, 1, true, 30000 ether);

        // Pass invalid proof
        aliceProof[0] = 0xca6d546259ec0929fd20fbc9a057c980806abef37935fb5ca5f6a179718f1481;

        vm.expectRevert(MultiTokenVestingMerklePurchasable.InvalidProof.selector);
        tokenVesting.claimSchedule{value: purchasePrice}(
            aliceProof, baseTime, cliff, duration, 1, true, claimableAmount
        );
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 0);
    }

    function testCannotClaimWithoutTokens() public {
        vm.warp(1622551240);

        vm.startPrank(deployer);
        tokenVesting.withdraw(500000 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(address(tokenVesting)), 0);

        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.InsufficientTokensInContract.selector);
        tokenVesting.claimSchedule{value: purchasePrice}(
            aliceProof, baseTime, cliff, duration, 1, true, claimableAmount
        );
        vm.stopPrank();

        assertEq(tokenVesting.scheduleClaimed(alice, baseTime, cliff, duration, 1, true, claimableAmount), false);
    }

    function testCanUpdateMerkleTree() public {
        vm.warp(1622551240);

        assertEq(tokenVesting.balanceOf(alice), 0);

        vm.startPrank(alice);
        tokenVesting.claimSchedule{value: purchasePrice}(
            aliceProof, baseTime, cliff, duration, 1, true, claimableAmount
        );
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), claimableAmount);
        assertEq(tokenVesting.scheduleClaimed(alice, baseTime, cliff, duration, 1, true, claimableAmount), true);

        //Update Merkle Tree
        vm.startPrank(deployer);
        tokenVesting.setMerkleRoot(merkleRoot2);
        vm.stopPrank();

        // Claim with new proof
        vm.startPrank(john);
        tokenVesting.claimSchedule{value: purchasePrice}(johnProof, baseTime, cliff, duration, 1, true, claimableAmount);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(john), claimableAmount);
        assertEq(tokenVesting.scheduleClaimed(john, baseTime, 0, duration, 1, true, claimableAmount), true);
    }

    // Payment Testing

    function testVTokenCostSet() public {
        assertEq(tokenVesting.vTokenCost(), vTokenCost);
    }

    // test change of vTokenCost
    function testChangeVTokenCost() public {
        uint256 newVTokenCost = 0.001 ether;
        assertEq(tokenVesting.vTokenCost(), vTokenCost);

        bytes memory expectedError = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(alice),
            " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );

        vm.startPrank(alice);
        vm.expectRevert(expectedError);
        tokenVesting.setVTokenCost(newVTokenCost);
        vm.stopPrank();

        vm.startPrank(deployer);
        vm.expectRevert(TokenVesting.InvalidAmount.selector);
        tokenVesting.setVTokenCost(10 ether);
        vm.stopPrank();

        vm.startPrank(deployer);
        tokenVesting.setVTokenCost(newVTokenCost);
        vm.stopPrank();
        assertEq(tokenVesting.vTokenCost(), newVTokenCost);
    }

    // test change of paymentReceiver by owner
    function testChangePaymentReceiver() public {
        address payable newPaymentReceiver = payable(bob);
        assertEq(tokenVesting.paymentReceiver(), paymentReceiver);

        bytes memory expectedError = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(bob),
            " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );

        vm.startPrank(bob);
        vm.expectRevert(expectedError);
        tokenVesting.setPaymentReceiver(newPaymentReceiver);
        vm.stopPrank();

        vm.startPrank(deployer);
        vm.expectRevert(TokenVesting.InvalidAddress.selector);
        tokenVesting.setPaymentReceiver(payable(address(0)));

        tokenVesting.setPaymentReceiver(newPaymentReceiver);
        vm.stopPrank();
        assertEq(tokenVesting.paymentReceiver(), newPaymentReceiver);
    }

    function testCantClaimTwiceAcrossContract() public {
        vm.warp(1622551240);

        assertEq(tokenVesting.balanceOf(alice), 0);

        vm.startPrank(alice);
        tokenVesting.claimSchedule{value: purchasePrice}(
            aliceProof, baseTime, cliff, duration, 1, true, claimableAmount
        );
        vm.expectRevert(MultiTokenVestingMerklePurchasable.AlreadyClaimed.selector);
        tokenVesting2.claimSchedule{value: purchasePrice}(
            aliceProof, baseTime, cliff, duration, 1, true, claimableAmount
        );
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), claimableAmount);
        assertEq(tokenVesting2.scheduleClaimed(alice, baseTime, cliff, duration, 1, true, claimableAmount), true);
        assertEq(tokenVesting.scheduleClaimed(alice, baseTime, cliff, duration, 1, true, claimableAmount), true);

        //check if the paymentReceiver received the payment
        assertEq(paymentReceiver.balance, purchasePrice);
    }
}
