// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./oz/ReentrancyGuard.sol";
import "./oz/Ownable.sol";
import "./oz/SafeMath.sol";
import "./oz/SafeERC20.sol";
import "./oz/Math.sol";

import "./interfaces/ITokenOffering.sol";
import "./Whitelisted.sol";

contract InitialTokenOffering is
    ITokenOffering,
    ReentrancyGuard,
    Ownable,
    Whitelisted
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public protocolToken;

    IERC20 public offeringToken;

    uint8 public numberPools;

    uint256 public startBlock;

    uint256 public endBlock;

    bool public isEmergencyRefund = false;

    mapping(uint8 => PoolCharacteristics) private _poolInformation;

    mapping(address => mapping(uint8 => UserInfo)) private _userInfo;

    struct PoolCharacteristics {
        uint256 raisingAmountPool; // amount of tokens raised for the pool (in LP tokens)
        uint256 offeringAmountPool; // amount of tokens offered for the pool (in offeringTokens)
        uint256 limitPerUserInLP; // limit of tokens per user (if 0, it is ignored)
        uint256 maxCommitRatio; // max commit base on protocol token holding
        uint256 minProtocolToJoin; // Can zero these out
        uint256 totalAmountPool; // total amount pool deposited (in LP tokens)
        uint256 sumTaxesOverflow; // total taxes collected (starts at 0, increases with each harvest if overflow)
        address lpToken; // lp token for this pool
        bool hasTax; // tax on the overflow (if any, it works with _calculateTaxOverflow)
        bool hasWhitelist; // only for whitelist
        bool isStopDeposit;
        bool hasOverflow; // Can deposit overflow
    }

    struct UserInfo {
        uint256 amountPool; // How many tokens the user has provided for pool
        bool claimedPool; // Whether the user has claimed (default: false) for pool
    }

    mapping(address => bool) private managers;

    modifier onlyManager() {
        require(managers[msg.sender] == true, "Not a manager");
        _;
    }

    modifier notContract() {
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    constructor(
        uint8 _numberPools,
        uint256 _startBlockFromNow, // dependent on blocktime
        uint256 _endBlockFromNow, // dependent on blocktime
        address _protocolTokenAddress
    ) public {
        require(_numberPools > 0, "_numberPools > 0");
        require(
            _protocolTokenAddress != address(0),
            "0x0 _protocolTokenAddress"
        );

        numberPools = _numberPools;
        protocolToken = _protocolTokenAddress;

        // startBlock = block.number + 201600; // 7 days
        // endBlock = block.number + 403200; // 14 days

        startBlock = block.number + _startBlockFromNow;
        endBlock = block.number + _endBlockFromNow;

        managers[msg.sender] = true;
    }

    /* ================== MUTATION FUNCTIONS =================== */

    function depositPool(uint256 _amount, uint8 _pid)
        external
        override
        nonReentrant
        notContract
    {
        require(!isEmergencyRefund, "In emergency status");
        require(_pid < numberPools, "Invalid pool");
        require(_amount > 0, "Cant deposit zero");

        PoolCharacteristics memory pool = _poolInformation[_pid];

        // Check if the pool has a limit per user
        uint256 protocolHolding = IERC20(protocolToken).balanceOf(msg.sender);
        uint256 limitPerUserInLP = pool.limitPerUserInLP;

        require(
            protocolHolding >= pool.minProtocolToJoin,
            "Not meet min protocol"
        );
        require(
            pool.offeringAmountPool > 0 && pool.raisingAmountPool > 0,
            "Pool not set"
        );
        require(
            !pool.hasWhitelist ||
                (pool.hasWhitelist && isWhitelisted(msg.sender)),
            "Not whitelisted"
        );
        require(!pool.isStopDeposit, "Pool is stopped");
        require(
            block.number > startBlock && block.number < endBlock,
            "Not in time"
        );
        require(
            pool.hasOverflow ||
                pool.totalAmountPool.add(_amount) <= pool.raisingAmountPool,
            "Pool is full"
        );

        // Transfers funds to this contract
        uint256 beforeAmount = IERC20(pool.lpToken).balanceOf(address(this));
        IERC20(pool.lpToken).safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        uint256 increaseAmount = IERC20(pool.lpToken)
            .balanceOf(address(this))
            .sub(beforeAmount);

        require(increaseAmount > 0, "Error amount");

        // Update the user status
        _userInfo[msg.sender][_pid].amountPool = _userInfo[msg.sender][_pid]
            .amountPool
            .add(increaseAmount);

        if (pool.maxCommitRatio > 0) {
            uint256 newLimit = protocolHolding.mul(pool.maxCommitRatio).div(
                10000
            );
            if (
                limitPerUserInLP == 0 ||
                (newLimit > 0 && newLimit < limitPerUserInLP)
            ) {
                limitPerUserInLP = newLimit;
            }

            require(
                _userInfo[msg.sender][_pid].amountPool <= limitPerUserInLP,
                "New amount above user max ratio"
            );
        }

        if (limitPerUserInLP > 0) {
            // Checks whether the limit has been reached
            require(
                _userInfo[msg.sender][_pid].amountPool <= limitPerUserInLP,
                "New amount above user limit"
            );
        }

        // Updates the totalAmount for pool
        _poolInformation[_pid].totalAmountPool = _poolInformation[_pid]
            .totalAmountPool
            .add(increaseAmount);

        emit Deposit(msg.sender, increaseAmount, _pid);
    }

    function harvestPool(uint8 _pid)
        external
        override
        nonReentrant
        notContract
    {
        require(!isEmergencyRefund, "In emergency status");
        require(block.number > endBlock, "Too early to harvest");
        require(_pid < numberPools, "Non valid pool id");
        require(
            _userInfo[msg.sender][_pid].amountPool > 0,
            "Did not participate"
        );
        require(!_userInfo[msg.sender][_pid].claimedPool, "Has harvested");

        // nonReentrant but still follow practices
        _userInfo[msg.sender][_pid].claimedPool = true;

        // Initialize the variables for offering, refunding user amounts, and tax amount
        uint256 offeringTokenAmount;
        uint256 refundingTokenAmount;
        uint256 userTaxOverflow;

        (
            offeringTokenAmount,
            refundingTokenAmount,
            userTaxOverflow
        ) = _calculateOfferingAndRefundingAmountsPool(msg.sender, _pid);

        // Increment the sumTaxesOverflow
        if (userTaxOverflow > 0) {
            _poolInformation[_pid].sumTaxesOverflow = _poolInformation[_pid]
                .sumTaxesOverflow
                .add(userTaxOverflow);
        }

        // Transfer these tokens back to the user if quantity > 0
        if (offeringTokenAmount > 0) {
            offeringToken.safeTransfer(
                address(msg.sender),
                offeringTokenAmount
            );
        }

        uint256 usedFund = _userInfo[msg.sender][_pid].amountPool;

        if (refundingTokenAmount > 0) {
            IERC20(_poolInformation[_pid].lpToken).safeTransfer(
                address(msg.sender),
                refundingTokenAmount
            );
            usedFund = usedFund.sub(refundingTokenAmount);
        }

        emit Harvest(
            msg.sender,
            offeringTokenAmount,
            refundingTokenAmount,
            _pid
        );
    }

    function emergencyRefund(uint8 _pid)
        external
        override
        nonReentrant
        notContract
    {
        require(isEmergencyRefund, "Not allowed");
        require(_pid < numberPools, "Non valid pool id");
        require(
            _userInfo[msg.sender][_pid].amountPool > 0,
            "Did not participate"
        );
        require(!_userInfo[msg.sender][_pid].claimedPool, "Has harvested");

        _userInfo[msg.sender][_pid].claimedPool = true;

        uint256 userFund = _userInfo[msg.sender][_pid].amountPool;

        IERC20(_poolInformation[_pid].lpToken).safeTransfer(
            address(msg.sender),
            userFund
        );
        emit EmergencyRefund(msg.sender, userFund, _pid);
    }

    function finalWithdraw() external onlyManager {
        for (uint8 i = 0; i < numberPools; i++) {
            IERC20 lpToken = IERC20(_poolInformation[i].lpToken);

            uint256 amount = lpToken.balanceOf(address(this));

            uint256 canWithdraw = Math.min(
                _poolInformation[i].totalAmountPool,
                _poolInformation[i].raisingAmountPool
            );

            if (amount > canWithdraw) {
                amount = canWithdraw;
            }

            if (amount > 0) {
                lpToken.safeTransfer(address(msg.sender), amount);
            }
        }

        emit AdminWithdraw(address(msg.sender));
    }

    function emergencyTokenWithdraw(address _token, uint256 _amount)
        external
        onlyManager
    {
        IERC20 token = IERC20(_token);

        uint256 amount = _amount;

        if (amount > token.balanceOf(address(this))) {
            amount = token.balanceOf(address(this));
        }

        token.safeTransfer(address(msg.sender), amount);
        emit EmergencyTokenWithdraw(address(msg.sender), _token, amount);
    }

    /* =================== VIEW/HELPERS ===================== */

    function viewPoolInformation(uint8 _pid)
        external
        view
        override
        returns (
            uint256 raisingAmountPool,
            uint256 offeringAmountPool,
            uint256 limitPerUserInLP,
            uint256 maxCommitRatio,
            uint256 minProtocolToJoin,
            uint256 totalAmountPool,
            uint256 sumTaxesOverflow,
            address lpToken,
            bool hasTax,
            bool hasWhitelist,
            bool isStopDeposit,
            bool hasOverflow
        )
    {
        PoolCharacteristics memory pool = _poolInformation[_pid];
        raisingAmountPool = pool.raisingAmountPool;
        offeringAmountPool = pool.offeringAmountPool;
        limitPerUserInLP = pool.limitPerUserInLP;
        maxCommitRatio = pool.maxCommitRatio;
        minProtocolToJoin = pool.minProtocolToJoin;
        totalAmountPool = pool.totalAmountPool;
        sumTaxesOverflow = pool.sumTaxesOverflow;
        lpToken = pool.lpToken;
        hasTax = pool.hasTax;
        hasWhitelist = pool.hasWhitelist;
        isStopDeposit = pool.isStopDeposit;
        hasOverflow = pool.hasOverflow;
    }

    function viewPoolTaxRateOverflow(uint8 _pid)
        external
        view
        override
        returns (uint256)
    {
        if (!_poolInformation[_pid].hasTax) {
            return 0;
        } else {
            return
                _calculateTaxOverflow(
                    _poolInformation[_pid].totalAmountPool,
                    _poolInformation[_pid].raisingAmountPool
                );
        }
    }

    function viewUserAllocationPools(address _user, uint8[] calldata _pids)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256[] memory allocationPools = new uint256[](_pids.length);
        for (uint8 i = 0; i < _pids.length; i++) {
            allocationPools[i] = _getUserAllocationPool(_user, _pids[i]);
        }
        return allocationPools;
    }

    function viewUserInfo(address _user, uint8[] calldata _pids)
        external
        view
        override
        returns (uint256[] memory, bool[] memory)
    {
        uint256[] memory amountPools = new uint256[](_pids.length);
        bool[] memory statusPools = new bool[](_pids.length);

        for (uint8 i = 0; i < numberPools; i++) {
            amountPools[i] = _userInfo[_user][i].amountPool;
            statusPools[i] = _userInfo[_user][i].claimedPool;
        }
        return (amountPools, statusPools);
    }

    function viewUserOfferingAndRefundingAmountsForPools(
        address _user,
        uint8[] calldata _pids
    ) external view override returns (uint256[3][] memory) {
        uint256[3][] memory amountPools = new uint256[3][](_pids.length);

        for (uint8 i = 0; i < _pids.length; i++) {
            uint256 userOfferingAmountPool;
            uint256 userRefundingAmountPool;
            uint256 userTaxAmountPool;

            if (_poolInformation[_pids[i]].raisingAmountPool > 0) {
                (
                    userOfferingAmountPool,
                    userRefundingAmountPool,
                    userTaxAmountPool
                ) = _calculateOfferingAndRefundingAmountsPool(_user, _pids[i]);
            }

            amountPools[i] = [
                userOfferingAmountPool,
                userRefundingAmountPool,
                userTaxAmountPool
            ];
        }
        return amountPools;
    }

    function _calculateOfferingAndRefundingAmountsPool(
        address _user,
        uint8 _pid
    )
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 userOfferingAmount;
        uint256 userRefundingAmount;
        uint256 taxAmount;

        if (
            _poolInformation[_pid].totalAmountPool >
            _poolInformation[_pid].raisingAmountPool
        ) {
            // Calculate allocation for the user
            uint256 allocation = _getUserAllocationPool(_user, _pid);

            // Calculate the offering amount for the user based on the offeringAmount for the pool
            userOfferingAmount = _poolInformation[_pid]
                .offeringAmountPool
                .mul(allocation)
                .div(1e12);

            // Calculate the payAmount
            uint256 payAmount = _poolInformation[_pid]
                .raisingAmountPool
                .mul(allocation)
                .div(1e12);

            // Calculate the pre-tax refunding amount
            userRefundingAmount = _userInfo[_user][_pid].amountPool.sub(
                payAmount
            );

            // Retrieve the tax rate
            if (_poolInformation[_pid].hasTax) {
                uint256 taxOverflow = _calculateTaxOverflow(
                    _poolInformation[_pid].totalAmountPool,
                    _poolInformation[_pid].raisingAmountPool
                );

                // Calculate the final taxAmount
                taxAmount = userRefundingAmount.mul(taxOverflow).div(1e12);

                // Adjust the refunding amount
                userRefundingAmount = userRefundingAmount.sub(taxAmount);
            }
        } else {
            userRefundingAmount = 0;
            taxAmount = 0;
            // _userInfo[_user] / (raisingAmount / offeringAmount)
            userOfferingAmount = _userInfo[_user][_pid]
                .amountPool
                .mul(_poolInformation[_pid].offeringAmountPool)
                .div(_poolInformation[_pid].raisingAmountPool);
        }
        return (userOfferingAmount, userRefundingAmount, taxAmount);
    }

    function _calculateTaxOverflow(
        uint256 _totalAmountPool,
        uint256 _raisingAmountPool
    ) internal pure returns (uint256) {
        uint256 ratioOverflow = _totalAmountPool.div(_raisingAmountPool);

        if (ratioOverflow >= 500) {
            return 2000000000; // 0.2%
        } else if (ratioOverflow >= 250) {
            return 2500000000; // 0.25%
        } else if (ratioOverflow >= 100) {
            return 3000000000; // 0.3%
        } else if (ratioOverflow >= 50) {
            return 5000000000; // 0.5%
        } else {
            return 10000000000; // 1%
        }
    }

    function _getUserAllocationPool(address _user, uint8 _pid)
        internal
        view
        returns (uint256)
    {
        if (_poolInformation[_pid].totalAmountPool > 0) {
            return
                _userInfo[_user][_pid].amountPool.mul(1e18).div(
                    _poolInformation[_pid].totalAmountPool.mul(1e6)
                );
        } else {
            return 0;
        }
    }

    /* =============== ADMIN FUNCTIONS ================ */

    function setManager(address _who, bool value) external onlyManager {
        managers[_who] = true;
    }

    function setProtocolToken(address _token) external onlyManager {
        protocolToken = _token;
    }

    function setPool(
        uint256 _offeringAmountPool,
        uint256 _raisingAmountPool,
        uint256 _limitPerUserInLP,
        uint256 _maxCommitRatio,
        uint256 _minProtocolToJoin,
        uint8 _pid,
        address _lpToken,
        bool _hasTax,
        bool _hasWhitelist,
        bool _isStopDeposit,
        bool _hasOverflow
    ) external override onlyManager {
        require(_pid < numberPools, "Pool does not exist");
        require(_lpToken != address(0), "0x0 _lpToken");

        //Dont change offeringAmountPool, raisingAmountPool if pool is exist
        _poolInformation[_pid].offeringAmountPool = _offeringAmountPool;
        _poolInformation[_pid].raisingAmountPool = _raisingAmountPool;

        _poolInformation[_pid].limitPerUserInLP = _limitPerUserInLP;
        _poolInformation[_pid].maxCommitRatio = _maxCommitRatio;
        _poolInformation[_pid].minProtocolToJoin = _minProtocolToJoin;

        _poolInformation[_pid].lpToken = _lpToken;
        _poolInformation[_pid].hasTax = _hasTax;
        _poolInformation[_pid].hasWhitelist = _hasWhitelist;
        _poolInformation[_pid].isStopDeposit = _isStopDeposit;
        _poolInformation[_pid].hasOverflow = _hasOverflow;

        emit PoolParametersSet(
            _offeringAmountPool,
            _raisingAmountPool,
            _pid,
            _lpToken,
            _hasTax,
            _hasWhitelist,
            _isStopDeposit
        );
    }

    function setNumberPools(uint8 _numberPools) external onlyManager {
        require(_numberPools > numberPools, "Invalid numberPools");
        numberPools = _numberPools;
    }

    function updateStartAndEndBlocks(uint256 _startBlock, uint256 _endBlock)
        external
        onlyManager
    {
        require(
            _startBlock < _endBlock,
            "New startBlock must be lower than new endBlock"
        );
        require(
            block.number < _startBlock,
            "New startBlock must be higher than current block"
        );

        if (block.number < startBlock) {
            startBlock = _startBlock;
        }

        endBlock = _endBlock;

        emit NewStartAndEndBlocks(startBlock, _endBlock);
    }

    function stopDepositPool(uint8 _pid, bool status) public onlyManager {
        require(_pid < numberPools, "Pool does not exist");
        require(
            _poolInformation[_pid].isStopDeposit != status,
            "Invalid status"
        );

        _poolInformation[_pid].isStopDeposit = status;
    }

    function startSale() external onlyManager {
        require(block.number < startBlock, "ITO Started");

        startBlock = block.number;
    }

    function endSale() external onlyManager {
        endBlock = block.number;
    }

    function setOfferingToken(IERC20 _offeringToken) public onlyManager {
        offeringToken = _offeringToken;
    }

    function setEmergencyRefund() public onlyManager {
        require(!isEmergencyRefund, "Cant change");

        isEmergencyRefund = true;
    }

    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    event AdminWithdraw(address indexed user);
    event EmergencyTokenWithdraw(
        address indexed user,
        address token,
        uint256 amount
    );
    event Deposit(address indexed user, uint256 amount, uint8 indexed pid);
    event Harvest(
        address indexed user,
        uint256 offeringAmount,
        uint256 excessAmount,
        uint8 indexed pid
    );
    event EmergencyRefund(
        address indexed user,
        uint256 userFund,
        uint8 indexed _pid
    );
    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event PoolParametersSet(
        uint256 offeringAmountPool,
        uint256 raisingAmountPool,
        uint8 pid,
        address lpToken,
        bool hasTax,
        bool hasWhitelist,
        bool isStopDeposit
    );
}
