const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("合约测试", function () {
  let voting;
  let erc20;
  let erc721;
  let auction;
  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // 部署Voting合约
    const Voting = await ethers.getContractFactory("Voting");
    voting = await Voting.deploy([owner.address, addr1.address, addr2.address]);
    await voting.waitForDeployment();

    // 部署ERC20合约
    const ERC20 = await ethers.getContractFactory("ERC20");
    erc20 = await ERC20.deploy("Test Token", "TEST");
    await erc20.waitForDeployment();

    // 部署ERC721合约
    const ERC721 = await ethers.getContractFactory("ERC721");
    erc721 = await ERC721.deploy("Test NFT", "TNFT");
    await erc721.waitForDeployment();

    // 部署Auction合约
    const Auction = await ethers.getContractFactory("Auction");
    const startTime = Math.floor(Date.now() / 1000) - 1800;
    const endTime = startTime + 3600;
    const priceDropInterval = 300;

    auction = await Auction.deploy(
      await erc721.getAddress(),
      owner.address,
      startTime,
      endTime,
      priceDropInterval
    );
    await auction.waitForDeployment();
  });

  describe("Voting 合约", function () {
    it("应该能够创建投票", async function () {
      // 这里需要根据你的voting合约的具体实现来编写测试
      console.log("Voting 合约地址:", await voting.getAddress());
      expect(await voting.getAddress()).to.be.properAddress;
    });
  });

  describe("ERC20 合约", function () {
    it("应该能够mint代币", async function () {
      await erc20.mint(ethers.parseEther("1000000"));
      const totalSupply = await erc20.totalSupply();
      expect(totalSupply).to.equal(ethers.parseEther("1000000"));
    });

    it("应该能够转账", async function () {
      await erc20.mint(ethers.parseEther("10000"));
      await erc20.transfer(addr1.address, ethers.parseEther("100"));
      const balance = await erc20.balanceOf(addr1.address);
      expect(balance).to.equal(ethers.parseEther("100"));
    });
  });

  describe("ERC721 合约", function () {
    it("应该能够mint NFT", async function () {
      await erc721.connect(addr1).mintNft(addr1.address, "test-uri");
      const ownerOf = await erc721.ownerOf(1);
      expect(ownerOf).to.equal(addr1.address);
    });
  });

  describe("Auction 合约", function () {
    it("应该正确设置拍卖时间", async function () {
      const startTime = await auction.startTime();
      const endTime = await auction.endTime();
      expect(endTime).to.be.gt(startTime);
    });
  });
});