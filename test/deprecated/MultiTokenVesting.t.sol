// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Token} from "../TestToken.sol";
import {TokenVesting} from "../../src/TokenVesting.sol";
import {MultiTokenVesting} from "../../src/deprecated/MultiTokenVesting.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MultiTokenVestingTest is Test {
    Token internal token;
    Token internal wrongToken;
    TokenVesting internal tokenVesting;
    MultiTokenVesting internal tokenVesting_2;
    TokenVesting internal tokenVesting_3;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address deployer = makeAddr("bighead");
    address payable deployerPayable = payable(deployer);
    // address vestingCreator = makeAddr("vestingCreator");
    uint256 constant vtokenCost = 1e8;

    // helper function for console logging bytes32
    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    function setUp() public {
        vm.startPrank(deployer);
        token = new Token("Test Token", "TT", 18, 1000000 ether);
        wrongToken = new Token("Wrong Token", "TT", 6, 1000000 ether);
        tokenVesting = new TokenVesting(IERC20Metadata(token), "Virtual Test Token", "vTT", deployer);

        vm.stopPrank();

        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
    }

    //// Test multiple vesting contracts

    function testMultipleVestingContractsClaim() public {
        vm.startPrank(deployer);
        tokenVesting_2 =
            new MultiTokenVesting(IERC20Metadata(token), "Virtual Test Token", "vTT", deployer, address(tokenVesting));
        vm.stopPrank();

        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;
        MultiTokenVesting.VestingSchedule memory vestingSchedule;
        MultiTokenVesting.VestingSchedule memory vestingSchedule_2;

        assertEq(address(tokenVesting.underlyingToken()), address(token));
        assertEq(address(tokenVesting_2.underlyingToken()), address(token));

        vm.startPrank(deployer);

        token.transfer(address(tokenVesting), 500 ether);
        token.transfer(address(tokenVesting_2), 500 ether);

        assertEq(token.balanceOf(address(tokenVesting)), 500 ether);
        assertEq(tokenVesting.getWithdrawableAmount(), 500 ether);

        assertEq(token.balanceOf(address(tokenVesting_2)), 500 ether);
        assertEq(tokenVesting_2.getWithdrawableAmount(), 500 ether);

        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 50 ether);
        tokenVesting_2.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 50 ether);
        vm.stopPrank();

        assertEq(tokenVesting.holdersVestingScheduleCount(alice), 1);
        assertEq(tokenVesting_2.holdersVestingScheduleCount(alice), 1);

        bytes32 vestingScheduleId = tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0);
        assertEq(tokenVesting_2.computeReleasableAmount(vestingScheduleId), 0);

        vm.startPrank(alice);
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0);
        assertEq(tokenVesting_2.computeReleasableAmount(vestingScheduleId), 0);
        vm.stopPrank();

        // // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        // // check that vested amount is half the total amount to vest
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 25 ether);
        assertEq(tokenVesting_2.computeReleasableAmount(vestingScheduleId), 25 ether);

        // // check that beneficiary cannot release more than the vested amount
        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.InsufficientReleasableTokens.selector);
        tokenVesting_2.release(vestingScheduleId, 50 ether);
        vm.stopPrank();

        // // release 10 tokens
        vm.startPrank(alice);
        tokenVesting_2.release(vestingScheduleId, 10 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(address(tokenVesting_2)), 490 ether);
        assertEq(alice.balance, 1 ether);
        assertEq(tokenVesting.balanceOf(alice), 50 ether);
        assertEq(tokenVesting_2.balanceOf(alice), 90 ether);
        assertEq(tokenVesting_2.totalSupply(), 90 ether);

        // // check that the vested amount is now 40
        assertEq(tokenVesting_2.computeReleasableAmount(vestingScheduleId), 15 ether);

        vestingSchedule = tokenVesting.getVestingSchedule(vestingScheduleId);
        vestingSchedule_2 = tokenVesting_2.getVestingSchedule(vestingScheduleId);
        assertEq(vestingSchedule_2.released, 10 ether);
        assertEq(vestingSchedule.released, 0 ether);

        // // set current time after the end of the vesting period
        vm.warp(baseTime + duration + 1);

        // // check that the vested amount is 90
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 50 ether);
        assertEq(tokenVesting_2.computeReleasableAmount(vestingScheduleId), 40 ether);

        // // beneficiary release vested tokens (45)
        vm.startPrank(alice);
        tokenVesting.releaseAvailableTokensForHolder(alice);
        tokenVesting_2.releaseAvailableTokensForHolder(alice);
        vm.stopPrank();

        // // check that the number of released tokens is 100
        vestingSchedule = tokenVesting.getVestingSchedule(vestingScheduleId);
        vestingSchedule_2 = tokenVesting.getVestingSchedule(vestingScheduleId);
        assertEq(vestingSchedule.released, 50 ether);
        assertEq(vestingSchedule_2.released, 50 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(tokenVesting.balanceOf(alice), 0 ether);
        assertEq(tokenVesting_2.balanceOf(alice), 0 ether);
        assertEq(tokenVesting_2.totalSupply(), 0 ether);

        // // check that the vested amount is 0
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0 ether);
    }

    function testMultipleVestingBalance() public {
        vm.startPrank(deployer);
        tokenVesting_2 =
            new MultiTokenVesting(IERC20Metadata(token), "Virtual Test Token", "vTT", deployer, address(tokenVesting));
        tokenVesting_3 = new TokenVesting(IERC20Metadata(token), "Virtual Test Token", "vTT", deployer);
        vm.stopPrank();

        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);

        token.transfer(address(tokenVesting), 500 ether);
        token.transfer(address(tokenVesting_2), 500 ether);
        token.transfer(address(tokenVesting_3), 500 ether);

        assertEq(token.balanceOf(address(tokenVesting)), 500 ether);
        assertEq(token.balanceOf(address(tokenVesting_2)), 500 ether);
        assertEq(token.balanceOf(address(tokenVesting_3)), 500 ether);

        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 50 ether);
        tokenVesting_2.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 50 ether);
        tokenVesting_3.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 50 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 50 ether);
        assertEq(tokenVesting_2.balanceOf(alice), 100 ether);
        assertEq(tokenVesting_2.totalSupply(), 100 ether);
        assertEq(tokenVesting.totalSupply(), 50 ether);
        bytes32 vestingScheduleId = tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // // set current time after the end of the vesting period
        vm.warp(baseTime + duration + 1);

        // // check that the vested amount is 90
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 50 ether);

        // // beneficiary release vested tokens (45)
        vm.startPrank(alice);
        tokenVesting.releaseAvailableTokensForHolder(alice);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 50 ether);
        assertEq(tokenVesting.balanceOf(alice), 0 ether);
        assertEq(tokenVesting_2.balanceOf(alice), 50 ether);
        assertEq(tokenVesting_2.totalSupply(), 50 ether);

        vm.startPrank(deployer);
        tokenVesting_2.addExternalVestingContract(address(tokenVesting_3));
        vm.stopPrank();

        assertEq(tokenVesting_2.totalSupply(), 100 ether);

        // // beneficiary release vested tokens (45)
        vm.startPrank(alice);
        tokenVesting_2.releaseAvailableTokensForHolder(alice);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(tokenVesting_2.balanceOf(alice), 50 ether);
        assertEq(tokenVesting_3.balanceOf(alice), 50 ether);
        assertEq(tokenVesting_2.totalSupply(), 50 ether);

        vm.startPrank(deployer);
        tokenVesting_2.removeExternalVestingContract(address(tokenVesting_3));
        vm.stopPrank();

        assertEq(tokenVesting_2.totalSupply(), 0 ether);
        assertEq(tokenVesting_3.balanceOf(alice), 50 ether);
        assertEq(tokenVesting_2.balanceOf(alice), 0 ether);
    }
}
