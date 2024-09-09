// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/most_contracts/Staker.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../contracts/most_contracts/MOST.sol";

error OwnableUnauthorizedAccount(address account);
error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

contract StakerTest is Test {
    Staker public staker;
    MOST public token;

    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        // Create test users

        owner = vm.addr(1);
        user1 = vm.addr(2);
        user2 = vm.addr(3);

        // Fund test users with some ether
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        vm.startPrank(owner);
        // Deploy ERC20 token and allocate some tokens to users
        token = new MOST(100000 ether);
        // Deploy Staker contract
        staker = new Staker(address(token));

        token.transfer(user1, 100 ether);
        token.transfer(user2, 100 ether);

        vm.stopPrank();
    }

    function setUpUserWithStake(
        address user,
        uint256 amount,
        uint256 duration
    ) public {
        vm.prank(user);
        token.approve(address(staker), amount);
        vm.prank(user);
        staker.stake(amount, duration);
    }

    function fundContract(uint256 amount) public {
        vm.startPrank(owner);
        token.approve(address(staker), amount);
        staker.fundRewards(amount);
        vm.stopPrank();
    }

    function unstake_value_after_penalty(
        uint256 value,
        uint256 stakedFor,
        uint256 lockedFor
    ) public pure returns (uint256) {
        uint256 ratio = 50 +
            ((50 * (stakedFor - (lockedFor / 2))) / (lockedFor / 2));
        return (value * ratio) / 100;
    }

    function firstTimeStake(address user) public {
        vm.prank(user);
        token.approve(address(staker), 100 ether);
        vm.prank(user);
        staker.stake(1 ether, 30 days);
    }

    function check_stake(
        address user,
        uint256 _amountStaked,
        uint256 _lockedAt,
        uint256 _lockedFor,
        uint256 _lastClaimTime
    ) public view {
        (
            uint256 amountStaked,
            uint256 lockedAt,
            uint256 lockedFor,
            uint256 lastClaimTime
        ) = staker.getUserStakeDetails(user);
        assertEq(amountStaked, _amountStaked);
        assertEq(lockedAt, _lockedAt);
        assertEq(lockedFor, _lockedFor);
        assertEq(lastClaimTime, _lastClaimTime);
    }

    function testStake() public {
        // User1 stakes tokens
        firstTimeStake(user1);

        // Check staked balance
        check_stake(user1, 1 ether, block.timestamp, 30 days, 0);

        // stake again for 30 days right after staking, ensure time is slightly more, amount is added and duration is same
        vm.warp(block.timestamp + 12);
        vm.prank(user1);
        staker.stake(1 ether, 30 days);
        check_stake(user1, 2 ether, block.timestamp, 30 days, 0);

        // // increase stake, with increased duration
        vm.prank(user1);
        staker.stake(1 ether, 60 days);
        check_stake(user1, 3 ether, block.timestamp, 60 days, 0);

        // Expect the transaction to revert with an error
        vm.expectRevert();
        vm.prank(user1);
        staker.stake(1 ether, 59 days);

        // Verify that other stake values remain the same
        check_stake(user1, 3 ether, block.timestamp, 60 days, 0);

        // // must revert when try to stake for less duration than previous duration
        vm.expectRevert();
        vm.prank(user1);
        staker.stake(1 ether, 30 days);
        check_stake(user1, 3 ether, block.timestamp, 60 days, 0); //these values remain the same
    }

    //no penalization
    function testUnstakeNoPenalization() public {
        // User1 stakes tokens
        firstTimeStake(user1); //user 1 has 99 E, staked 1 E
        // User2 stakes tokens
        firstTimeStake(user2); //user 1 has 99 E, staked 1 E

        //reverts for invalid unstake amounts
        vm.expectRevert();
        vm.prank(user2);
        staker.unstake(0); //unstaking 0

        vm.expectRevert();
        vm.prank(user2);
        staker.unstake(100 ether); //unstaking more than what was staked

        // //unstake before all tokens unlock, receive penalized amount and expected APRm in different durations
        vm.warp(block.timestamp + 30 days); //fast forward to slightly less than half duration

        vm.prank(user1);
        staker.unstake(1 ether); //trying to unstake all
        check_stake(user1, 0 ether, 0, 0, 0);
        assertEq(token.balanceOf(user1), 100 ether); //no APR because not rewards not funded or penalized

        //adding rewards
        vm.startPrank(owner);
        token.approve(address(staker), 100 ether);
        staker.fundRewards(1 ether);
        vm.stopPrank();

        vm.prank(user2);
        staker.unstake(1 ether); //trying to unstake all
        check_stake(user2, 0 ether, 0, 0, block.timestamp);
        assertApproxEqAbs(
            token.balanceOf(user2),
            100 ether + 0.00082 ether,
            0.00001 ether
        );
        // assertEq(token.balanceOf(user2), 100 ether + 0.00082);

        //both users details should be reset because they unstaked all
        vm.prank(user1);
        staker.stake(3 ether, 90 days);
        vm.prank(user2);
        staker.stake(3 ether, 180 days);

        //increasing time to more than 90 days to see if user1 gets more APR and is able to unstake all tokens
        vm.warp(block.timestamp + 120 days);
        vm.prank(user1);
        staker.unstake(1 ether); //trying to unstake only 1/3
        check_stake(
            user1,
            2 ether,
            block.timestamp - 120 days,
            90 days,
            block.timestamp
        );

        //apr for year should 5% and reward should be 0.04931...
        assertApproxEqAbs(
            token.balanceOf(user1),
            98 ether + 0.04931 ether,
            0.001 ether
        );

        vm.warp(block.timestamp + 60 days);
        vm.prank(user1);
        staker.unstake(2 ether); // unstaking rest: 2/3
        check_stake(user1, 0 ether, 0, 0, block.timestamp);

        //apr for year should 5% and reward should be 0.04931...
        assertApproxEqAbs(
            token.balanceOf(user1),
            //prev apr + current apr
            100 ether + 0.04931 ether + 0.01643835616 ether,
            0.0001 ether
        );

        vm.prank(user2);
        staker.unstake(3 ether); // unstaking all
        check_stake(user2, 0 ether, 0, 0, block.timestamp);

        //apr for year should 5% and reward should be 0.04931...
        assertApproxEqAbs(
            token.balanceOf(user2),
            //prev apr + current apr
            100 ether + 0.00082 ether + 0.1035616438 ether,
            0.0001 ether
        );
    }

    //works for any valid amount of stake and duration
    function testFuzzStake(uint256 value, uint256 duration) public {
        vm.assume(value > 0 && value <= token.balanceOf(user1));
        vm.assume(duration > 0);

        vm.prank(user1);
        token.approve(address(staker), token.balanceOf(user1));

        if (
            duration != 30 days &&
            duration != 60 days &&
            duration != 90 days &&
            duration != 180 days
        ) {
            vm.expectRevert();
            vm.prank(user1);
            staker.stake(value, duration);
            return;
        }

        vm.prank(user1);
        token.approve(address(staker), value);
        vm.prank(user1);
        staker.stake(value, duration);
        (uint256 amountStaked, , uint256 lockedFor, ) = staker
            .getUserStakeDetails(user1);

        assertEq(amountStaked, value);
        assertEq(lockedFor, duration);
    }

    function testUnstakePenalization() public {
        // User1 stakes tokens
        firstTimeStake(user1); //user 1 has 99 E, staked 1 E
        // User2 stakes tokens
        firstTimeStake(user2); //user 1 has 99 E, staked 1 E

        //reverts for invalid unstake amounts
        vm.expectRevert();
        vm.prank(user2);
        staker.unstake(0); //unstaking 0

        vm.expectRevert();
        vm.prank(user2);
        staker.unstake(100 ether); //unstaking more than what was staked

        // //unstake before all tokens unlock, receive penalized amount and expected APRm in different durations
        vm.warp(block.timestamp + 14 days); //fast forward to slightly less than half duration

        //50% penalization
        vm.prank(user1);
        staker.unstake(1 ether); //trying to unstake all
        check_stake(user1, 0 ether, 0, 0, block.timestamp);
        assertApproxEqAbs(
            token.balanceOf(user1), // 99 + 0.5 + apr
            99 ether + 0.5 ether + 0.000383 ether,
            0.00001 ether
        ); //half amount plus apr, APR comes from penalization

        vm.warp(block.timestamp + 7 days);
        vm.prank(user2);
        staker.unstake(1 ether); //trying to unstake all, must unstake based on linear function
        check_stake(user2, 0 ether, 0, 0, block.timestamp);

        assertApproxEqAbs(
            token.balanceOf(user2),
            99 ether +
                unstake_value_after_penalty(1 ether, 21 days, 30 days) +
                0.000575 ether,
            0.00001 ether
        );

        // // User2 unstakes tokens
        // vm.prank(user2);
        // staker.unstake(50 ether);

        // // Check staked balance
        // (uint256 amountStaked, , , ) = staker.getUserStakeDetails(user2);
        // assertEq(amountStaked, 0);

        //when reward balance is available, when it's not
    }

    // function testClaimRewards() public {
    //     // User1 stakes tokens
    //     vm.prank(user1);
    //     token.approve(address(staker), 100 ether);
    //     vm.prank(user1);
    //     staker.stake(100 ether, 30 days);

    //     // Fast forward time to accumulate rewards
    //     vm.warp(block.timestamp + 30 days);

    //     // User1 claims rewards
    //     vm.prank(user1);
    //     staker.claim();

    //     // Check user balance to ensure rewards are added
    //     uint256 userBalance = token.balanceOf(user1);
    //     assert(userBalance > 0); // Rewards should increase user balance
    // }

    function testConstructorSettings() public view {
        // Test initial multipliers
        assertEq(
            staker.getMultiplier(30 days),
            10,
            "30-day multiplier should be 1x"
        );
        assertEq(
            staker.getMultiplier(60 days),
            15,
            "60-day multiplier should be 1.5x"
        );
        assertEq(
            staker.getMultiplier(90 days),
            20,
            "90-day multiplier should be 2x"
        );
        assertEq(
            staker.getMultiplier(180 days),
            35,
            "180-day multiplier should be 3.5x"
        );

        // Test initial APRs
        assertEq(staker.getAPR(30 days), 100, "30-day APR should be 1%");
        assertEq(staker.getAPR(60 days), 300, "60-day APR should be 3%");
        assertEq(staker.getAPR(90 days), 500, "90-day APR should be 5%");
        assertEq(staker.getAPR(180 days), 700, "180-day APR should be 7%");

        // Test initial tier indexes
        assertEq(
            staker.getTierIndex(29_999),
            0,
            "Tier index for 29,999 tokens should be 0"
        );
        assertEq(
            staker.getTierIndex(30_000),
            1,
            "Tier index for 30,000 tokens should be 1"
        );
        assertEq(
            staker.getTierIndex(75_000),
            2,
            "Tier index for 75,000 tokens should be 2"
        );
        assertEq(
            staker.getTierIndex(250_000),
            3,
            "Tier index for 250,000 tokens should be 3"
        );
        assertEq(
            staker.getTierIndex(500_000),
            4,
            "Tier index for 500,000 tokens should be 4"
        );
        assertEq(
            staker.getTierIndex(1_000_000),
            5,
            "Tier index for 1,000,000 tokens should be 5"
        );
    }

    function testFailFundRewardsWithInsufficientBalance() public {
        vm.prank(user1);
        // Attempt to fund with more tokens than the user holds
        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
        staker.fundRewards(200 ether);
    }

    function testMultipleUsersStakingAndUnstakingWithPenalty() public {
        // User1 stakes
        firstTimeStake(user1);
        // User2 stakes a larger amount for a longer duration
        vm.prank(user2);
        token.approve(address(staker), 100 ether);
        vm.prank(user2);
        staker.stake(10 ether, 180 days);

        // Fast forward time and check balances and penalties
        vm.warp(block.timestamp + 90 days); // Halfway for user2, full period for user1

        // User1 unstakes with no penalty
        vm.prank(user1);
        staker.unstake(1 ether);

        // User2 unstakes with penalty
        vm.prank(user2);
        staker.unstake(5 ether);

        // Check final balances
        assertEq(token.balanceOf(user1), 100 ether); // no penalty
        assertLt(token.balanceOf(user2), 95 ether); // penalty applied
    }

    function testClaimRewardsWithoutFunding() public {
        firstTimeStake(user1);
        vm.warp(block.timestamp + 40 days);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NoRewardsInTressury.selector));
        staker.claim();
    }

    function testStakeWithUnsupportedDuration() public {
        vm.prank(user1);
        token.approve(address(staker), 100 ether);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidDuration.selector, 15 days)
        );
        staker.stake(1 ether, 15 days); // Unsupported duration
    }

    function testHaltedContract() public {
        // Halt the contract
        vm.prank(owner);
        staker.halt(true);

        // Try staking and unstaking
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Halted.selector));
        staker.stake(1 ether, 30 days);

        vm.prank(owner);
        staker.halt(false);

        firstTimeStake(user1);

        vm.prank(owner);
        staker.halt(true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Halted.selector));
        staker.unstake(1 ether);
    }

    function testRewardCalculationAccuracy() public {
        uint256 stakeAmount = 1 ether;
        uint256 duration = 180 days;

        setUpUserWithStake(user1, stakeAmount, duration);

        vm.warp(block.timestamp + 365 days); // Forward one year

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NoRewardsInTressury.selector));
        staker.claim();

        fundContract(100 ether);

        vm.prank(user1);
        staker.unstake(1 ether);

        uint256 apr = staker.getAPR(duration);
        uint256 expectedReward = (1 ether * apr * 365 days) /
            (365 days * 100_00);
        uint256 userBalance = token.balanceOf(user1);

        assertApproxEqAbs(
            userBalance,
            100 ether + expectedReward,
            0.000000000001 ether
        );
    }

    function testVerifyRewardCalculation() public {
        uint256 stakeAmount = 1 ether;
        uint256 duration = 30 days;

        setUpUserWithStake(user1, stakeAmount, duration);

        vm.warp(block.timestamp + duration + 15 days);

        uint256 apr = staker.getAPR(duration);
        uint256 timeStaked = duration + 15 days;
        uint256 expectedReward = (stakeAmount * apr * timeStaked) /
            (365 days * 100_00);

        fundContract(expectedReward + 1 ether);

        uint256 initialBalance = token.balanceOf(user1);

        vm.prank(user1);
        staker.unstake(0);

        uint256 newBalance = token.balanceOf(user1);
        uint256 actualReward = newBalance - initialBalance;

        assertApproxEqAbs(
            actualReward,
            expectedReward,
            0.000000000001 ether,
            "The actual reward does not match the expected reward closely enough."
        );
    }

    function testSetMultiplier() public {
        // Only owner can set multipliers
        vm.prank(owner);
        staker.setMultiplier(30 days, 25); // Set a new multiplier for 30 days

        // Check the new multiplier is updated
        uint256 newMultiplier = staker.getMultiplier(30 days);
        assertEq(newMultiplier, 25, "Multiplier should be updated to 25");

        // Non-owner cannot set multiplier
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1)
        );
        staker.setMultiplier(30 days, 30);
        vm.stopPrank();
    }

    function testSetAPRs() public {
        // Only owner can set APRs
        vm.prank(owner);
        staker.setAPRs(30 days, 200); // Set a new APR for 30 days

        // Check the new APR is updated
        uint256 newAPR = staker.getAPR(30 days);
        assertEq(newAPR, 200, "APR should be updated to 200");

        // Non-owner cannot set APRs
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1)
        );
        staker.setAPRs(30 days, 250);
        vm.stopPrank();
    }

    function testWithdraw() public {
        uint256 initialBalanceOfOwner = token.balanceOf(owner);
        uint256 amountToFund = 50 ether;
        uint256 amountToWithdraw = 10 ether;

        // Fund the contract first
        vm.startPrank(owner);
        token.approve(address(staker), amountToFund);
        staker.fundRewards(amountToFund);
        vm.stopPrank();

        // Only owner can withdraw
        vm.prank(owner);
        staker.withdraw(amountToWithdraw);
        assertEq(
            initialBalanceOfOwner - (amountToFund - amountToWithdraw),
            token.balanceOf(owner),
            "Owner should withdraw `amountToWithdraw`"
        );

        // Non-owner cannot withdraw
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1)
        );
        staker.withdraw(1 ether);
        vm.stopPrank();
    }

    function testStakedBalance() public {
        // User1 stakes tokens
        firstTimeStake(user1);

        // Check staked balance reflects the stake
        uint256 stakedAmount = staker.stakedBalance(user1);
        assertEq(stakedAmount, 1 ether, "Staked amount should match");

        // Check staked balance for a user with no stake
        uint256 stakedAmountUser2 = staker.stakedBalance(user2);
        assertEq(stakedAmountUser2, 0, "Staked amount should be 0 for user2");
    }

    function testGetUnlockTime() public {
        // User1 stakes tokens for 30 days
        firstTimeStake(user1);

        // Check the unlock time is set correctly
        uint256 unlockTime = staker.getUnlockTime(user1);
        assertEq(
            unlockTime,
            block.timestamp + 30 days,
            "Unlock time should be 30 days from now"
        );

        // Test unlock time after updating the stake duration
        vm.startPrank(user1);
        token.approve(address(staker), 1 ether);
        staker.stake(1 ether, 60 days); // Update duration to 60 days
        vm.stopPrank();

        uint256 newUnlockTime = staker.getUnlockTime(user1);
        assertEq(
            newUnlockTime,
            block.timestamp + 60 days,
            "Unlock time should be updated to 60 days"
        );
    }

    function testClaimRewards() public {
        // Set up initial conditions
        uint256 initialStake = 10 ether;
        uint256 stakeDuration = 90 days; // Duration with a specific APR

        // Fund user and approve transfer to Staker contract
        vm.startPrank(user1);
        token.approve(address(staker), initialStake);
        staker.stake(initialStake, stakeDuration);
        vm.stopPrank();

        // Calculate expected reward after half the duration
        uint256 halfDuration = stakeDuration / 2;
        vm.warp(block.timestamp + halfDuration);

        // Fund the reward pool to cover expected claims
        uint256 rewardPoolAmount = 100 ether;
        vm.startPrank(owner);
        token.approve(address(staker), rewardPoolAmount);
        staker.fundRewards(rewardPoolAmount);
        vm.stopPrank();

        // Capture balances before claiming
        uint256 preClaimTokenBalance = token.balanceOf(user1);

        // User1 claims rewards
        vm.prank(user1);
        staker.claim();

        // Check the reward was paid out
        uint256 postClaimTokenBalance = token.balanceOf(user1);

        assertGt(
            postClaimTokenBalance,
            preClaimTokenBalance,
            "Token balance should increase after claiming"
        );

        // Verify the correct reward amount
        uint256 claimedReward = postClaimTokenBalance - preClaimTokenBalance;
        uint256 expectedReward = _calculateExpectedReward(
            initialStake,
            halfDuration,
            staker.getAPR(stakeDuration)
        );

        assertApproxEqAbs(
            claimedReward,
            expectedReward,
            0.0001 ether,
            "Claimed reward does not match the expected reward"
        );
    }

    function testAirdropAndStakeSuccess() public {
        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        uint256 totalAmount = 3 ether;
        uint256 lockDuration = 90 days;

        // Owner funds the contract to cover airdrop
        vm.startPrank(owner);
        token.approve(address(staker), totalAmount);
        staker.airdropAndStake(addresses, amounts, totalAmount, lockDuration);
        vm.stopPrank();

        // Check staked amounts and lock details
        for (uint i = 0; i < addresses.length; i++) {
            (uint256 amountStaked, , uint256 lockedFor, ) = staker
                .getUserStakeDetails(addresses[i]);
            assertEq(
                amountStaked,
                amounts[i],
                "Staked amount should match the airdropped amount"
            );
            assertEq(
                lockedFor,
                lockDuration,
                "Lock duration should match the specified duration"
            );
        }
    }

    function testAirdropAndStakeMismatchedArrays() public {
        address[] memory addresses = new address[](1);
        uint256[] memory amounts = new uint256[](2); // Deliberate mismatch
        addresses[0] = user1;
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        uint256 totalAmount = 3 ether;
        uint256 lockDuration = 90 days;

        vm.startPrank(owner);
        token.approve(address(staker), totalAmount);
        vm.expectRevert(abi.encodeWithSelector(LengthMismatch.selector));
        staker.airdropAndStake(addresses, amounts, totalAmount, lockDuration);
        vm.stopPrank();
    }

    function testAirdropAndStakeOnlyOwner() public {
        address[] memory addresses = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        addresses[0] = user1;
        amounts[0] = 1 ether;

        uint256 totalAmount = 1 ether;
        uint256 lockDuration = 90 days;

        vm.startPrank(user1);
        token.approve(address(staker), totalAmount);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1)
        );
        staker.airdropAndStake(addresses, amounts, totalAmount, lockDuration);
        vm.stopPrank();
    }

    // Helper function to calculate expected reward
    function _calculateExpectedReward(
        uint256 amountStaked,
        uint256 timeStaked,
        uint256 apr
    ) internal pure returns (uint256) {
        return (amountStaked * apr * timeStaked) / (365 days * 10000); // APR is multiplied by 100 to accommodate percentage base
    }
}
