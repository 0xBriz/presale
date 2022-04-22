// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ITokenOffering {
    function depositPool(uint256 _amount, uint8 _pid) external;

    function harvestPool(uint8 _pid) external;

    function emergencyRefund(uint8 _pid) external;

    function setPool(
        uint256 _offeringAmountPool,
        uint256 _raisingAmountPool,
        uint256 _limitPerUserInLP,
        uint8 _pid,
        address _lpToken,
        bool _hasWhitelist,
        bool _isStopDeposit
    ) external;

    function viewPoolInformation(uint8 _pid)
        external
        view
        returns (
            uint256 raisingAmountPool,
            uint256 offeringAmountPool,
            uint256 limitPerUserInLP,
            uint256 totalAmountPool,
            address lpToken,
            bool hasWhitelist,
            bool isStopDeposit
        );

    function viewUserAllocationPools(address _user, uint8[] calldata _pids)
        external
        view
        returns (uint256[] memory);

    function viewUserOfferingAndRefundingAmountsForPools(
        address _user,
        uint8[] calldata _pids
    ) external view returns (uint256[2][] memory);
}
