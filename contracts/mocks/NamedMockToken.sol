// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NamedMockToken is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialMintAmount
    ) public ERC20(_name, _symbol) {
        _mint(msg.sender, _initialMintAmount);
    }
}
