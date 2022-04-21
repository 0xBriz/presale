// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./oz/Ownable.sol";

contract Whitelisted is Ownable {
    bool isWhitelistStarted = false;

    mapping(address => uint8) public whitelist;

    modifier onlyWhitelisted() {
        require(isWhitelisted(msg.sender));
        _;
    }

    mapping(address => bool) internal managers;

    modifier onlyManager() {
        require(managers[msg.sender] == true, "Not a manager");
        _;
    }

    function getWhitelistedZone(address _purchaser)
        public
        view
        returns (uint8)
    {
        return whitelist[_purchaser] > 0 ? whitelist[_purchaser] : 0;
    }

    function isWhitelisted(address _purchaser) public view returns (bool) {
        return whitelist[_purchaser] > 0;
    }

    function joinWhitelist(address _purchaser, uint8 _zone) public {
        require(isWhitelistStarted == true, "Whitelist not started");

        whitelist[_purchaser] = _zone;
    }

    function deleteFromWhitelist(address _purchaser) public onlyManager {
        whitelist[_purchaser] = 0;
    }

    function addToWhitelist(address[] memory purchasers, uint8 _zone)
        public
        onlyManager
    {
        for (uint256 i = 0; i < purchasers.length; i++) {
            whitelist[purchasers[i]] = _zone;
        }
    }

    function startWhitelist(bool _status) public onlyManager {
        isWhitelistStarted = _status;
    }

    function setManager(address _who, bool value) external onlyManager {
        managers[_who] = value;
    }
}
