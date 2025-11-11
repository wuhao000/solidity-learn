const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Auction 集成测试 - 完整拍卖流程", function () {
  let auction;
  let nft;
  let mockERC20;
  let owner, seller, buyer1, buyer2, buyer3;

  // 测试常量
  const NFT_TOKENS = [1, 2, 3, 4, 5];
  const START_TIME = Math.floor(Date.now() / 1000) - 1800; // 30分钟前开始
  const END_TIME = START_TIME + 3600; // 持续1小时
  const PRICE_DROP_INTERVAL = 300; // 5分钟

  beforeEach(async function () {
    [owner, seller, buyer1, buyer2, buyer3] = await ethers.getSigners();

    // 部署ERC721合约
    const ERC721 = await ethers.getContractFactory("ERC721");
    nft = await ERC721.deploy("Premium NFT Collection", "PNC");
    await nft.waitForDeployment();

    // 部署Mock ERC20合约
    const MockERC20 = await ethers.getContractFactory("ERC20");
    mockERC20 = await MockERC20.deploy("StableCoin", "USDC");
    await mockERC20.waitForDeployment();

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

    // 准备测试环境
    await setupTestEnvironment();
  });

  async function setupTestEnvironment() {
    // 为卖家mint NFT并授权
    for (let i = 0; i < NFT_TOKENS.length; i++) {
      await nft.connect(seller).mintNft(seller.address, `token-uri-${NFT_TOKENS[i]}`);
    }
    await nft.connect(seller).setApprovalForAll(await auction.getAddress(), true);

    // 给买家设置足够的ETH余额
    for (const buyer of [buyer1, buyer2, buyer3]) {
      await ethers.provider.send("hardhat_setBalance", [
        buyer.address,
        "0x" + ethers.parseEther("5000").toString(16)
      ]);
    }

    // 给买家分配代币
    await mockERC20.mint(ethers.parseEther("100000"));
    for (const buyer of [buyer1, buyer2, buyer3]) {
      await mockERC20.transfer(buyer.address, ethers.parseEther("10000"));
      await mockERC20.connect(buyer).approve(await auction.getAddress(), ethers.parseEther("10000"));
    }
  }

  describe("完整拍卖流程测试", function () {
    it("多个NFT的完整拍卖生命周期", async function () {
      // 1. 卖家上架多个NFT，设置不同的价格策略
      const auctions = [
        { tokenId: 1, maxPrice: ethers.parseEther("100"), minPrice: ethers.parseEther("20") },
        { tokenId: 2, maxPrice: ethers.parseEther("200"), minPrice: ethers.parseEther("50") },
        { tokenId: 3, maxPrice: ethers.parseEther("150"), minPrice: ethers.parseEther("30") }
      ];

      // 上架NFT
      for (const auction of auctions) {
        await expect(
          auction.connect(seller).putOnShelf(auction.tokenId, auction.maxPrice, auction.minPrice)
        ).to.emit(auction, "NFTListed")
          .withArgs(auction.tokenId, seller.address, auction.maxPrice, auction.minPrice);
      }

      // 验证NFT已转移到拍卖合约
      for (const auction of auctions) {
        expect(await nft.ownerOf(auction.tokenId)).to.equal(await auction.getAddress());
      }

      // 2. 买家检查当前价格并出价
      const currentPrices = [];
      for (const auction of auctions) {
        const price = await auction.getPrice(auction.tokenId);
        currentPrices.push(price);
        expect(price).to.be.gte(auction.minPrice);
        expect(price).to.be.lte(auction.maxPrice);
      }

      // 3. 不同的买家购买不同的NFT
      const purchases = [
        { buyer: buyer1, tokenId: 1, price: currentPrices[0] },
        { buyer: buyer2, tokenId: 2, price: currentPrices[1] },
        { buyer: buyer3, tokenId: 3, price: currentPrices[2] }
      ];

      // 记录购买前的余额
      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);
      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);
      const buyerBalancesBefore = {};
      for (const purchase of purchases) {
        buyerBalancesBefore[purchase.buyer.address] = await ethers.provider.getBalance(purchase.buyer.address);
      }

      // 执行购买
      for (const purchase of purchases) {
        await expect(
          auction.connect(purchase.buyer).bid(purchase.tokenId, { value: purchase.price })
        ).to.emit(auction, "NFTSold")
          .withArgs(purchase.tokenId, purchase.buyer.address, purchase.price);
      }

      // 4. 验证NFT所有权转移
      for (const purchase of purchases) {
        expect(await nft.ownerOf(purchase.tokenId)).to.equal(purchase.buyer.address);
      }

      // 5. 验证资金分配
      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

      const sellerReceived = sellerBalanceAfter - sellerBalanceBefore;
      const ownerReceived = ownerBalanceAfter - ownerBalanceBefore;

      // 卖家应该收到大部分资金
      expect(sellerReceived).to.be.gt(0);
      // 管理员应该收到手续费
      expect(ownerReceived).to.be.gt(0);

      // 6. 卖家和管理员提取资金
      await expect(auction.connect(seller).withdraw()).to.not.be.reverted;
      await expect(auction.connect(owner).withdraw()).to.not.be.reverted;
    });

    it("代币和ETH混合购买的完整流程", async function () {
      // 上架两个NFT
      await auction.connect(seller).putOnShelf(1, ethers.parseEther("100"), ethers.parseEther("20"));
      await auction.connect(seller).putOnShelf(2, ethers.parseEther("100"), ethers.parseEther("20"));

      // buyer1用ETH购买第一个NFT
      const ethPrice = await auction.getPrice(1);
      await auction.connect(buyer1).bid(1, { value: ethPrice });

      // buyer2用代币购买第二个NFT（需要足够大的代币数量来覆盖价格）
      const tokenAmount = ethers.parseEther("1000000"); // 大量代币确保价格足够
      await auction.connect(buyer2).bidWithToken(2, 1, tokenAmount); // 1代表DAI

      // 验证NFT分配
      expect(await nft.ownerOf(1)).to.equal(buyer1.address);
      expect(await nft.ownerOf(2)).to.equal(buyer2.address);

      // 验证双方都有资金可以提取
      await expect(auction.connect(seller).withdraw()).to.not.be.reverted;
      await expect(auction.connect(owner).withdraw()).to.not.be.reverted;
    });
  });

  describe("竞争性出价场景", function () {
    it("多个买家竞购同一NFT（先到先得）", async function () {
      // 上架一个热门NFT
      await auction.connect(seller).putOnShelf(1, ethers.parseEther("100"), ethers.parseEther("10"));

      const currentPrice = await auction.getPrice(1);

      // 第一个买家成功购买
      await expect(
        auction.connect(buyer1).bid(1, { value: currentPrice })
      ).to.not.be.reverted;

      // 第二个买家购买失败
      await expect(
        auction.connect(buyer2).bid(1, { value: currentPrice })
      ).to.be.revertedWith("not on shelf");

      // 第三个买家购买失败
      await expect(
        auction.connect(buyer3).bid(1, { value: currentPrice })
      ).to.be.revertedWith("not on shelf");

      // 验证NFT归第一个买家所有
      expect(await nft.ownerOf(1)).to.equal(buyer1.address);
    });

    it("价格随时间下降影响买家决策", async function () {
      // 上架NFT
      await auction.connect(seller).putOnShelf(1, ethers.parseEther("100"), ethers.parseEther("10"));

      const initialPrice = await auction.getPrice(1);

      // 模拟时间推进（通过创建新的拍卖合约）
      const futureTime = Math.floor(Date.now() / 1000) + 1800; // 30分钟后
      const FutureAuction = await ethers.getContractFactory("Auction");
      const futureAuction = await FutureAuction.deploy(
        await nft.getAddress(),
        owner.address,
        START_TIME,
        futureTime,
        PRICE_DROP_INTERVAL
      );
      await futureAuction.waitForDeployment();

      await nft.connect(seller).setApprovalForAll(await futureAuction.getAddress(), true);
      await futureAuction.connect(seller).putOnShelf(2, ethers.parseEther("100"), ethers.parseEther("10"));

      const laterPrice = await futureAuction.getPrice(2);

      // 后期价格应该低于初期价格
      expect(laterPrice).to.be.lt(initialPrice);
    });
  });

  describe("卖家行为测试", function () {
    it("卖家可以灵活管理拍卖中的NFT", async function () {
      // 上架多个NFT
      await auction.connect(seller).putOnShelf(1, ethers.parseEther("100"), ethers.parseEther("20"));
      await auction.connect(seller).putOnShelf(2, ethers.parseEther("150"), ethers.parseEther("30"));
      await auction.connect(seller).putOnShelf(3, ethers.parseEther("200"), ethers.parseEther("40"));

      // 移除一个NFT
      await auction.connect(seller).removeFromShelf(2);
      expect(await nft.ownerOf(2)).to.equal(seller.address);

      // 其他NFT仍在拍卖中
      expect(await nft.ownerOf(1)).to.equal(await auction.getAddress());
      expect(await nft.ownerOf(3)).to.equal(await auction.getAddress());

      // 卖出剩余的NFT
      const price1 = await auction.getPrice(1);
      const price3 = await auction.getPrice(3);

      await auction.connect(buyer1).bid(1, { value: price1 });
      await auction.connect(buyer2).bid(3, { value: price3 });

      // 验证最终状态
      expect(await nft.ownerOf(1)).to.equal(buyer1.address);
      expect(await nft.ownerOf(2)).to.equal(seller.address); // 被移除
      expect(await nft.ownerOf(3)).to.equal(buyer2.address);
    });

    it("卖家可以重新上架已移除的NFT", async function () {
      // 上架NFT
      await auction.connect(seller).putOnShelf(1, ethers.parseEther("100"), ethers.parseEther("20"));

      // 移除NFT
      await auction.connect(seller).removeFromShelf(1);
      expect(await nft.ownerOf(1)).to.equal(seller.address);

      // 重新上架
      await expect(
        auction.connect(seller).putOnShelf(1, ethers.parseEther("80"), ethers.parseEther("15"))
      ).to.not.be.reverted;

      // 确认NFT回到拍卖合约
      expect(await nft.ownerOf(1)).to.equal(await auction.getAddress());

      // 可以被购买
      const newPrice = await auction.getPrice(1);
      await auction.connect(buyer1).bid(1, { value: newPrice });
      expect(await nft.ownerOf(1)).to.equal(buyer1.address);
    });
  });

  describe("拍卖结束和清理", function () {
    it("管理员可以结束拍卖并处理剩余NFT", async function () {
      // 创建一个已经结束的拍卖合约
      const pastEnd = Math.floor(Date.now() / 1000) - 100;
      const EndedAuction = await ethers.getContractFactory("Auction");
      const endedAuction = await EndedAuction.deploy(
        await nft.getAddress(),
        owner.address,
        pastEnd - 3600,
        pastEnd,
        PRICE_DROP_INTERVAL
      );
      await endedAuction.waitForDeployment();

      await nft.connect(seller).setApprovalForAll(await endedAuction.getAddress(), true);

      // 上架一些NFT
      await endedAuction.connect(seller).putOnShelf(1, ethers.parseEther("100"), ethers.parseEther("20"));
      await endedAuction.connect(seller).putOnShelf(2, ethers.parseEther("150"), ethers.parseEther("30"));
      await endedAuction.connect(seller).putOnShelf(3, ethers.parseEther("200"), ethers.parseEther("40"));

      // 管理员结束拍卖
      const remainingCount = await endedAuction.connect(owner).end();
      expect(remainingCount).to.be.gt(0);

      // NFT应该返回给卖家
      expect(await nft.ownerOf(1)).to.equal(seller.address);
      expect(await nft.ownerOf(2)).to.equal(seller.address);
      expect(await nft.ownerOf(3)).to.equal(seller.address);
    });
  });

  describe("合约升级功能", function () {
    it("管理员可以升级合约实现", async function () {
      // 创建一个新的"实现"地址（这里用任意地址模拟）
      const newImplementation = ethers.Wallet.createRandom().address;

      // 只有管理员可以升级
      await expect(
        auction.connect(buyer1).upgrade(newImplementation)
      ).to.be.reverted;

      await expect(
        auction.connect(owner).upgrade(newImplementation)
      ).to.not.be.reverted;

      expect(await auction.implementation()).to.equal(newImplementation);
    });
  });

  describe("完整经济模型验证", function () {
    it("验证整个拍卖系统的经济模型", async function () {
      // 设置多个拍卖
      const auctions = [
        { tokenId: 1, max: ethers.parseEther("100"), min: ethers.parseEther("20") },
        { tokenId: 2, max: ethers.parseEther("200"), min: ethers.parseEther("50") },
        { tokenId: 3, max: ethers.parseEther("300"), min: ethers.parseEther("100") }
      ];

      // 记录初始状态
      const initialSellerBalance = await ethers.provider.getBalance(seller.address);
      const initialOwnerBalance = await ethers.provider.getBalance(owner.address);

      // 上架NFT
      for (const auction of auctions) {
        await auction.connect(seller).putOnShelf(auction.tokenId, auction.max, auction.min);
      }

      // 卖出一些NFT
      let totalRevenue = ethers.parseEther("0");
      let totalFees = ethers.parseEther("0");

      for (let i = 0; i < 2; i++) { // 只卖出前两个
        const price = await auction.getPrice(auctions[i].tokenId);
        totalRevenue += price;

        // 估算手续费（1%-5%）
        const estimatedFee = price * 3n / 100n; // 假设平均3%
        totalFees += estimatedFee;

        await auction.connect(buyer1).bid(auctions[i].tokenId, { value: price });
      }

      // 提取资金
      await auction.connect(seller).withdraw();
      await auction.connect(owner).withdraw();

      // 验证最终状态
      const finalSellerBalance = await ethers.provider.getBalance(seller.address);
      const finalOwnerBalance = await ethers.provider.getBalance(owner.address);

      const sellerProfit = finalSellerBalance - initialSellerBalance;
      const ownerProfit = finalOwnerBalance - initialOwnerBalance;

      // 卖家应该获得大部分收入
      expect(sellerProfit).to.be.gte(totalRevenue * 90n / 100n);

      // 管理员应该获得手续费
      expect(ownerProfit).to.be.gte(totalFees * 50n / 100n); // 考虑时间导致的费率变化

      // 第三个NFT仍可售出
      expect(await nft.ownerOf(3)).to.equal(await auction.getAddress());
    });
  });
});