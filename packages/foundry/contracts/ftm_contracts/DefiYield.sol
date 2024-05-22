// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DefiYield is ERC20 {
    constructor() ERC20("Defi Yield", "DEFI") {
        _mint(0xA7C015519fAdeD4Be69310390CFD1f8E07d5eBF7, 416669 * 10 ** decimals());
    }

}
