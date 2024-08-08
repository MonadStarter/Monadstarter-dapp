// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MOST is ERC20 {
    constructor(uint256 initialSupply) ERC20("MOST", "MonadStarter") {
        _mint(msg.sender, initialSupply);
    }
}
