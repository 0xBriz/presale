// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDepositToken is ERC20 {
    constructor(uint256 _initialMintAmount)
        public
        ERC20("Get Moist", "GETMOIST")
    {
        _mint(msg.sender, _initialMintAmount);
    }
}
