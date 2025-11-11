// SPDX-License-Identifier: MIT
pragma solidity ^0.8;
// 拍卖合约 - 修改时间: 2025-11-10 19:43

import {ERC721} from "../task2/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAuction, AuctionInfo, TokenType} from "./IAuction.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Auction is IAuction, ReentrancyGuard, IERC721Receiver, UUPSUpgradeable, Initializable {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    uint256 constant MAX_FEE_PERCENT = 500;

    uint256 constant MIN_FEE_PERCENT = 100;

    address public override implementation;
    address public override admin;

    ERC721 public nft;
    /**
     * 拍卖开始时间
     */
    uint256 public startTime;
    /**
     * 拍卖结束时间
     */
    uint256 public endTime;

    /**
     * 价格衰减时间间隔（秒）
     */
    uint256 public priceDropInterval;
    /**
     * 合约所有者
     */
    address public owner;

    /**
     * 从开始时间到结束时间的衰减次数
     */
    uint256 public dropTimes;

    uint256 private _feePercentDropPerTime;

    /**
     * 拍卖品信息
     */
    mapping(uint256 => AuctionInfo) public shelf;

    mapping(address => mapping(TokenType => uint256)) private _winFunds;

    /**
     * 拍卖中的tokenId
     */
    uint256[] private _onShelf;

    /**
     * 代币 => 代币到usd的汇率预言机地址
     */
    mapping(TokenType => address) private _feedsAddress;

    /**
     * 代币的erc20合约地址
     */
    mapping(TokenType => address) private _tokenContractAddress;

    // 仅用于测试的函数
    bool public testMode;
    address public mockFeedAddress;

    constructor() {
        _disableInitializers();
    }

    // 初始化函数，代替构造函数
    function initialize(
        address _admin,
        address nftAddr,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _priceDropInterval
    ) public initializer {
        admin = _admin;
        owner = _admin;
        nft = ERC721(nftAddr);
        admin = owner; // 设置管理员为owner
        startTime = _startTime;
        endTime = _endTime;
        priceDropInterval = _priceDropInterval;
        dropTimes = (_endTime - _startTime) / _priceDropInterval;
        _feePercentDropPerTime = (MAX_FEE_PERCENT - MIN_FEE_PERCENT) / dropTimes;
        _feedsAddress[TokenType.DAI] = 0x14866185B1962B63C3Ea9E03Bc1da838bab34C19;
        _feedsAddress[TokenType.ETH] = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        _tokenContractAddress[TokenType.DAI] = 0x3e622317f8C93f7328350cF0B56d9eD4C620C5d6;
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function version() public pure returns (uint256) {
        return 2;
    }

    function _onlyOwner() internal view {
        require(msg.sender == owner, "not owner");
    }

    modifier isStarted() {
        _isStarted();
        _;
    }

    function _isStarted() internal view {
        require(block.timestamp <= endTime && block.timestamp >= startTime, "auction not started or ended.");
    }

    /**
     * 结束拍卖
     * @return 剩余未处理的拍卖品的数量
     */
    function end(uint256 limit) external payable onlyOwner returns (uint256) {
        require(limit > 0 && limit <= 20, "limit should between 1-20");
        require(block.timestamp > endTime, "not reach the end time");
        require(_onShelf.length > 0, "all handled.");
        for (uint256 i = 0; i < limit; i++) {
            if (_onShelf.length == 0) {
                return 0;
            }
            uint256 tokenId = _onShelf[_onShelf.length - 1];
            AuctionInfo storage info = shelf[tokenId];
            address oldOwner = info.owner;
            delete shelf[tokenId];
            _onShelf.pop();
            nft.safeTransferFrom(address(this), oldOwner, tokenId);
        }
        return _onShelf.length;
    }

    function getPrice(uint256 tokenId) public view returns (uint256) {
        AuctionInfo storage info = shelf[tokenId];
        if (block.timestamp < startTime) {
            return info.maxPrice;
        } else if (block.timestamp > endTime) {
            return info.minPrice;
        } else {
            uint256 elapsed = (block.timestamp - startTime) / priceDropInterval;
            uint256 dropPrice = elapsed * info.dropPerTime;
            if (dropPrice >= info.maxPrice - info.minPrice) {
                return info.minPrice;
            }
            return info.maxPrice - dropPrice;
        }
    }

    function _authorizeUpgrade(address newImplementation) internal {
        require(msg.sender == admin);
        implementation = newImplementation;
    }

    function withdraw() external {
        require(_winFunds[msg.sender][TokenType.ETH] > 0 || _winFunds[msg.sender][TokenType.DAI] > 0, "no funds.");
        _withdraw(TokenType.ETH);
        _withdraw(TokenType.DAI);
    }

    function _withdraw(TokenType tokenSymbol) internal {
        uint256 val = _winFunds[msg.sender][tokenSymbol];
        if (val > 0) {
            _winFunds[msg.sender][tokenSymbol] = 0;
            if (tokenSymbol == TokenType.ETH) {
                (bool success,) = msg.sender.call{value: val}("");
                require(success, "eth transfer failed");
            } else {
                IERC20 tokenContract = IERC20(_tokenContractAddress[tokenSymbol]);
                tokenContract.safeTransfer(msg.sender, val);
            }
        }
    }

    /**
     * Returns the latest answer.
     */
    function getChainlinkDataFeedLatestAnswer(TokenType symbol) public view returns (int256, uint8, uint256, uint256) {
        address feedAddress;

        if (testMode) {
            feedAddress = mockFeedAddress;
        } else {
            feedAddress = _feedsAddress[symbol];
        }

        AggregatorV3Interface dataFeed = AggregatorV3Interface(feedAddress);
        uint8 decimal = dataFeed.decimals();
        // prettier-ignore
        (
            /* uint80 roundId */
            ,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return (answer, decimal, startedAt, updatedAt);
    }

    /**
     * 仅用于测试：设置测试模式和Mock预言机地址
     */
    function setTestMode(bool _testMode, address _mockFeedAddress) external {
        require(msg.sender == admin, "only admin");
        testMode = _testMode;
        mockFeedAddress = _mockFeedAddress;
    }

    /**
     * 上架拍卖, 需提前授权nft给当前合约
     */
    function putOnShelf(uint256 tokenId, uint256 maxPrice, uint256 minPrice) external {
        require(nft.ownerOf(tokenId) == msg.sender, "not owner");
        require(shelf[tokenId].owner == address(0), "already on shelf");
        require(maxPrice >= minPrice, "max price less than min price");
        _onShelf.push(tokenId);
        uint256 dropPerTime = (maxPrice - minPrice) / dropTimes;
        shelf[tokenId] =
            AuctionInfo({maxPrice: maxPrice, minPrice: minPrice, dropPerTime: dropPerTime, owner: msg.sender});
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
    }

    function removeFromShelf(uint256 tokenId) external isStarted {
        require(shelf[tokenId].owner == msg.sender, "not owner");
        _removeToken(tokenId);
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function _removeToken(uint256 tokenId) private {
        delete shelf[tokenId];
        for (uint256 i = 0; i < _onShelf.length; i++) {
            if (_onShelf[i] == tokenId) {
                _onShelf[i] = _onShelf[_onShelf.length - 1];
                _onShelf.pop();
                break;
            }
        }
    }

    /**
     * 用代币出价竞拍
     */
    function bidWithToken(uint256 tokenId, TokenType tokenSymbol, uint256 tokenAmount) external isStarted nonReentrant {
        _bid(tokenId, tokenSymbol, tokenAmount);
    }

    /**
     * 出价，使用eth
     */
    function bid(uint256 tokenId) external payable isStarted nonReentrant {
        _bid(tokenId, TokenType.ETH, msg.value);
    }

    function _bid(uint256 tokenId, TokenType tokenSymbol, uint256 tokenValue) internal {
        AuctionInfo storage info = shelf[tokenId];
        require(info.owner != address(0), "not on shelf");
        _removeToken(tokenId);
        uint256 price = getPrice(tokenId);
        uint256 usd = getAuctionPriceUsd(tokenSymbol, tokenValue);
        require(usd >= price, "payment less than price");
        uint256 fee = _getFee(tokenValue);
        uint256 received = tokenValue - fee;
        _winFunds[info.owner][tokenSymbol] += received;
        _winFunds[owner][tokenSymbol] = fee;
        if (tokenSymbol != TokenType.ETH) {
            address addr = _tokenContractAddress[tokenSymbol];
            require(addr != address(0), "Token not supported");
            IERC20 tokenContract = IERC20(addr);
            tokenContract.safeTransferFrom(msg.sender, address(this), tokenValue);
        }
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function getAuctionPriceUsd(TokenType symbol, uint256 value) private view returns (uint256) {
        (int256 price, uint8 decimal,,) = getChainlinkDataFeedLatestAnswer(symbol);
        require(price > 0, "need price > 0");
        // forge-lint: disable-next-line(unsafe-typecast)
        return value * uint256(price) / (10 ** (18 + decimal));
    }

    /**
     * 动态手续费，从5%-1%随时间衰减
     */

    function _getFee(uint256 currentPrice) internal view returns (uint256) {
        uint256 percentage = MAX_FEE_PERCENT;
        if (block.timestamp >= startTime) {
            uint256 elapsed = (block.timestamp - startTime) / priceDropInterval;
            uint256 dropPercentage = elapsed * _feePercentDropPerTime;
            if (dropPercentage >= MAX_FEE_PERCENT - MIN_FEE_PERCENT) {
                percentage = MIN_FEE_PERCENT;
            } else {
                percentage = MAX_FEE_PERCENT - dropPercentage;
            }
        }
        return currentPrice * percentage / 10000;
    }

    /**
     * IERC721Receiver接口实现，允许接收NFT
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
