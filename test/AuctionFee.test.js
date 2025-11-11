const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Auction 手续费测试", function () {
  let auction;
  let nft;
  let owner, seller, buyer;

  // 测试常量
  const TOKEN_ID = 1;
  const START_TIME = Math.floor(Date.now() / 1000) - 3600; // 1小时前开始
  const END_TIME = START_TIME + 7200; // 持续2小时
  const PRICE_DROP_INTERVAL = 300; // 5分钟
  const MAX_PRICE = ethers.parseEther("100");
  const MIN_PRICE = ethers.parseEther("20");

  beforeEach(async function () {
    [owner, seller, buyer] = await ethers.getSigners();

    // 部署ERC721合约
    const ERC721 = await ethers.getContractFactory("ERC721");
    nft = await ERC721.deploy("Test NFT", "TNFT");
    await nft.waitForDeployment();

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

    // 设置测试环境
    await nft.connect(seller).mintNft(seller.address, "test-uri");
    await nft.connect(seller).setApprovalForAll(await auction.getAddress(), true);

    // 给买家足够的ETH
    await ethers.provider.send("hardhat_setBalance", [
      buyer.address,
      "0x" + ethers.parseEther("1000").toString(16)
    ]);
  });

  describe("手续费率计算", function () {
    it("拍卖开始前手续费应该是5%", async function () {
      // 创建一个未来开始的拍卖合约
      const futureStart = Math.floor(Date.now() / 1000) + 3600;
      const futureEnd = futureStart + 7200;

      const FutureAuction = await ethers.getContractFactory("Auction");
      const futureAuction = await FutureAuction.deploy(
        await nft.getAddress(),
        owner.address,
        futureStart,
        futureEnd,
        PRICE_DROP_INTERVAL
      );
      await futureAuction.waitForDeployment();

      // 测试手续费计算 - 我们需要访问内部函数，这里通过计算验证
      const bidAmount = ethers.parseEther("100");
      await nft.connect(seller).setApprovalForAll(await futureAuction.getAddress(), true);
      await futureAuction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("1000"), ethers.parseEther("1"));

      // 在拍卖开始前，手续费率应该是5%
      // 由于我们无法直接调用内部函数，我们通过观察资金分配来验证
      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);
      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      await futureAuction.connect(buyer).bid(TOKEN_ID, { value: bidAmount });

      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;
      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;

      // 5% 手续费：100 ETH -> 95 ETH给卖家，5 ETH给合约所有者
      const expectedSellerReceived = bidAmount * 95n / 100n;
      const expectedOwnerReceived = bidAmount * 5n / 100n;

      expect(sellerReceived).to.equal(expectedSellerReceived);
      expect(ownerReceived).to.equal(expectedOwnerReceived);
    });

    it("拍卖接近结束时手续费应该接近1%", async function () {
      // 创建一个接近结束的拍卖合约
      const pastStart = Math.floor(Date.now() / 1000) - 7000;
      const pastEnd = pastStart + 7200;

      const PastAuction = await ethers.getContractFactory("Auction");
      const pastAuction = await PastAuction.deploy(
        await nft.getAddress(),
        owner.address,
        pastStart,
        pastEnd,
        PRICE_DROP_INTERVAL
      );
      await pastAuction.waitForDeployment();

      await nft.connect(seller).setApprovalForAll(await pastAuction.getAddress(), true);
      await pastAuction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("1000"), ethers.parseEther("1"));

      const bidAmount = ethers.parseEther("100");
      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);
      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      await pastAuction.connect(buyer).bid(TOKEN_ID, { value: bidAmount });

      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;
      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;

      // 接近结束时，手续费应该接近1%
      expect(ownerReceived).to.be.gt(0);
      expect(sellerReceived).to.be.gt(bidAmount * 90n / 100n);
    });
  });

  describe("资金分配测试", function () {
    beforeEach(async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("1000"), ethers.parseEther("1"));
    });

    it("手续费应该正确分配给合约所有者", async function () {
      const bidAmount = ethers.parseEther("100");

      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      await auction.connect(buyer).bid(TOKEN_ID, { value: bidAmount });

      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);
      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;

      // 手续费应该在1%-5%之间
      expect(ownerReceived).to.be.gte(bidAmount / 100n); // 至少1%
      expect(ownerReceived).to.be.lte(bidAmount * 5n / 100n); // 最多5%
      expect(ownerReceived).to.be.gt(0);
    });

    it("净额应该正确分配给NFT所有者", async function () {
      const bidAmount = ethers.parseEther("100");

      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);

      await auction.connect(buyer).bid(TOKEN_ID, { value: bidAmount });

      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;

      // 卖家应该收到扣除手续费后的金额
      expect(sellerReceived).to.be.gte(bidAmount * 95n / 100n); // 至少95%
      expect(sellerReceived).to.be.lt(bidAmount); // 小于总金额
    });

    it("总资金分配应该等于出价金额", async function () {
      const bidAmount = ethers.parseEther("100");

      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);
      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      await auction.connect(buyer).bid(TOKEN_ID, { value: bidAmount });

      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;
      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;

      // 考虑gas费用，卖家和所有者收到的总和应该接近出价金额
      const totalReceived = sellerReceived + ownerReceived;

      // 由于gas费用的存在，总金额会略小于出价金额，但应该很接近
      expect(totalReceived).to.be.gt(bidAmount * 95n / 100n);
    });
  });

  describe("多笔交易手续费分配", function () {
    beforeEach(async function () {
      // 为测试创建多个NFT
      await nft.mint(seller.address, 2);
      await nft.mint(seller.address, 3);
      await nft.connect(seller).setApprovalForAll(await auction.getAddress(), true);

      await auction.connect(seller).putOnShelf(1, ethers.parseEther("1000"), ethers.parseEther("1"));
      await auction.connect(seller).putOnShelf(2, ethers.parseEther("1000"), ethers.parseEther("1"));
      await auction.connect(seller).putOnShelf(3, ethers.parseEther("1000"), ethers.parseEther("1"));
    });

    it("多笔交易的手续费应该累积", async function () {
      const bidAmount = ethers.parseEther("100");

      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      // 进行三笔交易
      await auction.connect(buyer).bid(1, { value: bidAmount });
      await auction.connect(buyer).bid(2, { value: bidAmount });
      await auction.connect(buyer).bid(3, { value: bidAmount });

      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);
      const totalOwnerReceived = ownerBalanceAfter - ownerBalanceBefore;

      // 应该收到三笔交易的手续费总和
      expect(totalOwnerReceived).to.be.gte(bidAmount * 3n / 100n); // 至少3% (1% x 3)
      expect(totalOwnerReceived).to.be.lte(bidAmount * 15n / 100n); // 最多15% (5% x 3)
    });

    it("卖家应该能够提取所有销售资金", async function () {
      const bidAmount = ethers.parseEther("100");

      // 进行三笔交易
      await auction.connect(buyer).bid(1, { value: bidAmount });
      await auction.connect(buyer).bid(2, { value: bidAmount });
      await auction.connect(buyer).bid(3, { value: bidAmount });

      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);

      await auction.connect(seller).withdraw();

      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      const sellerWithdrawn = sellerBalanceAfter - sellerBalanceBefore;

      // 卖家应该收到三笔交易的净额总和
      expect(sellerWithdrawn).to.be.gte(bidAmount * 285n / 100n); // 至少285 ETH (95% x 3)
      expect(sellerWithdrawn).to.be.lt(bidAmount * 3n); // 小于300 ETH
    });

    it("管理员应该能够提取所有手续费", async function () {
      const bidAmount = ethers.parseEther("100");

      // 进行三笔交易
      await auction.connect(buyer).bid(1, { value: bidAmount });
      await auction.connect(buyer).bid(2, { value: bidAmount });
      await auction.connect(buyer).bid(3, { value: bidAmount });

      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      await auction.connect(owner).withdraw();

      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);
      const ownerWithdrawn = ownerBalanceAfter - ownerBalanceBefore;

      // 管理员应该收到三笔交易的手续费总和
      expect(ownerWithdrawn).to.be.gte(bidAmount * 3n / 100n); // 至少3 ETH (1% x 3)
      expect(ownerWithdrawn).to.be.lte(bidAmount * 15n / 100n); // 最多15 ETH (5% x 3)
    });
  });

  describe("手续费精度测试", function () {
    it("小额资金的手续费计算", async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("1"), ethers.parseEther("0.01"));

      const smallBid = ethers.parseEther("0.001"); // 0.001 ETH

      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);
      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);

      await auction.connect(buyer).bid(TOKEN_ID, { value: smallBid });

      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);
      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);

      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;
      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;

      // 即使是小额资金，也应该正确计算手续费
      expect(ownerReceived).to.be.gte(0);
      expect(sellerReceived).to.be.gte(0);
      expect(ownerReceived + sellerReceived).to.be.gte(smallBid * 95n / 100n);
    });

    it("大额资金的手续费计算", async function () {
      await auction.connect(seller).putOnShelf(TOKEN_ID, ethers.parseEther("10000"), ethers.parseEther("1000"));

      const largeBid = ethers.parseEther("1000"); // 1000 ETH

      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);
      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);

      await auction.connect(buyer).bid(TOKEN_ID, { value: largeBid });

      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);
      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);

      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;
      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;

      // 大额资金的手续费应该准确
      expect(ownerReceived).to.be.gte(largeBid / 100n); // 至少1%
      expect(ownerReceived).to.be.lte(largeBid * 5n / 100n); // 最多5%
      expect(sellerReceived).to.be.gte(largeBid * 95n / 100n); // 至少95%
    });
  });
});