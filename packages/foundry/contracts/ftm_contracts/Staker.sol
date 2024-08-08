// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//testing
import {IStaker} from "./IStaker.sol";
//TODO: remove console
import "forge-std/console.sol";

error InvalidDuration(uint256 duration);
error InvalidAmount(uint256 amount);
// error NotStaked(address accountff);
// error InvalidStakeAmount(uint256 amount);
error NoRewardsToClaim(address account);
error NoRewardsInTressury();
error Halted();
error LengthMismatch();

//TODO: make sure rewards calculation and decimals are correct
//TODO: ensure the token approvals when they are required
//TODO: Tests

contract Staker is IStaker, Ownable {
    using Address for address;
    using SafeERC20 for IERC20;

    struct UserStakeDetails {
        uint256 amountStaked;
        uint256 lockedAt;
        uint256 lockedFor;
        uint256 lastClaimTime;
    }

    IERC20 private _token; //MOST

    mapping(address => UserStakeDetails) private _userMapping;

    // duration to multiplier
    mapping(uint256 => uint256) private _multipliers;
    //duration to apr
    mapping(uint256 => uint256) private _aprs;
    // stores minimum amount of tokens required for each tier index
    uint256[5] private _tierIndex;
    //mapping(uint256 => uint256) private _tierIndex;

    uint256 private _rewardBalance;
    bool private _halted;

    event Stake(
        address indexed account,
        uint256 timestamp,
        uint256 duration,
        uint256 value
    );

    event Unstake(
        address indexed account,
        uint256 timestamp,
        uint256 value,
        uint256 unstaked
    );
    event RewardsFunded(address indexed funder, uint256 amount);
    event Claim(address indexed account, uint256 timestamp, uint256 reward);
    event MultiplierUpdated(uint256[] indexed newMultipliers);

    constructor(address tokenAddress) Ownable(msg.sender) {
        _token = IERC20(tokenAddress);

        //default multipliers of 1x,1.5x,2x and 3.5x
        _multipliers[30 days] = 10;
        _multipliers[60 days] = 15;
        _multipliers[90 days] = 20;
        _multipliers[180 days] = 35;

        //default APR values for different stake durations [1%,3%,5%,7%]
        _aprs[30 days] = 100;
        _aprs[60 days] = 300;
        _aprs[90 days] = 500;
        _aprs[180 days] = 700;

        //minimum tokens required for each tier index
        _tierIndex[0] = 30_000;
        _tierIndex[1] = 75_000;
        _tierIndex[2] = 250_000;
        _tierIndex[3] = 500_000;
        _tierIndex[4] = 1_000_000;
    }

    /**
     * @dev Fund the contract to reward stakers, can be funded by anyone
     * @notice - Access control: External
     */
    function fundRewards(uint256 amount) external {
        _token.safeTransferFrom(msg.sender, address(this), amount);
        _rewardBalance += amount;
        emit RewardsFunded(msg.sender, amount);
    }

    /**
     * @dev Stakes and locks the token for the given duration
     * @notice - Access control: External. Can only be called when app is nothalted
     */
    //REVIEW: do we need to force minimum amount of stake? so they atleast come under tear 1
    function stake(uint256 value, uint256 duration) external {
        _notHalted();
        _checkDuration(duration);

        UserStakeDetails storage userStakeDetails = _userMapping[msg.sender];

        uint256 oldUnlockAt = userStakeDetails.lockedAt +
            userStakeDetails.lockedFor;
        uint256 newUnlockAt = duration + block.timestamp; // x number of days from now

        if (newUnlockAt <= oldUnlockAt) {
            revert InvalidDuration(duration);
        }

        //perform staking and locking
        _token.safeTransferFrom(msg.sender, address(this), value);
        userStakeDetails.amountStaked += value;
        userStakeDetails.lockedAt = block.timestamp; //resets the lock time if user had staked before
        userStakeDetails.lockedFor = duration;

        emit Stake(msg.sender, block.timestamp, duration, value);
    }

    /**
     * @dev unstakes the value amount of tokens if enough balance and tokens are unlocked.
     If tokens are locked, user incurs a penalty of at max 50% if unstaked at half of unstake period
      and lineraly less if unstaked after half duration
      The peanlized tokens go back to the contract and provide APR to stakers
     * @notice - Access control: External. Can only be called when app is nothalted
     * @dev if the use unstakes with zero value, then only the accrued interest is withdrawn
     */

    function unstake(uint256 value) external {
        _notHalted();

        UserStakeDetails storage userStakeDetails = _userMapping[msg.sender];

        if (value > userStakeDetails.amountStaked) {
            revert InvalidAmount(value);
        }

        uint256 lockStartTime = userStakeDetails.lockedAt;
        uint256 lockDuration = userStakeDetails.lockedFor;
        uint256 unlockTime = lockStartTime + lockDuration;
        uint256 currentTime = block.timestamp;

        uint256 aprRewards = calculateRewards(
            userStakeDetails.amountStaked,
            lockStartTime,
            lockDuration,
            userStakeDetails.lastClaimTime
        );

        if (value == 0) {
            if (aprRewards <= 0) {
                revert NoRewardsToClaim(msg.sender);
            }

            if (_rewardBalance < aprRewards) {
                revert NoRewardsInTressury();
            }

            _rewardBalance -= aprRewards;
            _token.safeTransfer(msg.sender, aprRewards);
            //update the last time user claimed rewards
            userStakeDetails.lastClaimTime = block.timestamp;

            emit Claim(msg.sender, block.timestamp, aprRewards);
            return;
        }

        uint256 unstakeAmount = value;

        if (currentTime < unlockTime) {
            uint256 halfWayPoint = lockStartTime + (lockDuration / 2);
            if (currentTime <= halfWayPoint) {
                unstakeAmount = (value * 50) / 100; // Applying a 50% penalization for unstaking before the halfway point
            } else {
                // Time since the halfway point
                uint256 timeBeyondHalf = currentTime - halfWayPoint;

                // Calculate the reduction in penalty from 50% to 0%
                uint256 penaltyReduction = (50 * timeBeyondHalf) /
                    (lockDuration / 2);

                // Penalty decreases linearly from 50% to 0% over the second half of the lock period
                uint256 linearPenalty = 50 - penaltyReduction;

                // Calculate the unstake amount by applying the linearly reduced penalty
                unstakeAmount = (value * (100 - linearPenalty)) / 100;
            }
        }

        // Add the penalty to the reward balance, this will be recycled as additional staker APR
        _rewardBalance += (value - unstakeAmount);

        userStakeDetails.amountStaked -= value;

        if (userStakeDetails.amountStaked == 0) {
            userStakeDetails.lockedFor = 0;
            userStakeDetails.lockedAt = 0;
        }

        // if we have rewards to give to the user, add the rewards to unstakeAmount
        if (_rewardBalance >= aprRewards) {
            //reduce the apr_reward from the total reward balance
            _rewardBalance -= aprRewards;
            // add the reward to user unstakeAmount
            unstakeAmount += aprRewards;

            //update the last time user claimed rewards
            userStakeDetails.lastClaimTime = block.timestamp;
        }

        _token.safeTransfer(msg.sender, unstakeAmount);
        emit Unstake(msg.sender, block.timestamp, value, unstakeAmount);
    }

    /**
     * @dev Airdrop and stake MOST
     * @notice - Access control: Only Owner.
     */
    function airdropAndStake(
        address[] calldata _addresses,
        uint256[] calldata _amounts,
        uint256 _totalAmount,
        uint256 _lockDuration
    ) external onlyOwner {
        // require(
        //     _addresses.length == _amounts.length,
        //     "Array lengths do not match"
        // );

        if (_addresses.length == _amounts.length) {
            revert LengthMismatch();
        }
        _checkDuration(_lockDuration);
        // Transfer the total amount to this contract
        // require(
        //     _token.transferFrom(msg.sender, address(this), _totalAmount),
        //     "Transfer failed"
        // );

        _token.safeTransferFrom(msg.sender, address(this), _totalAmount);

        for (uint256 i = 0; i < _addresses.length; i++) {
            address user = _addresses[i];
            uint256 amount = _amounts[i];

            // Update the user's staking details
            _userMapping[user] = UserStakeDetails({
                lockedAt: block.timestamp,
                lockedFor: _lockDuration,
                lastClaimTime: block.timestamp,
                amountStaked: amount
            });
        }
    }

    /**
     * @dev to set the multipliers array. add values in whole decimals
     * @notice - Access control: onlyOwner, they can change the multiplier anytime
     */
    function setMultiplier(
        uint256 duration,
        uint256 multiplier
    ) external onlyOwner {
        _multipliers[duration] = multiplier;
    }

    /**
     * @dev to set the aprs array, add values in multiple of 100
     * @notice - Access control: onlyOwner, they can change the APR rewards anytime
     */
    function setAPRs(uint256 duration, uint256 apr) external onlyOwner {
        _aprs[duration] = apr;
    }

    function halt(bool status) external onlyOwner {
        _halted = status;
    }

    /**
     * @dev to allow devs to withdraw tokens from contract in case of a hack or any issue
     * @notice - Access control: onlyOwner, 
     TODO: do we want to make it more trustworthy to prove that we can't run away with the tokens
     */
    function withdraw(uint256 value) external onlyOwner {
        _token.safeTransfer(msg.sender, value);
    }

    /**
     * @dev staked balance of a user
     * @notice - Access control: Public.
     * @return - the number of MOST a user has staked
     */
    //
    function stakedBalance(address account) external view returns (uint256) {
        UserStakeDetails memory userStakeDetails = _userMapping[account];
        return userStakeDetails.amountStaked;
    }

    /**
     * @dev Get the unlock time of user tokens based on their lock time and total lock duration
     * @notice - Access control: External.
     * @return - time at which user tokens will be unlocked
     */
    function getUnlockTime(address account) external view returns (uint256) {
        UserStakeDetails memory userStakeDetails = _userMapping[account];
        return userStakeDetails.lockedAt + userStakeDetails.lockedFor;
    }

    /**
     * @dev Get the stake details of a user
     * @notice - Access control: External.
     * @return - the amount of tokens user has staked, when user locked tokens, how long they locked for, when user last claimed APR.
     */
    function getUserStakeDetails(
        address user
    ) external view returns (uint256, uint256, uint256, uint256) {
        UserStakeDetails memory details = _userMapping[user];
        return (
            details.amountStaked,
            details.lockedAt,
            details.lockedFor,
            details.lastClaimTime
        );
    }

    function getTierIndex(uint256 amount) external view returns (uint256) {
        for (uint256 i = 0; i < _tierIndex.length; i++) {
            if (amount < _tierIndex[i]) {
                return i;
            }
        }
        return _tierIndex.length;
    }

    /**
     * @dev user multiplier based on lock duration. If tokens are unlocked, reverts
     * @notice - Access control: External.
     * @return - multiplier based on locked duration of a user
     */

    function getMultiplier(uint256 duration) external view returns (uint256) {
        uint256 multiplier = _multipliers[duration];
        if (multiplier == 0) {
            revert InvalidDuration(duration);
        }
        return multiplier;
    }

    /**
     * @dev claim apr rewards
      The peanlized tokens go back to the contract and provide APR to stakers
     * @notice - Access control: External. Can be claimed anytime regardless of token unlocks
    //  */
    function claim() public {
        UserStakeDetails storage userStakeDetails = _userMapping[msg.sender];
        uint256 aprRewards = calculateRewards(
            userStakeDetails.amountStaked,
            userStakeDetails.lockedAt,
            userStakeDetails.lockedFor,
            userStakeDetails.lastClaimTime
        );

        if (aprRewards <= 0) {
            revert NoRewardsToClaim(msg.sender);
        }

        if (_rewardBalance < aprRewards) {
            revert NoRewardsInTressury();
        }

        _rewardBalance -= aprRewards;
        _token.safeTransfer(msg.sender, aprRewards);
        //update the last time user claimed rewards
        userStakeDetails.lastClaimTime = block.timestamp;

        emit Claim(msg.sender, block.timestamp, aprRewards);
    }

    /**
     * @dev calculates apr based on lock duration of an account. if duration is 0 (by default) it reverts
     * @notice - Access control: Public.
     * @return - apr based on locked duration of a user
     */
    function getAPR(uint256 duration) public view returns (uint256) {
        uint256 apr = _aprs[duration];
        if (apr == 0) {
            revert InvalidDuration(duration);
        }
        return apr;
    }

    /**
     * @dev calculates the apr amount the user has earned
     * @notice - Access control: Public
     * @return - user reward
     */
    //TODO: make sure the decimal math is right
    // @note: this will still work if pool has no money, do we want to revert or leave?
    function calculateRewards(
        uint256 amountStaked,
        uint256 lockedAt,
        uint256 lockedFor,
        uint256 lastClaimTime
    ) public view returns (uint256) {
        uint256 apr = getAPR(lockedFor);

        // if user has not claimed, lastRewardsClaim would be 0 otherwise it would be last blocktime when they claimed
        uint256 durationTime;
        if (lastClaimTime == 0) {
            // If the user hasn't claimed rewards before, calculate from the lock start time
            durationTime = block.timestamp - lockedAt;
        } else {
            // Calculate from the last claim time
            durationTime = block.timestamp - lastClaimTime;
        }
        // changed to 100_00 after tests
        return (amountStaked * apr * durationTime) / (365 days * 100_00);
    }

    //REVIEW: what was the virtual interest and total interest part?
    // function getTotalInterestAccrued(
    //     address user
    // ) external view returns (uint256 totalInterest) {
    //     UserStakeDetails memory userStakeDetails = _userMapping[user];
    //     uint256 apr = getAPR(userStakeDetails.lockedFor);
    //     uint256 timeElapsed = block.timestamp - userStakeDetails.lockedAt;

    //     totalInterest =
    //         (userStakeDetails.amountStaked * apr * timeElapsed) /
    //         (365 days * 100);
    // }

    function _notHalted() private view {
        if (_halted) {
            revert Halted();
        }
    }

    function _checkDuration(uint256 duration) private pure {
        if (
            duration != 30 days &&
            duration != 60 days &&
            duration != 90 days &&
            duration != 180 days
        ) {
            revert InvalidDuration(duration);
        }
    }
}
