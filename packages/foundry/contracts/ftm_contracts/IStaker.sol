// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
interface IStaker {
    function stakedBalance(address account) external view returns (uint256);
    function unlockTime(address account) external view returns (uint256);
    function getUserStakeDetails(
        address user
    ) external view returns (uint256, uint256, uint256, uint256);
    function fund_rewards(uint256 amount) external;
    function getAPR(uint256 duration) external view returns (uint256);
    function getTierIndex(uint256 amount) external view returns (uint256);
    function getMultiplier(uint256 duration) external view returns (uint256);
    function stake(uint256 value, uint256 duration) external;
    function unstake(uint256 value) external;
    function claim() external;
    function calculateRewards(
        uint256 amountStaked,
        uint256 lockedAt,
        uint256 lockedFor,
        uint256 lastClaimTime
    ) external view returns (uint256);
    function getTotalInterestAccrued(
        address user
    ) external view returns (uint256 totalInterest);
    function airdropAndStake(
        address[] calldata _addresses,
        uint256[] calldata _amounts,
        uint256 _totalAmount,
        uint256 _lockDuration
    ) external;
    function set_multiplier(uint256 duration, uint256 multiplier) external;
    function set_APRs(uint256 duration, uint256 apr) external;
    function halt(bool status) external;
    function withdraw(uint256 value) external;
}
