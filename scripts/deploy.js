const { ethers } = require("hardhat");

async function main() {
  console.log("开始部署合约...");

  // 示例：部署一个简单的合约
  // 你可以根据需要修改这里来部署你的具体合约

  try {
    // 部署Voting合约
    console.log("正在部署 Voting 合约...");
    const Voting = await ethers.getContractFactory("voting");
    const voting = await Voting.deploy();
    await voting.waitForDeployment();
    console.log("Voting 合约部署地址:", await voting.getAddress());

    // 部署ERC20合约
    console.log("正在部署 ERC20 合约...");
    const ERC20 = await ethers.getContractFactory("ERC20");
    const erc20 = await ERC20.deploy("Test Token", "TEST", ethers.parseEther("1000000"));
    await erc20.waitForDeployment();
    console.log("ERC20 合约部署地址:", await erc20.getAddress());

    // 部署ERC721合约
    console.log("正在部署 ERC721 合约...");
    const ERC721 = await ethers.getContractFactory("ERC721");
    const erc721 = await ERC721.deploy("Test NFT", "TNFT");
    await erc721.waitForDeployment();
    console.log("ERC721 合约部署地址:", await erc721.getAddress());

    // 部署Auction合约
    console.log("正在部署 Auction 合约...");
    const Auction = await ethers.getContractFactory("Auction");
    const auction = await Auction.deploy(ethers.parseEther("1")); // 起拍价 1 ETH
    await auction.waitForDeployment();
    console.log("Auction 合约部署地址:", await auction.getAddress());

    console.log("所有合约部署完成！");

  } catch (error) {
    console.error("部署过程中出现错误:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });