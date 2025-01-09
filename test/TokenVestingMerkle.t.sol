// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Token } from "./TestToken.sol";
import { TokenVestingMerkle } from "../src/TokenVestingMerkle.sol";
import { TokenVesting } from "../src/TokenVesting.sol";

contract TokenVestingMerkleTest is Test {
    Token internal token;
    TokenVestingMerkle internal tokenVesting;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address deployer = makeAddr("bighead");

    address jane = makeAddr("jane");
    address john = makeAddr("john");

    bytes32[] aliceProof = new bytes32[](1);

    bytes32[] johnProof = new bytes32[](3);

    // merkleRoot of alice, bob, bighead
    bytes32 merkleRoot1 = 0xd3c242c647a293473133758815a38c34eaa471e529e85a9698d0954fea73de70;

    // merkleRoot of alice, bob, bighead, jane, john
    bytes32 merkleRoot2 = 0xdec85dd4681b9730081b74e7337159b996eae28b57448cec7cea8ec343f0d836;

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
        token = new Token("Test Token", "TT", 18, 1000000 ether);

        // Iniate TokenVestingMerkle with the merkle root from the example MerkleTree `samples/merkleTree.json`
        tokenVesting = new TokenVestingMerkle(IERC20Metadata(token), "Virtual Test Token", "vTT", deployer, merkleRoot1);

        token.transfer(address(tokenVesting), 1000000 ether);
        vm.stopPrank();
    }

    function testcanClaimSchedule() public {
        vm.warp(1622551240);

        assertEq(tokenVesting.balanceOf(alice), 0);

        vm.startPrank(alice);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 20000 ether);
        assertEq(tokenVesting.scheduleClaimed(alice, 1622551248, 0, 2630000, 1, true, 20000 ether), true);
    }

    function testCanOnlyClaimOnce() public {
        vm.warp(1622551240);

        vm.startPrank(alice);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.expectRevert(TokenVestingMerkle.AlreadyClaimed.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 20000 ether);
    }

    function testProofMustBeValid() public {
        vm.warp(1622551240);
        vm.startPrank(alice);

        // Pass wrong number of tokens
        vm.expectRevert(TokenVestingMerkle.InvalidProof.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 30000 ether);

        // Pass invalid proof
        aliceProof[0] = 0xca6d546259ec0929fd20fbc9a057c980806abef37935fb5ca5f6a179718f1481;

        vm.expectRevert(TokenVestingMerkle.InvalidProof.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 0);
    }

    function testCannotClaimWithoutTokens() public {
        vm.warp(1622551240);

        vm.startPrank(deployer);
        tokenVesting.withdraw(1000000 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(address(tokenVesting)), 0);

        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.InsufficientTokensInContract.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.scheduleClaimed(alice, 1622551248, 0, 2630000, 1, true, 20000 ether), false);
    }

    function testCanUpdateMerkleTree() public {
        vm.warp(1622551240);

        assertEq(tokenVesting.balanceOf(alice), 0);

        vm.startPrank(alice);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 20000 ether);
        assertEq(tokenVesting.scheduleClaimed(alice, 1622551248, 0, 2630000, 1, true, 20000 ether), true);

        //TODO: Update Merkle Tree
        vm.startPrank(deployer);
        tokenVesting.updateMerkleRoot(merkleRoot2);
        vm.stopPrank();

        // Claim with new proof
        vm.startPrank(john);
        tokenVesting.claimSchedule(johnProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(john), 20000 ether);
        assertEq(tokenVesting.scheduleClaimed(john, 1622551248, 0, 2630000, 1, true, 20000 ether), true);
    }
}
