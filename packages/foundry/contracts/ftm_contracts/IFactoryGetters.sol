// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFactoryGetters {
    function getFeeAddress() external view returns (address);

    function getStakerAddress() external view returns (address);
}
