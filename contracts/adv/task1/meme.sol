// SPDX-License-Identifier: MIT
pragma solidity ^0.8;
import {ERC20} from "../../task2/ERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

struct Allocation {
    address receiver;
    uint16 percentage;
}

/**
 * 每笔交易按5%收取交易税
 * 交易税计入 税池
 * 税池可以按设定的比例分配给固定的若干地址
 * 用户可以添加流动性和移除流动性（合约不参与）
 * 设置了单笔交易最大额度
 * 设置了单日交易最大额度
 * 设置了单日交易次数限制
 * 设置了单个地址的balance不能超过总供应量的10%
 *
 */
contract Meme is ERC20 {
    uint256 public constant TAX_RATE = 5;
    uint256 public constant MAX_AMOUNT_PER_TX = 100e18;
    uint256 public constant MAX_AMOUNT_PER_DAY = 10000e18;
    uint256 public constant SECONDS_PER_DAY = 3600 * 24;
    uint256 public constant MAX_TX_COUNT_PER_DAY = 500;
    uint256 public taxPool;
    mapping(uint256 => uint256) public dailyTransferAmount;
    mapping(uint256 => uint256) public dailyTransferCount;

    IUniswapV2Router02 public immutable uniswapRouter;

    Allocation[] public allocations;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function _calcTax(uint256 amount) internal pure returns (uint256 tax) {
        tax = amount * TAX_RATE / 100;
    }

    function allocateFunds() external onlyOwner {
        for (uint8 i = 0; i < allocations.length; i++) {
            uint256 amount = taxPool * allocations[i].percentage / 100;
            address receiver = allocations[i].receiver;
            balanceOf[receiver] += amount;
            taxPool -= amount;
            emit Transfer(address(0), receiver, amount);
        }
    }

    /**
     * 转账前计算税费并将税费转入税费池
     * 限制单笔转账金额
     * 限制每日转账总金额
     */
    function _removeTaxFromAmount(uint256 amount) internal returns (uint256, uint256) {
        require(amount <= MAX_AMOUNT_PER_TX, "over limit per transaction");
        uint256 day = block.timestamp / 1 days;
        dailyTransferAmount[day] += amount;
        dailyTransferCount[day] += 1;
        require(dailyTransferAmount[day] <= MAX_AMOUNT_PER_DAY, "over daily limit");
        require(dailyTransferCount[day] <= MAX_TX_COUNT_PER_DAY, "over daily limit");
        uint256 tax = _calcTax(amount);
        require(
            (balanceOf[msg.sender] + amount - tax) * 100 / totalSupply <= 10,
            "forbidden balance more than 10% of supply"
        );
        taxPool += tax;
        return (amount - tax, tax);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        (uint256 actualAmount, ) = _removeTaxFromAmount(amount);
        return super.transfer(to, actualAmount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        (uint256 actualAmount, ) = _removeTaxFromAmount(amount);
        return super.transferFrom(from, to, actualAmount);
    }

    /// @notice 用户直接参与流动性池，token + ETH
    /// @param tokenAmount 用户想提供的代币数量
    function addLiquidityETH(uint256 tokenAmount)
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        require(msg.value > 0, "Require ETH");

        // 用户必须先 approve Router 可以花 token
        // ERC20 approve 示例：
        // MyToken(tokenAddress).approve(routerAddress, tokenAmount);

        // 调用 Router 添加流动性
        return uniswapRouter.addLiquidityETH{value: msg.value}(
            address(this), // 代币地址
            tokenAmount, // 用户提供的代币数量
            0, // slippage 最小 token
            0, // slippage 最小 ETH
            msg.sender, // LP Token 发给用户
            block.timestamp // deadline
        );
    }

    /// @notice 用户从流动性池移除流动性
    /// @param liquidity 用户想赎回的 LP Token 数量
    function removeLiquidityETH(uint256 liquidity) external {
        uniswapRouter.removeLiquidityETH(
            address(this), // 代币地址
            liquidity, // LP Token 数量
            0, // 最少代币收回量
            0, // 最少 ETH 收回量
            msg.sender, // token + ETH 回到用户
            block.timestamp
        );
    }
}
