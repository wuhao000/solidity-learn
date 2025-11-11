# Solidity Learning Project

这是一个使用 Hardhat 框架的 Solidity 学习项目，包含了多个智能合约实现示例。

## 项目结构

```
├── contracts/          # 智能合约源码
│   ├── task1/         # 任务1：基础合约
│   ├── task2/         # 任务2：ERC20/ERC721合约
│   ├── task3/         # 任务3：拍卖合约
│   └── utils/         # 工具合约
├── scripts/           # 部署脚本
├── test/             # 测试文件
├── artifacts/        # 编译后的合约文件
└── hardhat.config.js # Hardhat 配置文件
```

## 合约说明

### Task 1 - 基础功能合约
- `voting.sol` - 投票合约
- `reverse_string.sol` - 字符串反转合约
- `roman_to_integer.sol` - 罗马数字转整数合约
- `integer_to_roman.sol` - 整数转罗马数字合约
- `merge.sol` - 数组合并合约
- `find.sol` - 查找合约

### Task 2 - 代币合约
- `ERC20.sol` - ERC20代币合约
- `ERC721.sol` - ERC721 NFT合约
- `begging.sol` - 捐款合约

### Task 3 - 拍卖系统
- `Auction.sol` - 拍卖合约
- `AuctionFactory.sol` - 拍卖工厂合约
- `AuctionProxy.sol` - 拍卖代理合约
- `IAuction.sol` - 拍卖接口合约

### Utils
- `OnlyOwner.sol` - 所有者权限管理合约

## 安装和设置

### 环境要求
- Node.js >= 16.0.0
- npm 或 yarn

### 安装依赖

```bash
npm install
```

### 环境配置

复制 `.env.example` 为 `.env` 并配置相应变量：

```bash
cp .env.example .env
```

## 使用指南

### 编译合约

```bash
npm run compile
```

### 运行测试

```bash
npm run test
```

### 启动本地节点

```bash
npm run node
```

### 部署合约

```bash
# 部署到本地网络
npm run deploy:local

# 部署到其他网络
npm run deploy -- --network <network_name>
```

### 其他有用的命令

```bash
# 清理编译文件
npm run clean

# 生成gas报告
npm run gas-report

# 检查合约大小
npm run size

# 运行覆盖率测试
npm run coverage
```

## 网络配置

项目支持以下网络：
- hardhat (内置测试网络)
- localhost (本地8545端口)

可以在 `hardhat.config.js` 中添加更多网络配置。

## 测试

测试文件位于 `test/` 目录下，使用 Chai 和 Ethers.js 进行测试。

运行测试：
```bash
npm test
```

运行特定测试：
```bash
npx hardhat test test/sample-test.js
```

## 贡献

欢迎提交 Pull Request 和 Issue！

## 许可证

MIT License
