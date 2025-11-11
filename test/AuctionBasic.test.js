const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Auction 基础功能测试", function () {
  let auction;
  let nft;
  let owner, seller, buyer;

  beforeEach(async function () {
    [owner, seller, buyer] = await ethers.getSigners();

    // 部署ERC721合约
    const ERC721 = await ethers.getContractFactory("ERC721");
    nft = await ERC721.deploy("Test NFT", "TNFT");
    await nft.waitForDeployment();

    // 部署Auction合约
    const Auction = await ethers.getContractFactory("Auction");
    const startTime = Math.floor(Date.now() / 1000) - 1800; // 30分钟前开始
    const endTime = startTime + 3600; // 1小时后结束
    const priceDropInterval = 300; // 5分钟间隔

    auction = await Auction.deploy(
      await nft.getAddress(),
      owner.address,
      startTime,
      endTime,
      priceDropInterval
    );
    await auction.waitForDeployment();

    // 给卖家mint NFT并授权
    await nft.connect(seller).mintNft(seller.address, "test-uri-1");
    await nft.connect(seller).setApprovalForAll(await auction.getAddress(), true);

    // 给买家设置ETH余额
    await ethers.provider.send("hardhat_setBalance", [
      buyer.address,
      "0x" + ethers.parseEther("1000").toString(16)
    ]);
  });

  describe("合约部署", function () {
    it("应该正确设置合约参数", async function () {
      expect(await auction.nft()).to.equal(await nft.getAddress());
      expect(await auction.admin()).to.equal(owner.address);
    });

    it("应该正确设置时间参数", async function () {
      const startTime = await auction.startTime();
      const endTime = await auction.endTime();
      const interval = await auction.priceDropInterval();

      expect(startTime).to.be.gt(0);
      expect(endTime).to.be.gt(startTime);
      expect(interval).to.be.gt(0);
    });
  });

  describe("NFT上架功能", function () {
    it("应该能够成功上架NFT", async function () {
      // mint另一个NFT用于测试
      await nft.connect(seller).mintNft(seller.address, "test-uri-2");
      const tokenId = 2; // 第二个mint的token

      await expect(
        auction.connect(seller).putOnShelf(tokenId, ethers.parseEther("100"), ethers.parseEther("20"))
      ).to.not.be.reverted;

      const auctionInfo = await auction.shelf(tokenId);
      expect(auctionInfo.maxPrice).to.equal(ethers.parseEther("100"));
      expect(auctionInfo.minPrice).to.equal(ethers.parseEther("20"));
      expect(auctionInfo.owner).to.equal(seller.address);
    });

    it("非NFT所有者不能上架", async function () {
      // 使用 tokenId 1，但买家不是所有者
      await expect(
        auction.connect(buyer).putOnShelf(1, ethers.parseEther("100"), ethers.parseEther("20"))
      ).to.be.revertedWith("not owner");
    });

    it("最高价必须大于等于最低价", async function () {
      await expect(
        auction.connect(seller).putOnShelf(1, ethers.parseEther("20"), ethers.parseEther("100"))
      ).to.be.revertedWith("max price less than min price");
    });
  });

  describe("价格计算功能", function () {
    beforeEach(async function () {
      await auction.connect(seller).putOnShelf(1, ethers.parseEther("100"), ethers.parseEther("20"));
    });

    it("价格应该在最高价和最低价之间", async function () {
      const price = await auction.getPrice(1);
      expect(price).to.be.gte(ethers.parseEther("20"));
      expect(price).to.be.lte(ethers.parseEther("100"));
    });

    it("已上架的NFT应该有拍卖信息", async function () {
      const info = await auction.shelf(1);
      expect(info.owner).to.equal(seller.address);
      expect(info.maxPrice).to.equal(ethers.parseEther("100"));
      expect(info.minPrice).to.equal(ethers.parseEther("20"));
    });
  });

  describe("出价功能", function () {
    beforeEach(async function () {
      await auction.connect(seller).putOnShelf(1, ethers.parseEther("0.01"), ethers.parseEther("0.001"));
    });

    it("应该能够成功出价", async function () {
      const currentPrice = await auction.getPrice(1);

      await expect(
        auction.connect(buyer).bid(1, { value: currentPrice })
      ).to.not.be.reverted;

      // NFT应该转移给买家
      expect(await nft.ownerOf(1)).to.equal(buyer.address);
    });

    it("出价不足应该失败", async function () {
      const currentPrice = await auction.getPrice(1);
      const lowBid = currentPrice / 2n;

      await expect(
        auction.connect(buyer).bid(1, { value: lowBid })
      ).to.be.revertedWith("payment less than price");
    });

    it("已售出的NFT不能再次出价", async function () {
      const currentPrice = await auction.getPrice(1);

      // 第一次出价成功
      await auction.connect(buyer).bid(1, { value: currentPrice });

      // 第二次出价失败
      await expect(
        auction.connect(buyer).bid(1, { value: currentPrice })
      ).to.be.revertedWith("not on shelf");
    });
  });

  describe("移除NFT功能", function () {
    beforeEach(async function () {
      await auction.connect(seller).putOnShelf(1, ethers.parseEther("100"), ethers.parseEther("20"));
    });

    it("NFT所有者应该能够移除NFT", async function () {
      await expect(
        auction.connect(seller).removeFromShelf(1)
      ).to.not.be.reverted;

      // NFT应该返回给卖家
      expect(await nft.ownerOf(1)).to.equal(seller.address);

      // 拍卖信息应该被清除
      const auctionInfo = await auction.shelf(1);
      expect(auctionInfo.owner).to.equal(ethers.ZeroAddress);
    });

    it("非NFT所有者不能移除NFT", async function () {
      await expect(
        auction.connect(buyer).removeFromShelf(1)
      ).to.be.revertedWith("not owner");
    });
  });

  describe("管理员功能", function () {
    it("只有管理员可以升级合约", async function () {
      const newImplementation = ethers.Wallet.createRandom().address;

      // 非管理员不能升级
      await expect(
        auction.connect(buyer).upgrade(newImplementation)
      ).to.be.reverted;

      // 管理员可以升级
      await expect(
        auction.connect(owner).upgrade(newImplementation)
      ).to.not.be.reverted;

      expect(await auction.implementation()).to.equal(newImplementation);
    });

    it("只有管理员可以结束拍卖", async function () {
      // 非管理员不能结束拍卖
      await expect(
        auction.connect(buyer).end()
      ).to.be.reverted;

      // 注意：实际结束需要拍卖时间已过，这里只测试权限
    });
  });

  describe("手续费机制", function () {
    it("应该有合理的手续费常数", async function () {
      // 这些常量应该在合约中定义
      // MAX_FEE_PERCENT = 500 (5%)
      // MIN_FEE_PERCENT = 100 (1%)

      // 我们通过测试手续费计算来验证
      await auction.connect(seller).putOnShelf(1, ethers.parseEther("0.01"), ethers.parseEther("0.001"));

      const bidAmount = ethers.parseEther("0.01");
      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);
      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      await auction.connect(buyer).bid(1, { value: bidAmount });

      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;
      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;

      // 验证资金分配
      expect(sellerReceived).to.be.gt(0);
      expect(ownerReceived).to.be.gt(0);
      expect(sellerReceived + ownerReceived).to.be.gte(bidAmount * 95n / 100n);
    });
  });
});