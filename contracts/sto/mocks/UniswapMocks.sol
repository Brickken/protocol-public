// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { IUniswapV3Pair, IUniswapV3Router, IUniswapV3Factory, IUniswapV2Pair } from "../interfaces/UniswapInterfaces.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV2PairMock is IUniswapV2Pair {
    function getReserves() 
        external 
        view 
        returns (
            uint112 reserve0, 
            uint112 reserve1, 
            uint32 blockTimestampLast
        ) {
            return(
                uint112(100e18),
                uint112(400e6),
                uint32(block.timestamp)
            );
        }
}

contract UniswapV2PairMockV2 is IUniswapV2Pair {
    function getReserves() 
        external 
        view 
        returns (
            uint112 reserve0, 
            uint112 reserve1, 
            uint32 blockTimestampLast
        ) {
            return(
                uint112(100e18),
                uint112(400e6),
                uint32(block.timestamp - 30 days)
            );
        }
}

contract UniswapV3PairMock is IUniswapV3Pair {
    address private _token0;
    address private _token1;

    constructor(
        address newToken0,
        address newToken1
    ) {
        _token0 = newToken0;
        _token1 = newToken1;
    }

    function observe(
        uint32[] calldata secondsAgos
    )
        external
        pure
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        ) {
        
        int56[] memory ticks = new int56[](2);
        ticks[0] = int56(-22544792805753);
        ticks[1] = int56(-22544795464353);
        
        if(secondsAgos[0] == 112233) {
            ticks[1] = int56(-112234);
            ticks[0] = int56(-2);
        }

        uint160[] memory secondsCumulative = new uint160[](2);

        return(
            ticks,
            secondsCumulative
        );
    }

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }
}

contract UniswapV3FactoryMock is IUniswapV3Factory {
    IUniswapV3Pair private _pool;
    address private token0;
    address private token1;

    constructor(
        address newToken0,
        address newToken1
    ) {
        _pool = new UniswapV3PairMock(newToken0, newToken1);
        token0 = newToken0;
        token1 = newToken1;
    }

    function getPool(address a, address, uint24) external view returns(address pool) {
        if(a != token0 && a != token1) return address(0);
        pool = address(_pool);
    }
}

contract UniswapV3RouterMock is IUniswapV3Router {
    using SafeERC20 for IERC20;

    IUniswapV3Factory private _factory;
    IERC20 private token0;
    IERC20 private token1;

    constructor(
        address newToken0,
        address newToken1
    ) {
        _factory = new UniswapV3FactoryMock(newToken0, newToken1);
        token0 = IERC20(newToken0);
        token1 = IERC20(newToken1);
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        amountOut = uint256(100e6);
        token0.transferFrom(msg.sender, address(this), 100e18);
        token1.safeTransfer(params.recipient, amountOut);
        return amountOut;
    }

    function factory() external view returns(address) {
        return address(_factory);
    }
}