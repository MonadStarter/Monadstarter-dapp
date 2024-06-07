// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EscrowToken is ERC20, Ownable {
    constructor() ERC20("esZKSTR", "esZKSTR") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    // Override transfer functions to make the token non-transferable
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(
            from == address(0) || to == address(0),
            "EscrowToken: transfer disabled"
        );
        super._beforeTokenTransfer(from, to, amount);
    }
}
