// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IFactoryGetters {
    function getFeeAddress() external view returns(address);
    function getLauncherToken() external view returns(address);
    function getStakerAddress() external view returns(address);
}