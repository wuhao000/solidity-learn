const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Auction 合约测试 - Mock预言机简化版", function () {
  let auction;
  let nft;
  let mockOracle;
  let owner, seller, buyer;

  // 测试常量 - 设置更合理的价格
  const TOKEN_ID = 1;
  const START_TIME = Math.floor(Date.now() / 1000) - 1800; // 30分钟前开始
  const END_TIME = START_TIME + 3600; // 1小时后结束
  const PRICE_DROP_INTERVAL = 300; // 5分钟间隔

  // 预言机价格设置 (ETH价格为 $3000，8位小数)
  const ETH_PRICE = 3000 * 1e8; // 3000 * 10^8
  const ORACLE_DECIMALS = 8;

  beforeEach(async function () {
    [owner, seller, buyer] = await ethers.getSigners();

    // 部署ERC721合约
    const ERC721 = await ethers.getContractFactory("ERC721");
    nft = await ERC721.deploy("Test NFT", "TNFT");
    await nft.waitForDeployment();

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

    // 给买家设置足够的ETH余额
    await ethers.provider.send("hardhat_setBalance", [
      buyer.address,
      "0x" + ethers.parseEther("100").toString(16)
    ]);
  });

  describe("Mock预言机基本功能", function () {
    it("应该正确设置测试模式", async function () {
      expect(await auction.testMode()).to.equal(true);
      expect(await auction.mockFeedAddress()).to.equal(await mockOracle.getAddress());
    });

    it("应该能够获取预言机价格", async function () {
      const result = await auction.getChainlinkDataFeedLatestAnswer(0); // ETH = 0
      const price = result[0];
      const decimals = result[1];

      expect(price).to.equal(ETH_PRICE);
      expect(decimals).to.equal(ORACLE_DECIMALS);
    });

    it("应该能够更新预言机价格", async function () {
      const newPrice = 3500 * 1e8; // $3500
      await mockOracle.setPrice(newPrice);

      const result = await auction.getChainlinkDataFeedLatestAnswer(0);
      const price = result[0];
      expect(price).to.equal(newPrice);
    });
  });

  describe("简化出价功能测试", function () {
    it("应该能够成功用较低价格出价", async function () {
      // 设置非常低的USD价格，这样需要的ETH就少了
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("0.01"), ethers.parseEther("0.001")); // 0.01 USD

      const currentPrice = await auction.getPrice(TOKEN_ID);

      // 0.01 USD / 3000 USD/ETH = 0.00000333 ETH
      // 转换为wei: 0.00000333 * 10^18 = 3330000000000 wei
      const neededEth = BigInt(currentPrice) * BigInt(10**18) / BigInt(ETH_PRICE);
      const bidAmount = neededEth + ethers.parseEther("0.001"); // 加一点gas缓冲

      await expect(
        auction.connect(buyer).bid(TOKEN_ID, { value: bidAmount })
      ).to.not.be.reverted;

      // NFT应该转移给买家
      expect(await nft.ownerOf(TOKEN_ID)).to.equal(buyer.address);
    });

    it("出价不足应该失败", async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("0.01"), ethers.parseEther("0.001"));

      const currentPrice = await auction.getPrice(TOKEN_ID);
      const neededEth = BigInt(currentPrice) * BigInt(10**18) / BigInt(ETH_PRICE);
      const lowBid = neededEth / 2n; // 只出一半的价格

      await expect(
        auction.connect(buyer).bid(TOKEN_ID, { value: lowBid })
      ).to.be.revertedWith("payment less than price");
    });

    it("已售出的NFT不能再次出价", async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("0.01"), ethers.parseEther("0.001"));

      const currentPrice = await auction.getPrice(TOKEN_ID);
      const neededEth = BigInt(currentPrice) * BigInt(10**18) / BigInt(ETH_PRICE);
      const bidAmount = neededEth + ethers.parseEther("0.001");

      // 第一次出价成功
      await auction.connect(buyer).bid(TOKEN_ID, { value: bidAmount });

      // 第二次出价失败
      await expect(
        auction.connect(buyer).bid(TOKEN_ID, { value: bidAmount })
      ).to.be.revertedWith("not on shelf");
    });
  });

  describe("手续费机制测试", function () {
    it("应该正确计算和分配手续费", async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("0.01"), ethers.parseEther("0.001"));

      const currentPrice = await auction.getPrice(TOKEN_ID);
      const neededEth = BigInt(currentPrice) * BigInt(10**18) / BigInt(ETH_PRICE);
      const bidAmount = neededEth + ethers.parseEther("0.001");

      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);
      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      await auction.connect(buyer).bid(TOKEN_ID, { value: bidAmount });

      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;
      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;

      // 验证资金分配
      expect(sellerReceived).to.be.gt(0);
      expect(ownerReceived).to.be.gt(0);

      // 验证手续费在合理范围内
      const expectedMinFee = bidAmount / 100n; // 1%
      const expectedMaxFee = bidAmount * 5n / 100n; // 5%
      expect(ownerReceived).to.be.gte(expectedMinFee);
      expect(ownerReceived).to.be.lte(expectedMaxFee);
    });

    it("卖家和管理员应该能够提取资金", async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("0.01"), ethers.parseEther("0.001"));

      const currentPrice = await auction.getPrice(TOKEN_ID);
      const neededEth = BigInt(currentPrice) * BigInt(10**18) / BigInt(ETH_PRICE);
      const bidAmount = neededEth + ethers.parseEther("0.001");

      await auction.connect(buyer).bid(TOKEN_ID, { value: bidAmount });

      // 卖家提取资金
      await expect(auction.connect(seller).withdraw()).to.not.be.reverted;

      // 管理员提取手续费
      await expect(auction.connect(owner).withdraw()).to.not.be.reverted;
    });
  });

  describe("多笔交易测试", function () {
    it("应该能够处理多笔独立交易", async function () {
      // mint更多NFT
      await nft.connect(seller).mintNft(seller.address, "test-uri-2");
      await nft.connect(seller).mintNft(seller.address, "test-uri-3");

      // 上架多个低价NFT
      await auction.connect(seller).putOnShelf(2, ethers.parseEther("0.005"), ethers.parseEther("0.001"));
      await auction.connect(seller).putOnShelf(3, ethers.parseEther("0.006"), ethers.parseEther("0.001"));

      // 计算每个NFT需要的ETH（都是低价）
      const price1 = await auction.getPrice(2);
      const price2 = await auction.getPrice(3);
      const eth1 = BigInt(price1) * BigInt(10**18) / BigInt(ETH_PRICE) + ethers.parseEther("0.001");
      const eth2 = BigInt(price2) * BigInt(10**18) / BigInt(ETH_PRICE) + ethers.parseEther("0.001");

      // 买家1购买第一个NFT
      await auction.connect(buyer).bid(2, { value: eth1 });

      // 买家2购买第二个NFT（需要先mint更多NFT给第二个买家）
      const [_, __, thirdAddress] = await ethers.getSigners();
      await ethers.provider.send("hardhat_setBalance", [
        thirdAddress,
        "0x" + ethers.parseEther("100").toString(16)
      ]);
      await auction.connect(thirdAddress).bid(3, { value: eth2 });

      // 验证NFT所有权
      expect(await nft.ownerOf(2)).to.equal(buyer.address);
      expect(await nft.ownerOf(3)).to.equal(thirdAddress);

      // 验证资金可以提取
      await expect(auction.connect(seller).withdraw()).to.not.be.reverted;
      await expect(auction.connect(owner).withdraw()).to.not.be.reverted;
    });
  });
});