// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IStaker {
    function stake(uint256 value, uint256 duration) external;
    function unstake(uint256 value) external;
    function claim() external;
    function fundRewards(uint256 amount) external;
    function airdropAndStake(
        address[] calldata _addresses,
        uint256[] calldata _amounts,
        uint256 _totalAmount,
        uint256 _lockDuration
    ) external;
    function setMultiplier(uint256 duration, uint256 multiplier) external;
    function setAPRs(uint256 duration, uint256 apr) external;
    function halt(bool status) external;
    function withdraw(uint256 value) external;

    function stakedBalance(address account) external view returns (uint256);
    function getUnlockTime(address account) external view returns (uint256);
    function getUserStakeDetails(
        address user
    ) external view returns (uint256, uint256, uint256, uint256);
    function getAPR(uint256 duration) external view returns (uint256);
    function getTierIndex(uint256 amount) external view returns (uint256);
    function getMultiplier(uint256 duration) external view returns (uint256);
    function calculateRewards(
        uint256 amountStaked,
        uint256 lockedAt,
        uint256 lockedFor,
        uint256 lastClaimTime
    ) external view returns (uint256);
    // function getTotalInterestAccrued(
    //     address user
    // ) external view returns (uint256 totalInterest);
}
