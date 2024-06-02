// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staker is Context, Ownable {
    using Address for address;
    using SafeERC20 for IERC20;

    enum Duration {
        Days_30,
        Days_60,
        Days_90,
        Days_180
    }

    IERC20 _token;
    mapping(address => uint256) _balances;
    mapping(address => uint256) _lockTime;
    mapping(address => uint256) _lockDuration;
    uint256[] _multipliers;
    bool halted;

    event Stake(
        address indexed account,
        uint256 timestamp,
        uint256 duration,
        uint256 value
    );
    event Unstake(address indexed account, uint256 timestamp, uint256 value);

    constructor(address _tokenAddress) Ownable(_msgSender()) {
        _token = IERC20(_tokenAddress);
        _multipliers = [10, 15, 20, 35]; //default multipliers of 1x,1.5x,2x and 3.5x
    }

    function stakedBalance(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev Get the unlock time of user tokens based on their lock time and total lock duration
     * @notice - Access control: External.
     * @return - time at which user tokens will be unlocked
     */
    function unlockTime(address account) public view returns (uint256) {
        return _lockTime[account] + _lockDuration[account];
    }

    function duration_to_time(Duration duration) public pure returns (uint256) {
        if (duration == Duration.Days_30) {
            return 30 days;
        } else if (duration == Duration.Days_60) {
            return 60 days;
        } else if (duration == Duration.Days_90) {
            return 90 days;
        } else if (duration == Duration.Days_180) {
            return 180 days;
        }
        revert("Invalid duration");
    }

    /**
     * @dev Stakes and locks the token for the given duration
     * @notice - Access control: External. Can only be called when app is nothalted
     * TODO: Make sure that user can only stake in the duration they previously staked or they can move to a higher duration
     */
    function stake(uint256 value, Duration duration) external notHalted {
        require(value > 0, "stake value should be greater than 0");
        uint256 duration_time = duration_to_time(duration);
        uint256 unlock_time = duration_time + block.timestamp; // x number of days from now

        //allows locking if the new time is more than previous locked time
        if (unlock_time > unlockTime(_msgSender())) {
            //perform staking and locking
            _token.safeTransferFrom(_msgSender(), address(this), value);
            _balances[_msgSender()] += value;
            _lockTime[_msgSender()] = block.timestamp; //TODO: if user stakes more in future, the time would get reset, do we need this
            _lockDuration[_msgSender()] = duration_time;

            emit Stake(_msgSender(), block.timestamp, duration_time, value);
        } else {
            revert("new duration cannot be less than previous duration");
        }
    }
    //TODO: if there a scenario where we need to reset lockDuration and time?
    // let's say use stakes and after it's lock duration, unstakes.
    // lockDuration and lockTime would be based on previous values
    function unstake(uint256 value) external lockable {
        require(
            _balances[_msgSender()] >= value,
            "Staker: insufficient staked balance"
        );
        // if this works, it means all tokens are unlocked, so reset _lockDuration

        _balances[_msgSender()] -= value;
        _token.safeTransfer(_msgSender(), value);
        emit Unstake(_msgSender(), block.timestamp, value);
    }

    // returns user multiplier based on lock duration. If tokens are unlocked, multiplier is 0 right now
    function user_multiplier(address account) external returns (uint256) {
        // if the user tokens are unlocked, they don't earn a multiplier
        if (unlockTime(account) < block.timestamp) {
            return 0;
        }

        uint256 lockDuration = _lockDuration[account];

        if (lockDuration == 30 days) {
            return _multipliers[0];
        } else if (lockDuration == 60 days) {
            return _multipliers[1];
        } else if (lockDuration == 90 days) {
            return _multipliers[2];
        } else if (lockDuration == 180 days) {
            return _multipliers[3];
        }
        return 0;
    }

    /**
     * @dev to set the multipliers array. add values in whole decimals
     * @notice - Access control: onlyOwner, they can change the multiplier anytime
     */
    function set_multiplier(uint256[] calldata multipliers) external onlyOwner {
        _multipliers = multipliers;
    }

    function halt(bool status) external onlyOwner {
        halted = status;
    }

    // ensures that tokens are unlocked for the user
    modifier lockable() {
        require(
            unlockTime(_msgSender()) <= block.timestamp,
            "Staker: account is locked"
        );
        _;
    }

    modifier notHalted() {
        require(!halted, "Staker: Deposits are paused");
        _;
    }
}
