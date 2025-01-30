// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Token} from "./TestToken.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract TokenVestingTest is Test {
    Token internal token;
    Token internal wrongToken;
    TokenVesting internal tokenVesting;
    TokenVesting internal tokenVesting_2;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address deployer = makeAddr("bighead");
    address payable deployerPayable = payable(deployer);
    uint256 constant vtokenCost = 1e8;

    // helper function for console logging bytes32
    function bytes32ToString(
        bytes32 _bytes32
    ) public pure returns (string memory) {
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
        tokenVesting = new TokenVesting(
            IERC20Metadata(token),
            "Virtual Test Token",
            "vTT",
            deployer
        );

        vm.stopPrank();

        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
    }

    function testTokenSupply() public view {
        assertEq(token.totalSupply(), 1000000 ether);
        assertEq(token.balanceOf(deployer), 1000000 ether);
    }

    function testWrongToken() public {
        vm.startPrank(deployer);
        vm.expectRevert(TokenVesting.DecimalsError.selector);
        tokenVesting_2 = new TokenVesting(
            IERC20Metadata(wrongToken),
            "Virtual Test Token",
            "vTT",
            deployer
        );
        vm.stopPrank();
    }

    function testVirtualTokenMeta() public view {
        assertEq(tokenVesting.name(), "Virtual Test Token");
        assertEq(tokenVesting.symbol(), "vTT");
        assertEq(tokenVesting.decimals(), 18);
    }

    function testGradualTokenVesting() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;
        TokenVesting.VestingSchedule memory vestingSchedule;

        assertEq(address(tokenVesting.underlyingToken()), address(token));

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 1000 ether);

        assertEq(token.balanceOf(address(tokenVesting)), 1000 ether);
        assertEq(tokenVesting.getWithdrawableAmount(), 1000 ether);

        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();

        assertEq(tokenVesting.holdersVestingScheduleCount(alice), 1);

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0);

        vm.startPrank(alice);
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0);

        // // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        // // check that vested amount is half the total amount to vest
        assertEq(
            tokenVesting.computeReleasableAmount(vestingScheduleId),
            50 ether
        );

        // // check that only beneficiary can try to release vested tokens
        vm.startPrank(bob);
        vm.expectRevert(TokenVesting.Unauthorized.selector);
        tokenVesting.release(vestingScheduleId, 100 ether);
        vm.stopPrank();

        // // check that beneficiary cannot release more than the vested amount
        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.InsufficientReleasableTokens.selector);
        tokenVesting.release(vestingScheduleId, 100 ether);
        vm.stopPrank();

        // // release 10 tokens
        vm.startPrank(alice);
        tokenVesting.release(vestingScheduleId, 10 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(address(tokenVesting)), 990 ether);
        assertEq(alice.balance, 1 ether);

        // // check that the vested amount is now 40
        assertEq(
            tokenVesting.computeReleasableAmount(vestingScheduleId),
            40 ether
        );

        vestingSchedule = tokenVesting.getVestingSchedule(vestingScheduleId);
        assertEq(vestingSchedule.released, 10 ether);

        // // set current time after the end of the vesting period
        vm.warp(baseTime + duration + 1);

        // // check that the vested amount is 90
        assertEq(
            tokenVesting.computeReleasableAmount(vestingScheduleId),
            90 ether
        );

        // // beneficiary release vested tokens (45)
        vm.startPrank(alice);
        tokenVesting.release(vestingScheduleId, 45 ether);
        vm.stopPrank();

        // // owner release vested tokens (45)
        vm.startPrank(deployer);
        tokenVesting.release(vestingScheduleId, 45 ether);
        vm.stopPrank();

        // // check that the number of released tokens is 100
        vestingSchedule = tokenVesting.getVestingSchedule(vestingScheduleId);
        assertEq(vestingSchedule.released, 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);

        // // check that the vested amount is 0
        assertEq(
            tokenVesting.computeReleasableAmount(vestingScheduleId),
            0 ether
        );

        /*
         * TEST SUMMARY
         * send tokens to vesting contract
         * create new vesting schedule (100 tokens)
         * check that vested amount is 0
         * purchase vesting schedule
         * check that vesting schedule is owned by alice
         * set time to half the vesting period
         * check that vested amount is half the total amount to vest (50 tokens)
         * check that only beneficiary can try to release vested tokens
         * check that beneficiary cannot release more than the vested amount
         * release 10 tokens
         * check that the released amount is 10
         * check that the vested amount is now 40
         * set current time after the end of the vesting period
         * check that the vested amount is 90 (100 - 10 released tokens)
         * release all vested tokens (90)
         * check that the number of released tokens is 100
         * check that the vested amount is 0
         * check ETH balance
         */
    }

    function testVestingWithCliff() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 * (365 days);
        uint256 cliff = 1 * (365 days);

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            cliff,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0);

        // One day before cliff ends
        vm.warp(baseTime + cliff - 1 days);
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0);

        // Cliff has ended
        vm.warp(baseTime + cliff);
        assertEq(
            tokenVesting.computeReleasableAmount(vestingScheduleId),
            25 ether
        );

        // Vesting period has ended
        vm.warp(block.timestamp + duration);
        assertEq(
            tokenVesting.computeReleasableAmount(vestingScheduleId),
            100 ether
        );
    }

    function testNonOwnerCannotRevokeSchedule() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        bytes memory expectedError = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(bob),
            " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );

        vm.startPrank(bob);
        vm.expectRevert(expectedError);
        tokenVesting.revoke(vestingScheduleId);
        vm.stopPrank();
    }

    function testCanOnlyBeRevokedIfRevokable() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            false,
            100 ether
        );

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        vm.expectRevert(TokenVesting.NotRevokable.selector);
        tokenVesting.revoke(vestingScheduleId);
        vm.stopPrank();
    }

    function testOnlySchedulerRoleCanCreateSchedule() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert();
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();

        vm.startPrank(deployer);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();
    }

    // test checks that the owner can revoke a vesting schedule and that the beneficiary receives tokens
    function testRevokeScheduleReleasesVestedTokens2() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        assertEq(tokenVesting.getWithdrawableAmount(), 0);

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // Set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);
        assertEq(token.balanceOf(address(alice)), 0 ether);
        vm.stopPrank();
        vm.startPrank(deployer);
        tokenVesting.revoke(vestingScheduleId);
        assertEq(token.balanceOf(address(alice)), 50 ether);

        TokenVesting.VestingSchedule memory vestingSchedule = tokenVesting
            .getVestingSchedule(vestingScheduleId);
        assertEq(vestingSchedule.status == TokenVesting.Status.REVOKED, true);

        assertEq(tokenVesting.getWithdrawableAmount(), 50 ether);

        // Cannot withdraw more than available
        vm.expectRevert(TokenVesting.InsufficientTokensInContract.selector);
        tokenVesting.withdraw(51 ether);

        tokenVesting.withdraw(50 ether);
        assertEq(tokenVesting.getWithdrawableAmount(), 0);

        vm.stopPrank();

        // Alice can't release more tokens
        vm.warp(baseTime + duration);
        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.ScheduleWasRevoked.selector);
        tokenVesting.release(vestingScheduleId, 50 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(address(alice)), 50 ether);
    }

    function testScheduleIndexComputation() public view {
        bytes32 expectedVestingScheduleId = 0x1891b47bd496d985cc84f1e264ac3dea4e3f7af4fafeb854e6cd86a41b23e7f9;

        assertEq(
            tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0),
            expectedVestingScheduleId
        );
    }

    function testTextInputParameterChecks() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);

        vm.expectRevert(TokenVesting.InvalidDuration.selector);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            0,
            1,
            false,
            100 ether
        );

        vm.expectRevert(TokenVesting.InvalidSlicePeriod.selector);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            0,
            false,
            100 ether
        );

        vm.expectRevert(TokenVesting.InvalidAmount.selector);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            false,
            0
        );

        vm.expectRevert(TokenVesting.DurationShorterThanCliff.selector);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            5 weeks,
            duration,
            1,
            false,
            100 ether
        );
    }

    function testComputationMultipleForSchedules() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 1000 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration * 2,
            1,
            true,
            50 ether
        );
        assertEq(tokenVesting.holdersVestingScheduleCount(alice), 2);
        vm.stopPrank();

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        assertEq(tokenVesting.balanceOf(alice), 150 ether);
    }

    function testClaimAvailableTokens() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 1000 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration * 2,
            1,
            true,
            50 ether
        );
        assertEq(tokenVesting.holdersVestingScheduleCount(alice), 2);
        vm.stopPrank();

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        assertEq(tokenVesting.balanceOf(alice), 150 ether);

        vm.startPrank(alice);
        tokenVesting.releaseAvailableTokensForHolder(alice);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 87.5 ether);
        assertEq(token.balanceOf(address(alice)), 62.5 ether);
    }

    function testCannotClaimMoreThanAvailable() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 1000 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration * 2,
            1,
            true,
            50 ether
        );
        assertEq(tokenVesting.holdersVestingScheduleCount(alice), 2);
        vm.stopPrank();

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        vm.startPrank(alice);
        tokenVesting.releaseAvailableTokensForHolder(alice);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 87.5 ether);
        assertEq(token.balanceOf(address(alice)), 62.5 ether);
    }

    function testVirtualTokenTotalSupplyAndBalance() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        // virtual token total supply should be 0 before any vesting schedules are created
        assertEq(tokenVesting.totalSupply(), 0);

        // virtual token balance of alice should be 0 before any vesting schedules are created
        assertEq(tokenVesting.balanceOf(address(alice)), 0);

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // virtual token total supply should be 100 after vesting schedule is created
        assertEq(tokenVesting.totalSupply(), 100 ether);

        // virtual token balance of alice should be 100 after vesting schedule is created and purchased
        assertEq(tokenVesting.balanceOf(address(alice)), 100 ether);

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        vm.startPrank(alice);
        tokenVesting.release(vestingScheduleId, 50 ether);
        assertEq(token.balanceOf(address(alice)), 50 ether);
        vm.stopPrank();

        // virtual token total supply should be 50 after alice has released 50 tokens
        assertEq(tokenVesting.totalSupply(), 50 ether);

        // virtual token balance of alice should be 50 after alice has released 50 tokens
        assertEq(tokenVesting.balanceOf(address(alice)), 50 ether);

        // set time to end of vesting period
        vm.warp(baseTime + duration + 1);

        assertEq(tokenVesting.balanceOf(address(alice)), 50 ether);

        vm.startPrank(alice);
        tokenVesting.release(vestingScheduleId, 50 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(address(alice)), 100 ether);
        assertEq(tokenVesting.balanceOf(address(alice)), 0);
    }

    function testNonTransferability() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        assertEq(tokenVesting.balanceOf(address(alice)), 100 ether);

        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.NotSupported.selector);
        tokenVesting.transfer(address(bob), 50 ether);

        vm.expectRevert(TokenVesting.NotSupported.selector);
        tokenVesting.transferFrom(address(alice), address(bob), 50 ether);

        vm.expectRevert(TokenVesting.NotSupported.selector);
        tokenVesting.approve(address(1), 50 ether);
        vm.stopPrank();
    }

    function testFuzzCreateAndRelease(uint256 amount, uint256 duration) public {
        // Assuming 1.6 Tredecillion tokens is enough for everyone
        uint256 maxTokens = 2 ** 200;
        // schedule duration between 1 day and 50 years
        uint256 maxDuration = 50 * (365 days);
        vm.deal(alice, amount);

        vm.assume(amount > 0 ether && amount <= maxTokens);
        vm.assume(duration > 1 weeks && duration <= maxDuration);

        uint256 baseTime = block.timestamp;

        vm.startPrank(deployer);
        Token fuzzToken = new Token("Fuzz Token", "TT", 18, amount);
        TokenVesting fuzzVesting = new TokenVesting(
            IERC20Metadata(fuzzToken),
            "Fuzz Vesting",
            "FV",
            deployer
        );
        fuzzToken.transfer(address(fuzzVesting), amount);
        fuzzVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            amount
        );
        vm.stopPrank();

        bytes32 vestingScheduleId = fuzzVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        uint256 releasableAmount = fuzzVesting.computeReleasableAmount(
            vestingScheduleId
        );

        vm.startPrank(alice);
        fuzzVesting.release(vestingScheduleId, releasableAmount);
        vm.stopPrank();
    }

    function testUnderlyingTokenDecimals() public {
        vm.startPrank(deployer);
        Token customToken = new Token("6 Decimals Token", "6DT", 6, 100 ether);
        vm.expectRevert(TokenVesting.DecimalsError.selector);
        new TokenVesting(
            IERC20Metadata(customToken),
            "Vesting",
            "v6DT",
            deployer
        );
        vm.stopPrank();
    }

    function testStartTooFarInFuture() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);

        // Test start time more than 30 weeks in future
        vm.expectRevert(TokenVesting.InvalidStart.selector);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime + 31 weeks, // Start time > 30 weeks
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();
    }

    function testSlicePeriodTooLong() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);

        // Test slice period > 60 seconds
        vm.expectRevert(TokenVesting.InvalidSlicePeriod.selector);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            61, // slice period > 60 seconds
            true,
            100 ether
        );
        vm.stopPrank();
    }

    function testInvalidScheduleRevoke() public {
        vm.startPrank(deployer);
        // Try to revoke non-existent schedule
        bytes32 invalidScheduleId = keccak256("invalid");
        vm.expectRevert(TokenVesting.InvalidSchedule.selector);
        tokenVesting.revoke(invalidScheduleId);
        vm.stopPrank();
    }

    function testUnauthorizedReleaseAvailableTokens() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();

        // Try to release available tokens for alice from bob's account
        vm.startPrank(bob);
        vm.expectRevert(TokenVesting.Unauthorized.selector);
        tokenVesting.releaseAvailableTokensForHolder(alice);
        vm.stopPrank();
    }

    function testPauseUnpause() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);

        // Test pause
        tokenVesting.setPaused(true);
        vm.expectRevert("Pausable: paused");
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        // Test unpause
        tokenVesting.setPaused(false);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();
    }

    function testUnauthorizedPause() public {
        vm.startPrank(alice);
        bytes memory expectedError = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(alice),
            " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        vm.expectRevert(expectedError);
        tokenVesting.setPaused(true);
        vm.stopPrank();
    }

    function testWithdrawMoreThanAvailable() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        // Try to withdraw more than available
        vm.expectRevert(TokenVesting.InsufficientTokensInContract.selector);
        tokenVesting.withdraw(101 ether);
        vm.stopPrank();
    }

    function testDurationTooLong() public {
        uint256 baseTime = block.timestamp;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);

        // Test duration > 50 years
        vm.expectRevert(TokenVesting.InvalidDuration.selector);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            51 * 365 days, // Duration > 50 years
            1,
            true,
            100 ether
        );
        vm.stopPrank();
    }

    function testAmountTooLarge() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        // Create a new token with enough supply
        Token largeToken = new Token("Large Token", "LT", 18, 2 ** 201);
        TokenVesting largeVesting = new TokenVesting(
            IERC20Metadata(largeToken),
            "Large Vesting",
            "LV",
            deployer
        );

        // Transfer enough tokens to cover the large amount
        largeToken.transfer(address(largeVesting), 2 ** 201);

        // Test amount > 2**200
        vm.expectRevert(TokenVesting.InvalidAmount.selector);
        largeVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            2 ** 201 // Amount too large
        );
        vm.stopPrank();
    }

    function testInsufficientTokensInContract() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 50 ether); // Only transfer 50 tokens

        // Try to create schedule for 100 tokens
        vm.expectRevert(TokenVesting.InsufficientTokensInContract.selector);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );
        vm.stopPrank();
    }

    function testRevokeNonExistentSchedule() public {
        vm.startPrank(deployer);
        bytes32 nonExistentId = keccak256("non-existent");
        vm.expectRevert(TokenVesting.InvalidSchedule.selector);
        tokenVesting.revoke(nonExistentId);
        vm.stopPrank();
    }

    function testReleaseFromRevokedSchedule() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // Revoke the schedule
        tokenVesting.revoke(vestingScheduleId);
        vm.stopPrank();

        // Try to release from revoked schedule
        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.ScheduleWasRevoked.selector);
        tokenVesting.release(vestingScheduleId, 50 ether);
        vm.stopPrank();
    }

    function testDurationTooShort() public {
        uint256 baseTime = block.timestamp;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);

        // Test duration < 7 days
        vm.expectRevert(TokenVesting.InvalidDuration.selector);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            6 days, // Duration < 7 days
            1,
            true,
            100 ether
        );
        vm.stopPrank();
    }

    function testComputeReleasableAmountAfterRevocation() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // Move to middle of vesting period
        vm.warp(baseTime + duration / 2);

        // Get releasable amount before revocation
        uint256 releasableBeforeRevoke = tokenVesting.computeReleasableAmount(
            vestingScheduleId
        );
        assertEq(releasableBeforeRevoke, 50 ether);

        // Release available tokens
        tokenVesting.release(vestingScheduleId, releasableBeforeRevoke);

        // Revoke the schedule
        tokenVesting.revoke(vestingScheduleId);

        // Verify schedule status is revoked
        TokenVesting.VestingSchedule memory schedule = tokenVesting
            .getVestingSchedule(vestingScheduleId);
        assertEq(
            uint256(schedule.status),
            uint256(TokenVesting.Status.REVOKED)
        );

        // Verify released amount
        assertEq(schedule.released, 50 ether);
        vm.stopPrank();
    }

    function testGetVestingScheduleByAddressAndIndex() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        TokenVesting.VestingSchedule memory schedule = tokenVesting
            .getVestingScheduleByAddressAndIndex(alice, 0);
        assertEq(schedule.beneficiary, alice);
        assertEq(schedule.amountTotal, 100 ether);
        assertEq(schedule.duration, duration);
        assertEq(schedule.revokable, true);
        vm.stopPrank();
    }

    function testReleaseByOwner() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // Move to middle of vesting period
        vm.warp(baseTime + duration / 2);

        // Owner can release on behalf of beneficiary
        tokenVesting.release(vestingScheduleId, 50 ether);
        assertEq(token.balanceOf(alice), 50 ether);
        vm.stopPrank();
    }

    function testReleaseByUnauthorized() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);
        vm.stopPrank();

        // Move to middle of vesting period
        vm.warp(baseTime + duration / 2);

        // Charlie (unauthorized) tries to release
        vm.startPrank(charlie);
        vm.expectRevert(TokenVesting.Unauthorized.selector);
        tokenVesting.release(vestingScheduleId, 50 ether);
        vm.stopPrank();
    }

    function testReleaseAvailableTokensByOwner() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        // Move to middle of vesting period
        vm.warp(baseTime + duration / 2);

        // Owner can release available tokens for beneficiary
        tokenVesting.releaseAvailableTokensForHolder(alice);
        assertEq(token.balanceOf(alice), 50 ether);
        vm.stopPrank();
    }

    function testComputeReleasableAmountBeforeCliff() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;
        uint256 cliff = 2 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            cliff,
            duration,
            1,
            true,
            100 ether
        );

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // Check before cliff
        vm.warp(baseTime + cliff - 1 days);
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0);
        vm.stopPrank();
    }

    function testComputeReleasableAmountAfterEnd() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(
            alice,
            baseTime,
            0,
            duration,
            1,
            true,
            100 ether
        );

        bytes32 vestingScheduleId = tokenVesting
            .computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // Check after end
        vm.warp(baseTime + duration + 1 days);
        assertEq(
            tokenVesting.computeReleasableAmount(vestingScheduleId),
            100 ether
        );
        vm.stopPrank();
    }
}
