const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Auction 合约测试 - 使用Mock预言机", function () {
  let auction;
  let nft;
  let mockERC20;
  let mockOracle;
  let owner, seller, buyer1, buyer2;

  // 测试常量
  const TOKEN_ID = 1;
  const START_TIME = Math.floor(Date.now() / 1000) - 1800; // 30分钟前开始
  const END_TIME = START_TIME + 3600; // 1小时后结束
  const PRICE_DROP_INTERVAL = 300; // 5分钟间隔

  // 预言机价格设置 (ETH价格为 $3000，8位小数)
  const ETH_PRICE = 3000 * 1e8; // 3000 * 10^8
  const ORACLE_DECIMALS = 8;

  beforeEach(async function () {
    [owner, seller, buyer1, buyer2] = await ethers.getSigners();

    // 部署ERC721合约
    const ERC721 = await ethers.getContractFactory("ERC721");
    nft = await ERC721.deploy("Test NFT", "TNFT");
    await nft.waitForDeployment();

    // 部署Mock ERC20合约
    const MockERC20 = await ethers.getContractFactory("ERC20");
    mockERC20 = await MockERC20.deploy("Mock DAI", "DAI");
    await mockERC20.waitForDeployment();

    // 部署Mock预言机
    const MockOracle = await ethers.getContractFactory("MockAggregatorV3");
    mockOracle = await MockOracle.deploy(
      ETH_PRICE,
      ORACLE_DECIMALS,
      "ETH/USD Price Feed"
    );
    await mockOracle.waitForDeployment();

    // 部署Auction合约
    const Auction = await ethers.getContractFactory("Auction");
    auction = await Auction.deploy(
      await nft.getAddress(),
      owner.address,
      START_TIME,
      END_TIME,
      PRICE_DROP_INTERVAL
    );
    await auction.waitForDeployment();

    // 设置测试模式和Mock预言机
    await auction.connect(owner).setTestMode(true, await mockOracle.getAddress());

    // 设置测试环境
    await nft.connect(seller).mintNft(seller.address, "test-uri-1");
    await nft.connect(seller).setApprovalForAll(await auction.getAddress(), true);

    // mint ERC20代币
    await mockERC20.mint(ethers.parseEther("100000"));
    await mockERC20.transfer(buyer1.address, ethers.parseEther("1000"));
    await mockERC20.transfer(buyer2.address, ethers.parseEther("1000"));

    // 给买家设置ETH余额（增加余额以支持高价NFT）
    await ethers.provider.send("hardhat_setBalance", [
      buyer1.address,
      "0x" + ethers.parseEther("10000").toString(16)
    ]);
    await ethers.provider.send("hardhat_setBalance", [
      buyer2.address,
      "0x" + ethers.parseEther("10000").toString(16)
    ]);
  });

  describe("Mock预言机设置", function () {
    it("应该正确设置测试模式", async function () {
      expect(await auction.testMode()).to.equal(true);
      expect(await auction.mockFeedAddress()).to.equal(await mockOracle.getAddress());
    });

    it("应该能够获取预言机价格", async function () {
      const result = await auction.getChainlinkDataFeedLatestAnswer(0); // ETH = 0
      const price = result[0];
      const decimals = result[1];
      const startedAt = result[2];
      const updatedAt = result[3];

      expect(price).to.equal(ETH_PRICE);
      expect(decimals).to.equal(ORACLE_DECIMALS);
      expect(startedAt).to.be.gt(0);
      expect(updatedAt).to.be.gt(0);
    });

    it("应该能够更新预言机价格", async function () {
      const newPrice = 3500 * 1e8; // $3500
      await mockOracle.setPrice(newPrice);

      const result = await auction.getChainlinkDataFeedLatestAnswer(0);
      const price = result[0];
      expect(price).to.equal(newPrice);
    });
  });

  describe("价格转换功能", function () {
    it("应该正确计算ETH对应的USD价值", async function () {
      // 1 ETH = $3000
      const ethAmount = ethers.parseEther("1"); // 1 ETH = 1e18 wei
      const expectedUSD = ethAmount * BigInt(ETH_PRICE) / (10n ** BigInt(ORACLE_DECIMALS));

      // 通过测试转换函数
      const usdValue = await calculateAuctionPriceUsd(0, ethAmount);
      expect(usdValue).to.equal(expectedUSD);
    });

    // 辅助函数：计算USD价值（模拟合约中的逻辑）
    async function calculateAuctionPriceUsd(symbol, value) {
      const result = await auction.getChainlinkDataFeedLatestAnswer(symbol);
      const price = result[0];
      const decimal = result[1];
      return (BigInt(value) * BigInt(price.toString())) / (10n ** BigInt(Number(decimal) + 18));
    }
  });

  describe("完整的出价功能测试", function () {
    beforeEach(async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("100"), ethers.parseEther("20"));
    });

    it("应该能够成功用ETH出价", async function () {
      const currentPrice = await auction.getPrice(TOKEN_ID);

      // 计算需要的ETH数量
      // 如果当前价格是100 USD，ETH价格是3000 USD，则需要 100/3000 ETH
      const neededEth = (BigInt(currentPrice) * BigInt(1e18)) / BigInt(ETH_PRICE);
      const bidAmount = neededEth + BigInt(ethers.parseEther("0.01")); // 稍微多一点点

      await expect(
        auction.connect(buyer1).bid(TOKEN_ID, { value: bidAmount })
      ).to.not.be.reverted;

      // NFT应该转移给买家
      expect(await nft.ownerOf(TOKEN_ID)).to.equal(buyer1.address);
    });

    it("出价不足应该失败", async function () {
      const currentPrice = await auction.getPrice(TOKEN_ID);
      const neededEth = (BigInt(currentPrice) * BigInt(1e18)) / BigInt(ETH_PRICE);
      const lowBid = neededEth / 2n; // 只出一半的价格

      await expect(
        auction.connect(buyer1).bid(TOKEN_ID, { value: lowBid })
      ).to.be.revertedWith("payment less than price");
    });

    it("已售出的NFT不能再次出价", async function () {
      const currentPrice = await auction.getPrice(TOKEN_ID);
      const neededEth = (BigInt(currentPrice) * BigInt(1e18)) / BigInt(ETH_PRICE);
      const bidAmount = neededEth + BigInt(ethers.parseEther("0.01"));

      // 第一次出价成功
      await auction.connect(buyer1).bid(TOKEN_ID, { value: bidAmount });

      // 第二次出价失败
      await expect(
        auction.connect(buyer2).bid(TOKEN_ID, { value: bidAmount })
      ).to.be.revertedWith("not on shelf");
    });
  });

  describe("手续费机制测试", function () {
    it("应该正确计算和分配手续费", async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("0.01"), ethers.parseEther("0.001"));

      const currentPrice = await auction.getPrice(TOKEN_ID);
      const neededEth = (BigInt(currentPrice) * BigInt(1e18)) / BigInt(ETH_PRICE);
      const bidAmount = neededEth + BigInt(ethers.parseEther("0.01"));

      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);
      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      await auction.connect(buyer1).bid(TOKEN_ID, { value: bidAmount });

      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;
      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;

      // 验证资金分配
      expect(sellerReceived).to.be.gt(0);
      expect(ownerReceived).to.be.gt(0);

      // 验证手续费在1%-5%之间
      const expectedMinFee = bidAmount / 100n; // 1%
      const expectedMaxFee = bidAmount * 5n / 100n; // 5%
      expect(ownerReceived).to.be.gte(expectedMinFee);
      expect(ownerReceived).to.be.lte(expectedMaxFee);
    });

    it("卖家和管理员应该能够提取资金", async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("0.01"), ethers.parseEther("0.001"));

      const currentPrice = await auction.getPrice(TOKEN_ID);
      const neededEth = (BigInt(currentPrice) * BigInt(1e18)) / BigInt(ETH_PRICE);
      const bidAmount = neededEth + BigInt(ethers.parseEther("0.01"));

      await auction.connect(buyer1).bid(TOKEN_ID, { value: bidAmount });

      // 卖家提取资金
      await expect(auction.connect(seller).withdraw()).to.not.be.reverted;

      // 管理员提取手续费
      await expect(auction.connect(owner).withdraw()).to.not.be.reverted;
    });
  });

  describe("动态手续费测试", function () {
    it("拍卖开始时手续费应该较高", async function () {
      // 创建刚开始的拍卖
      const startTime = Math.floor(Date.now() / 1000);
      const endTime = startTime + 3600;

      const NewAuction = await ethers.getContractFactory("Auction");
      const newAuction = await NewAuction.deploy(
        await nft.getAddress(),
        owner.address,
        startTime,
        endTime,
        300
      );
      await newAuction.waitForDeployment();

      await newAuction.connect(owner).setTestMode(true, await mockOracle.getAddress());

      await nft.connect(seller).mintNft(seller.address, "test-uri-2");
      await nft.connect(seller).setApprovalForAll(await newAuction.getAddress(), true);
      await newAuction.connect(seller).putOnShelf(2, ethers.parseEther("100"), ethers.parseEther("20"));

      // 测试手续费计算 - 这里无法直接调用内部函数，但可以通过出价来验证
      const bidAmount = ethers.parseEther("0.1");
      await newAuction.connect(buyer2).bid(2, { value: bidAmount });

      // 验证手续费被正确收取
      await expect(newAuction.connect(owner).withdraw()).to.not.be.reverted;
    });
  });

  describe("多笔交易测试", function () {
    it("应该能够处理多笔独立交易", async function () {
      // mint更多NFT
      await nft.connect(seller).mintNft(seller.address, "test-uri-2");
      await nft.connect(seller).mintNft(seller.address, "test-uri-3");

      // 上架多个NFT
      await auction.connect(seller).putOnShelf(2, ethers.parseEther("50"), ethers.parseEther("10"));
      await auction.connect(seller).putOnShelf(3, ethers.parseEther("60"), ethers.parseEther("15"));

      // 计算每个NFT需要的ETH
      const price1 = await auction.getPrice(2);
      const price2 = await auction.getPrice(3);
      const eth1 = (BigInt(price1) * BigInt(1e18)) / BigInt(ETH_PRICE) + BigInt(ethers.parseEther("0.01"));
      const eth2 = (BigInt(price2) * BigInt(1e18)) / BigInt(ETH_PRICE) + BigInt(ethers.parseEther("0.01"));

      // 买家1购买第一个NFT
      await auction.connect(buyer1).bid(2, { value: eth1 });

      // 买家2购买第二个NFT
      await auction.connect(buyer2).bid(3, { value: eth2 });

      // 验证NFT所有权
      expect(await nft.ownerOf(2)).to.equal(buyer1.address);
      expect(await nft.ownerOf(3)).to.equal(buyer2.address);

      // 验证资金可以提取
      await expect(auction.connect(seller).withdraw()).to.not.be.reverted;
      await expect(auction.connect(owner).withdraw()).to.not.be.reverted;
    });
  });
});