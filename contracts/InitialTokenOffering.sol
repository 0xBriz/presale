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
        uint256 totalAmountPool; // total amount pool deposited (in LP tokens)
        address lpToken; // lp token for this pool
        bool hasWhitelist; // only for whitelist
        bool isStopDeposit;
    }

    struct UserInfo {
        uint256 amountPool; // How many tokens the user has provided for pool
        bool claimedPool; // Whether the user has claimed (default: false) for pool
    }

    modifier notContract() {
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    constructor(uint8 _numberPools, address _offeringTokenAddress) public {
        require(_numberPools > 0, "_numberPools > 0");
        require(
            _offeringTokenAddress != address(0),
            "0x0 _offeringTokenAddress"
        );

        numberPools = _numberPools;

        // Start block can be set by admin when ready
        startBlock = block.number + 28800; // ~1 day BSC
        // End block can updated by admin
        endBlock = block.number + 86400; // ~3 days BSC

        offeringToken = IERC20(_offeringTokenAddress);

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
        uint256 limitPerUserInLP = pool.limitPerUserInLP;

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

        // Initialize the variables for offering, refunding user amounts
        uint256 offeringTokenAmount;
        uint256 refundingTokenAmount;

        (
            offeringTokenAmount,
            refundingTokenAmount
        ) = _calculateOfferingAndRefundingAmountsPool(msg.sender, _pid);

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

    /**
     * @dev Allows user to take back there deposits if `isEmergencyRefund` has been set by admins
     */
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

    /* =================== VIEW/HELPERS ===================== */

    function viewPoolInformation(uint8 _pid)
        external
        view
        override
        returns (
            uint256 raisingAmountPool,
            uint256 offeringAmountPool,
            uint256 limitPerUserInLP,
            uint256 totalAmountPool,
            address lpToken,
            bool hasWhitelist,
            bool isStopDeposit
        )
    {
        PoolCharacteristics memory pool = _poolInformation[_pid];
        raisingAmountPool = pool.raisingAmountPool;
        offeringAmountPool = pool.offeringAmountPool;
        limitPerUserInLP = pool.limitPerUserInLP;
        totalAmountPool = pool.totalAmountPool;
        lpToken = pool.lpToken;
        hasWhitelist = pool.hasWhitelist;
        isStopDeposit = pool.isStopDeposit;
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
    ) external view override returns (uint256[2][] memory) {
        uint256[2][] memory amountPools = new uint256[2][](_pids.length);

        for (uint8 i = 0; i < _pids.length; i++) {
            uint256 userOfferingAmountPool;
            uint256 userRefundingAmountPool;

            if (_poolInformation[_pids[i]].raisingAmountPool > 0) {
                (
                    userOfferingAmountPool,
                    userRefundingAmountPool
                ) = _calculateOfferingAndRefundingAmountsPool(_user, _pids[i]);
            }

            amountPools[i] = [userOfferingAmountPool, userRefundingAmountPool];
        }
        return amountPools;
    }

    function _calculateOfferingAndRefundingAmountsPool(
        address _user,
        uint8 _pid
    ) internal view returns (uint256, uint256) {
        uint256 userOfferingAmount;
        uint256 userRefundingAmount;

        if (
            _poolInformation[_pid].totalAmountPool >
            _poolInformation[_pid].raisingAmountPool
        ) {
            // Calculate allocation for the user
            uint256 usersAllocation = _getUserAllocationPool(_user, _pid);

            // Calculate the offering amount for the user based on the offeringAmount for the pool
            userOfferingAmount = _poolInformation[_pid]
                .offeringAmountPool
                .mul(usersAllocation)
                .div(1e12);

            // Calculate the payAmount
            uint256 payAmount = _poolInformation[_pid]
                .raisingAmountPool
                .mul(usersAllocation)
                .div(1e12);

            // Calculate the pre-tax refunding amount
            userRefundingAmount = _userInfo[_user][_pid].amountPool.sub(
                payAmount
            );
        } else {
            userRefundingAmount = 0;
            // _userInfo[_user] / (raisingAmount / offeringAmount)
            userOfferingAmount = _userInfo[_user][_pid]
                .amountPool
                .mul(_poolInformation[_pid].offeringAmountPool)
                .div(_poolInformation[_pid].raisingAmountPool);
        }
        return (userOfferingAmount, userRefundingAmount);
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

    function setPool(
        uint256 _offeringAmountPool,
        uint256 _raisingAmountPool,
        uint256 _limitPerUserInLP,
        uint8 _pid,
        address _lpToken,
        bool _hasWhitelist,
        bool _isStopDeposit
    ) external override onlyManager {
        require(_pid < numberPools, "Pool does not exist");
        require(_lpToken != address(0), "0x0 _lpToken");

        // Dont change offeringAmountPool, raisingAmountPool if pool is exist
        _poolInformation[_pid].offeringAmountPool = _offeringAmountPool;
        _poolInformation[_pid].raisingAmountPool = _raisingAmountPool;

        _poolInformation[_pid].limitPerUserInLP = _limitPerUserInLP;

        _poolInformation[_pid].lpToken = _lpToken;
        _poolInformation[_pid].hasWhitelist = _hasWhitelist;
        _poolInformation[_pid].isStopDeposit = _isStopDeposit;

        emit PoolParametersSet(
            _offeringAmountPool,
            _raisingAmountPool,
            _pid,
            _lpToken,
            _hasWhitelist,
            _isStopDeposit
        );
    }

    /**
     * @dev Allows admins to with the deposited LP tokens from the pools
     */
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
        uint256 contractBalance = token.balanceOf(address(this));

        if (amount > contractBalance) {
            amount = contractBalance;
        }

        token.safeTransfer(address(msg.sender), amount);

        emit EmergencyTokenWithdraw(address(msg.sender), _token, amount);
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
        bool hasWhitelist,
        bool isStopDeposit
    );
}
