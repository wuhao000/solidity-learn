// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockAggregatorV3
 * @dev Mock Chainlink price feed for testing purposes
 */
contract MockAggregatorV3 is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;
    uint256 private _updatedAt;
    string private _description;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
    event RoundData(int80 indexed roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    constructor(
        int256 initialPrice,
        uint8 decimalsValue,
        string memory descriptionValue
    ) {
        _price = initialPrice;
        _decimals = decimalsValue;
        _updatedAt = block.timestamp;
        _description = descriptionValue;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external view override returns (uint256) {
        return 1;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _price, _updatedAt, _updatedAt, 1);
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _updatedAt, _updatedAt, 1);
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
        _updatedAt = block.timestamp;
        emit AnswerUpdated(newPrice, 1, _updatedAt);
        emit RoundData(1, newPrice, _updatedAt, _updatedAt, 1);
    }

    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    function setDescription(string memory newDescription) external {
        _description = newDescription;
    }
}