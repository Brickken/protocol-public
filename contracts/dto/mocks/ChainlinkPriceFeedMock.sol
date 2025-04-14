// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { IChainlinkPriceFeed } from "../interfaces/ChainlinkInterfaces.sol";

contract ChainlinkPriceFeedMock is IChainlinkPriceFeed {
    uint256 private counter;


    constructor() {
        counter = 2000;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function getRoundData(
        uint80 id
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            require(id != 1, "FAIL");
            return (
                id,
                int256(9983e5),
                0,
                uint256(block.timestamp)+counter,
                0
            );
        }


    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            return (
                4,
                int256(9983e5),
                0,
                block.timestamp,
                0
            );
        }
}

contract ChainlinkPriceFeedMockV2 is IChainlinkPriceFeed {
    uint256 private counter;


    constructor() {
        counter = 2000;
    }

    function decimals() external pure returns (uint8) {
        return 28;
    }

    function getRoundData(
        uint80 id
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            require(id != 1, "FAIL");
            return (
                id,
                int256(9983e5),
                0,
                uint256(block.timestamp)+counter,
                0
            );
        }


    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            return (
                4,
                int256(9983e5),
                0,
                block.timestamp,
                0
            );
        }
}

contract ChainlinkPriceFeedMockV3 is IChainlinkPriceFeed {
    uint256 private counter;


    constructor() {
        counter = 2000;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function getRoundData(
        uint80 id
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            require(id != 1, "FAIL");
            return (
                id,
                int256(-9983e5),
                0,
                uint256(block.timestamp)+counter,
                0
            );
        }


    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            return (
                4,
                int256(-9983e5),
                0,
                block.timestamp,
                0
            );
        }
}