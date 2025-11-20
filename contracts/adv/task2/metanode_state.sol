// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ERC20} from "../../task2/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract MetaNodeStakingContract is Initializable, UUPSUpgradeable, PausableUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;

    bytes32 public constant ADMIN_ROLE = keccak256("admin_role");
    bytes32 public constant UPGRADE_ROLE = keccak256("upgrade_role");
    uint256 public constant ETH_PID = 0;

    struct Pool {
        // 质押代币地址
        address stTokenAddress;
        // 池子的权重
        uint256 poolWeight;
        // 最后一次分配收益的区块高度
        uint256 lastRewardBlock;
        uint256 accMetaNodePerST;
        // 池子中质押代币总量
        uint256 stTokenAmount;
        // 最小质押金额
        uint256 minDepositAmount;
        // 解质押锁定区块数
        uint256 unstakeLockedBlocks;
    }

    struct UnstakeRequest {
        // 请求解质押的金额
        uint256 amount;
        // 该金额可以解锁的区块号
        uint256 unlockBlocks;
    }

    struct User {
        // 用户提供的质押代币数量
        uint256 stAmount;
        // 已分发给用户的MetaNode数量
        uint256 finishedMetaNode;
        // 待领取的MetaNode数量
        uint256 pendingMetaNode;
        // 解质押请求列表
        UnstakeRequest[] requests;
    }

    // MetaNode质押合约开始生效的区块号
    uint256 public startBlock;
    // MetaNode质押合约结束的区块号
    uint256 public endBlock;
    // 每个区块产生的MetaNode代币奖励数量
    uint256 public MetaNodePerBlock;

    // 暂停提取功能的状态标志
    bool public withdrawPaused;

    // 暂停领取奖励功能的状态标志
    bool public claimPaused;

    // MetaNode代币合约地址
    IERC20 public MetaNode;

    // 所有池子的总权重
    uint256 public totalPoolWeight;

    Pool[] public pools;

    mapping(address => bool) public poolFlag;

    // 池子ID => 用户地址 => 用户信息
    mapping(uint256 => mapping(address => User)) public users;

    // ************************************** 事件定义 **************************************

    event SetMetaNode(IERC20 indexed MetaNode);

    event PauseWithdraw();

    event UnpauseWithdraw();

    event PauseClaim();

    event UnpauseClaim();

    event SetStartBlock(uint256 indexed startBlock);

    event SetEndBlock(uint256 indexed endBlock);

    event SetMetaNodePerBlock(uint256 indexed MetaNodePerBlock);

    event AddPool(
        address indexed stTokenAddress,
        uint256 indexed poolWeight,
        uint256 indexed lastRewardBlock,
        uint256 minDepositAmount,
        uint256 unstakeLockedBlocks
    );

    event UpdatePoolInfo(uint256 indexed poolId, uint256 indexed minDepositAmount, uint256 indexed unstakeLockedBlocks);

    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight);

    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 totalMetaNode);

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);

    event RequestUnstake(address indexed user, uint256 indexed poolId, uint256 amount);

    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount, uint256 indexed blockNumber);

    event Claim(address indexed user, uint256 indexed poolId, uint256 MetaNodeReward);

    /**
     * 池子的pid是顺序编号且从0开始的，所以不能大于池子的长度 - 1
     */
    modifier checkPid(uint256 _pid) {
        require(_pid < pools.length, "invalid pid");
        _;
    }

    /**
     * 只有非暂停状态下才可以领取
     */
    modifier whenNotClaimPaused() {
        require(!claimPaused, "claim is paused");
        _;
    }

    /**
     * 非暂停状态下可以提取（解质押）
     */
    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    /**
     * @notice 设置MetaNode代币地址，部署时设置基本信息
     */
    function initialize(IERC20 _MetaNode, uint256 _startBlock, uint256 _endBlock, uint256 _MetaNodePerBlock)
        public
        initializer
    {
        require(_startBlock <= _endBlock && _MetaNodePerBlock > 0, "invalid parameters");

        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADE_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        setMetaNode(_MetaNode);

        startBlock = _startBlock;
        endBlock = _endBlock;
        MetaNodePerBlock = _MetaNodePerBlock;
    }

    /**
     * 有升级权限的地址才可以升级合约
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADE_ROLE) {}

    // ************************************** 管理员函数 **************************************

    /**
     * @notice 设置MetaNode代币地址，仅管理员可调用
     */
    function setMetaNode(IERC20 _MetaNode) public onlyRole(ADMIN_ROLE) {
        MetaNode = _MetaNode;

        emit SetMetaNode(MetaNode);
    }

    /**
     * @notice 暂停提取功能，仅管理员可调用
     */
    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused, "withdraw has been already paused");

        withdrawPaused = true;

        emit PauseWithdraw();
    }

    /**
     * @notice 恢复提取功能，仅管理员可调用
     */
    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(withdrawPaused, "withdraw has been already unpaused");

        withdrawPaused = false;

        emit UnpauseWithdraw();
    }

    /**
     * @notice 暂停领取奖励功能，仅管理员可调用
     */
    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "claim has been already paused");

        claimPaused = true;

        emit PauseClaim();
    }

    /**
     * @notice 恢复领取奖励功能，仅管理员可调用
     */
    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "claim has been already unpaused");

        claimPaused = false;

        emit UnpauseClaim();
    }

    /**
     * @notice 更新质押开始区块，仅管理员可调用
     */
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock <= endBlock, "start block must be smaller than end block");

        startBlock = _startBlock;

        emit SetStartBlock(_startBlock);
    }

    /**
     * @notice 更新质押结束区块，仅管理员可调用
     */
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(startBlock <= _endBlock, "start block must be smaller than end block");

        endBlock = _endBlock;

        emit SetEndBlock(_endBlock);
    }

    /**
     * @notice 更新每个区块的MetaNode奖励数量，仅管理员可调用
     */
    function setMetaNodePerBlock(uint256 _MetaNodePerBlock) public onlyRole(ADMIN_ROLE) {
        require(_MetaNodePerBlock > 0, "invalid parameter");

        MetaNodePerBlock = _MetaNodePerBlock;

        emit SetMetaNodePerBlock(_MetaNodePerBlock);
    }

    /**
     * @notice 添加新的质押池，仅管理员可调用
     * 不要多次添加相同的质押代币，否则会导致MetaNode奖励计算混乱
     */
    function addPool(
        address _stTokenAddress,
        uint256 _poolWeight,
        uint256 _minDepositAmount,
        uint256 _unstakeLockedBlocks,
        bool _withUpdate
    ) public onlyRole(ADMIN_ROLE) {
        // 默认第一个池子为ETH池，所以第一个池子必须使用 stTokenAddress = address(0x0) 添加
        if (pools.length > 0) {
            require(_stTokenAddress != address(0), "invalid staking token address");
            require(!poolFlag[_stTokenAddress], "token already in pool");
            poolFlag[_stTokenAddress] = true;
        } else {
            require(_stTokenAddress == address(0), "invalid staking token address");
        }
        // 允许最小质押金额为0
        //require(_minDepositAmount > 0, "invalid min deposit amount");
        require(_unstakeLockedBlocks > 0, "invalid withdraw locked blocks");
        require(block.number < endBlock, "Already ended");

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalPoolWeight = totalPoolWeight + _poolWeight;

        pools.push(
            Pool({
                stTokenAddress: _stTokenAddress,
                poolWeight: _poolWeight,
                lastRewardBlock: lastRewardBlock,
                accMetaNodePerST: 0,
                stTokenAmount: 0,
                minDepositAmount: _minDepositAmount,
                unstakeLockedBlocks: _unstakeLockedBlocks
            })
        );

        emit AddPool(_stTokenAddress, _poolWeight, lastRewardBlock, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice 更新指定池子的信息（最小质押金额和解质押锁定区块数），仅管理员可调用
     */
    function updatePool(uint256 _pid, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks)
        public
        onlyRole(ADMIN_ROLE)
        checkPid(_pid)
    {
        pools[_pid].minDepositAmount = _minDepositAmount;
        pools[_pid].unstakeLockedBlocks = _unstakeLockedBlocks;

        emit UpdatePoolInfo(_pid, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice 更新指定池子的权重，仅管理员可调用
     */
    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate)
        public
        onlyRole(ADMIN_ROLE)
        checkPid(_pid)
    {
        require(_poolWeight > 0, "invalid pool weight");

        if (_withUpdate) {
            massUpdatePools();
        }

        totalPoolWeight = totalPoolWeight - pools[_pid].poolWeight + _poolWeight;
        pools[_pid].poolWeight = _poolWeight;

        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    // ************************************** 查询函数 **************************************

    /**
     * @notice 获取池子的总数量
     */
    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    /**
     * @notice 更新所有池子的奖励变量，注意gas消耗！
     */
    function massUpdatePools() public {
        uint256 length = pools.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    // ************************************** 公共函数 **************************************

    /**
     * @notice 更新指定池子的奖励变量至最新状态
     */
    function updatePool(uint256 pid) public checkPid(pid) {
        Pool storage pool = pools[pid];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        // 计算从上次更新到当前区块期间产生的总MetaNode奖励数量
        // getMultiplier返回这两个区块之间应该产生的MetaNode代币总数
        uint256 totalMetaNode = getMultiplier(pool.lastRewardBlock, block.number);

        // 计算当前池子应该分配到的MetaNode奖励数量
        // 按权重分配：(总奖励 * 当前池子权重) / 所有池子的总权重
        uint256 rewardMetaNode = totalMetaNode * pool.poolWeight / totalPoolWeight;

        // 获取当前池子中用户质押的代币总量
        uint256 stSupply = pool.stTokenAmount;

        // 如果池子中有质押代币，则更新每个质押代币的累计奖励率
        if (stSupply > 0) {
            // 将MetaNode奖励转换为"每个代币应得的奖励"的标准单位
            // 乘以1 ether是为了提高精度，避免小数计算损失
            uint256 totalMetaNode_ = rewardMetaNode * 1 ether;

            // 计算每个质押代币应该分得的MetaNode奖励
            // (总奖励 * 精度) / 质押代币总数 = 每个代币的奖励
            totalMetaNode_ /= stSupply;

            // 将新计算出的每个代币奖励累加到池子的累计奖励率中
            // accMetaNodePerST表示每个质押代币累计应该获得的MetaNode奖励(包含精度)
            pool.accMetaNodePerST += totalMetaNode_;
        }

        pool.lastRewardBlock = block.number;

        emit UpdatePool(pid, pool.lastRewardBlock, rewardMetaNode);
    }

    /**
     * @notice 返回从_from区块到_to区块的奖励倍数 [_from, _to)
     *
     * @param _from    起始区块号（包含）
     * @param _to      结束区块号（不包含）
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256 multiplier) {
        require(_from <= _to, "invalid block");
        if (_from < startBlock) {
            _from = startBlock;
        }
        if (_to > endBlock) {
            _to = endBlock;
        }
        require(_from <= _to, "end block must be greater than start block");
        multiplier = (_to - _from) * MetaNodePerBlock;
    }

    /**
     * @notice 获取用户在指定池子中待领取的MetaNode数量
     */
    function pendingMetaNode(uint256 _pid, address _user) external view checkPid(_pid) returns (uint256) {
        return pendingMetaNodeByBlockNumber(_pid, _user, block.number);
    }

    /**
     * @notice 根据指定区块号获取用户在池子中待领取的MetaNode数量
     */
    function pendingMetaNodeByBlockNumber(uint256 pid, address userAddr, uint256 _blockNumber)
        public
        view
        checkPid(pid)
        returns (uint256)
    {
        Pool storage pool = pools[pid];
        User storage user = users[pid][userAddr];
        uint256 accMetaNodePerST = pool.accMetaNodePerST;
        uint256 stSupply = pool.stTokenAmount;

        if (_blockNumber > pool.lastRewardBlock && stSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, _blockNumber);
            uint256 MetaNodeForPool = multiplier * pool.poolWeight / totalPoolWeight;
            accMetaNodePerST = accMetaNodePerST + MetaNodeForPool * (1 ether) / stSupply;
        }

        return user.stAmount * accMetaNodePerST / (1 ether) - user.finishedMetaNode + user.pendingMetaNode;
    }

    /**
     * @notice 获取用户的质押数量
     */
    function stakingBalance(uint256 _pid, address _user) external view checkPid(_pid) returns (uint256) {
        return users[_pid][_user].stAmount;
    }

    /**
     * @notice 获取用户的提取金额信息，包括锁定的解质押金额和已解锁的待提取金额
     */
    function withdrawAmount(uint256 pid, address userAddr) public view checkPid(pid) returns (uint256, uint256) {
        User storage user = users[pid][userAddr];
        uint256 requestAmount;
        uint256 pendingWithdrawAmount;
        for (uint256 i = 0; i < user.requests.length; i++) {
            if (user.requests[i].unlockBlocks <= block.number) {
                pendingWithdrawAmount += user.requests[i].amount;
            }
            requestAmount += user.requests[i].amount;
        }
        return (requestAmount, pendingWithdrawAmount);
    }

    /**
     * @notice 质押ETH以获取MetaNode奖励
     */
    function depositETH() public payable whenNotPaused {
        Pool storage pool = pools[ETH_PID];
        require(pool.stTokenAddress == address(0x0), "invalid staking token address");

        uint256 amount = msg.value;
        require(amount >= pool.minDepositAmount, "deposit amount is too small");

        _deposit(ETH_PID, amount);
    }

    /**
     * @notice 质押代币以获取MetaNode奖励
     * 质押前，用户需要授权此合约能够花费或转移其质押代币
     *
     * @param pid       要存入的池子ID
     * @param amount    要存入的质押代币数量
     */
    function deposit(uint256 pid, uint256 amount) public whenNotPaused checkPid(pid) {
        require(pid != 0, "deposit not support ETH staking");
        Pool storage pool = pools[pid];
        require(amount > pool.minDepositAmount, "deposit amount is too small");

        if (amount > 0) {
            IERC20(pool.stTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        }

        _deposit(pid, amount);
    }

    /**
     * @notice 解质押质押代币
     *
     * @param pid       要提取的池子ID
     * @param amount    要解质押的代币数量
     */
    function unstake(uint256 pid, uint256 amount) public whenNotPaused checkPid(pid) whenNotWithdrawPaused {
        Pool storage pool = pools[pid];
        User storage user = users[pid][msg.sender];

        require(user.stAmount >= amount, "Not enough staking token balance");

        updatePool(pid);

        uint256 pendingMetaNode_ = user.stAmount * pool.accMetaNodePerST / (1 ether) - user.finishedMetaNode;

        if (pendingMetaNode_ > 0) {
            user.pendingMetaNode = user.pendingMetaNode + pendingMetaNode_;
        }

        if (amount > 0) {
            user.stAmount = user.stAmount - amount;
            user.requests.push(UnstakeRequest({amount: amount, unlockBlocks: block.number + pool.unstakeLockedBlocks}));
        }

        pool.stTokenAmount = pool.stTokenAmount - amount;
        user.finishedMetaNode = user.stAmount * pool.accMetaNodePerST / (1 ether);

        emit RequestUnstake(msg.sender, pid, amount);
    }

    /**
     * @notice 提取已解锁的解质押金额
     *
     * @param _pid       要提取的池子ID
     */
    function withdraw(uint256 _pid) public whenNotPaused checkPid(_pid) whenNotWithdrawPaused {
        Pool storage pool = pools[_pid];
        User storage user = users[_pid][msg.sender];

        uint256 pendingWithdraw_;
        uint256 popNum_;
        for (uint256 i = 0; i < user.requests.length; i++) {
            if (user.requests[i].unlockBlocks > block.number) {
                break;
            }
            pendingWithdraw_ = pendingWithdraw_ + user.requests[i].amount;
            popNum_++;
        }

        for (uint256 i = 0; i < user.requests.length - popNum_; i++) {
            user.requests[i] = user.requests[i + popNum_];
        }

        for (uint256 i = 0; i < popNum_; i++) {
            user.requests.pop();
        }

        if (pendingWithdraw_ > 0) {
            if (pool.stTokenAddress == address(0x0)) {
                _safeETHTransfer(msg.sender, pendingWithdraw_);
            } else {
                IERC20(pool.stTokenAddress).safeTransfer(msg.sender, pendingWithdraw_);
            }
        }

        emit Withdraw(msg.sender, _pid, pendingWithdraw_, block.number);
    }

    /**
     * @notice 领取MetaNode代币奖励
     *
     * @param pid       要领取奖励的池子ID
     */
    function claim(uint256 pid) public whenNotPaused checkPid(pid) whenNotClaimPaused {
        Pool storage pool = pools[pid];
        User storage user = users[pid][msg.sender];

        updatePool(pid);

        uint256 pendingMetaNode_ =
            user.stAmount * pool.accMetaNodePerST / (1 ether) - user.finishedMetaNode + user.pendingMetaNode;

        if (pendingMetaNode_ > 0) {
            user.pendingMetaNode = 0;
            _safeMetaNodeTransfer(msg.sender, pendingMetaNode_);
        }

        user.finishedMetaNode = user.stAmount * pool.accMetaNodePerST / (1 ether);

        emit Claim(msg.sender, pid, pendingMetaNode_);
    }

    /**
     * @notice 质押代币以获取MetaNode奖励
     *
     * @param pid       要存入的池子ID
     * @param amount    要存入的质押代币数量
     */
    function _deposit(uint256 pid, uint256 amount) internal {
        Pool storage pool = pools[pid];
        User storage user = users[pid][msg.sender];

        updatePool(pid);

        if (user.stAmount > 0) {
            uint256 accST = user.stAmount * pool.accMetaNodePerST;
            accST /= 1 ether;

            uint256 pendingMetaNode_ = accST - user.finishedMetaNode;

            if (pendingMetaNode_ > 0) {
                user.pendingMetaNode += pendingMetaNode_;
            }
        }

         user.stAmount += amount;

        pool.stTokenAmount += amount;

        uint256 finishedMetaNode = user.stAmount * pool.accMetaNodePerST;
        finishedMetaNode /= 1 ether;

        user.finishedMetaNode = finishedMetaNode;

        emit Deposit(msg.sender, pid, amount);
    }

    /**
     * @notice 安全的MetaNode转账函数，防止因舍入误差导致池子没有足够的MetaNode代币
     *
     * @param _to        接收MetaNode代币的地址
     * @param _amount    要转账的MetaNode代币数量
     */
    function _safeMetaNodeTransfer(address _to, uint256 _amount) internal {
        uint256 MetaNodeBal = MetaNode.balanceOf(address(this));

        if (_amount > MetaNodeBal) {
            MetaNode.transfer(_to, MetaNodeBal);
        } else {
            MetaNode.transfer(_to, _amount);
        }
    }

    /**
     * @notice 安全的ETH转账函数
     *
     * @param _to        接收ETH的地址
     * @param amount    要转账的ETH数量
     */
    function _safeETHTransfer(address _to, uint256 amount) internal {
        (bool success, bytes memory data) = address(_to).call{value: amount}("");

        require(success, "ETH transfer call failed");
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "ETH transfer operation did not succeed");
        }
    }
}

