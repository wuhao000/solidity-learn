# 部署

1. 部署NFT合约 [ERC721.sol](../task2/ERC721.sol) 
2. 部署拍卖工厂合约 [AuctionFactory.sol](AuctionFactory.sol)
3. 部署逻辑合约 [Auction.sol](Auction.sol)
4. 调用工厂合约的 initialize 方法创建拍卖代理合约
5. 调用拍卖代理合约的version方法，返回逻辑合约版本号

# 升级

1. 修改逻辑合约的version()方法，version + 1
2. 部署新的逻辑合约 [Auction.sol](Auction.sol)
3. 验证新的逻辑合约的version为新的版本号
4. 拍卖代理合约的升级方法中填入新的逻辑合约地址，调用升级方法
5. 用代理合约调用version方法，应该返回新的版本号
6. 升级完成

# 测试

```bash
npm test
```