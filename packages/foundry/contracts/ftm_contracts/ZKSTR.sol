// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ZKSTR is ERC20 {
    constructor(uint256 initialSupply) ERC20("ZK Starter", "ZKSTR") {
        _mint(msg.sender, initialSupply);
    }
}
