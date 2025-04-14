// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { Roles } from "./Roles.sol";
import { Errors } from "./Errors.sol";
import { TickMath } from "./UniswapLibraries.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IChainlinkPriceFeed } from "../interfaces/ChainlinkInterfaces.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IUniswapV3Pair, IUniswapV3Factory, IUniswapV3Router } from "../interfaces/UniswapInterfaces.sol";
import { IPriceAndSwapManager } from "../interfaces/IPriceAndSwapManager.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title PriceAndSwapManager: contract that handles logic for the STOEscrowUpgradeable contract. Due to contract size limit we had to hand off this into a separate contract.
/// It abstracts away price recovery and swap logic. It supports Uniswap v3 pools and Chainlink price feeds.
/// This is a stateless, non upgradeable contract that is deployed once for every chain and to which all escrows will need to point to. 
/// If this needs to change, the factory has methods to change it accordingly to a newly deployed one.
/// @custom:security-contact tech@brickken.com
contract PriceAndSwapManager is IPriceAndSwapManager, Initializable {
    using Math for uint256;
    using SafeERC20 for IERC20Metadata;

    address public stoFactory;
    mapping(address caller => bool allowanceStatus) public allowedCaller;

    // Only contracts allowed by the factory can call functions with this modifer
    modifier onlyAllowed() {
        if(!allowedCaller[msg.sender]) revert Errors.UserIsNotWhitelisted(msg.sender);
        _;
    }

    // Only the factory contract can call functions with this modifer
    modifier onlyFactory() {
        if(msg.sender != stoFactory) revert Errors.UserIsNotAdmin(msg.sender);
        _;
    }

    function initialize(address _factory) external initializer {
        if(_factory == address(0)) revert Errors.NotZeroAddress();
        
        stoFactory = _factory;
    }

    /// @inheritdoc IPriceAndSwapManager
    function setAllowed(address toBeSet, bool status) external onlyFactory {
        allowedCaller[toBeSet] = status;
    }

    /// @inheritdoc IPriceAndSwapManager
    function getEstimationSTOToken(
        address caller,
        OfferingDetails calldata offeringDetails,
        UserDetails calldata userDetails,
        TokenUsedDetails calldata tokenUsedDetails,
        EscrowDetails calldata escrowDetails
    ) external view returns (uint256 expectedAmount) {
        
        uint256 actualAmount;

        if (
            (!escrowDetails.stoRelatedToken.hasRole(Roles.TOKEN_WHITELIST_ROLE, caller) && !escrowDetails.stoRelatedToken.whitelist_OLD_SLOT(caller)) ||
            offeringDetails.issuanceIndex == 0 ||
            offeringDetails.isEnded ||
            !tokenUsedDetails.isTokenWhitelisted ||
            offeringDetails.raisedAmount == offeringDetails.hardCap
        ) return(0);

        if (address(tokenUsedDetails.tokenAddress) != address(escrowDetails.paymentToken)) {
            uint256 priceInPaymentToken = getPriceInPaymentToken(
                PoolDetails(
                    address(tokenUsedDetails.tokenAddress),
                    address(escrowDetails.paymentToken),
                    escrowDetails.router,
                    uint24(tokenUsedDetails.whitelistedTokenFeesOnSwap)
                ),
                escrowDetails.twapInterval
            );

            uint256 amountOfPaymentTokens = tokenUsedDetails.amountOfTokens.mulDiv( // Amount of paymentTokens equivalent to the amount passed in
                priceInPaymentToken,
                10 ** IERC20Metadata(tokenUsedDetails.tokenAddress).decimals(),
                Math.Rounding.Down
            ); ///Rounding Down

            actualAmount = amountOfPaymentTokens;
        } else {
            actualAmount = tokenUsedDetails.amountOfTokens;
        }

        uint256 stoRelatedTokenScale = 10 ** escrowDetails.stoRelatedToken.decimals();

        uint256 usdPriceOfPaymentToken = getUSDPriceOfPaymentToken(
            escrowDetails.paymentTokenOracle, 
            escrowDetails.twapInterval
        );

        uint256 paymentTokenScale = 10 ** IERC20Metadata(escrowDetails.paymentToken).decimals();

        uint256 usdValue = actualAmount.mulDiv(
            usdPriceOfPaymentToken,
            paymentTokenScale,
            Math.Rounding.Down
        );

        if ( // alllow quantities less than minTicket only if what's left is minor than minTicket
            ((usdValue < offeringDetails.minTicket) &&
            (offeringDetails.hardCap - offeringDetails.raisedAmount) >= offeringDetails.minTicket) ||
            usdValue > offeringDetails.maxTicket // Disallow values for more than maxTicket
        ) return(0);

        // If investor already invested previously, check that his total ticket doesn't exceed maxTicket
        if(userDetails.isUserInvestor) {
            uint256 totalValue = (userDetails.userAmountOfPaymentTokens + actualAmount).mulDiv(
                usdPriceOfPaymentToken,
                paymentTokenScale,
                Math.Rounding.Down
            );

            if (totalValue > offeringDetails.maxTicket) return(0);
        }

        uint256 maxAmount;

        if (usdValue + offeringDetails.raisedAmount > offeringDetails.hardCap)
            {
                // Raised amount can never be greater than hardCap
                uint256 difference = offeringDetails.hardCap - offeringDetails.raisedAmount;
                maxAmount = difference.mulDiv(
                    paymentTokenScale, 
                    usdPriceOfPaymentToken, 
                    Math.Rounding.Up);
            }

        if(maxAmount > 0) {     
            actualAmount = maxAmount;
        }

        expectedAmount = actualAmount
            .mulDiv(
                usdPriceOfPaymentToken,
                paymentTokenScale,
                Math.Rounding.Up
            )
            .mulDiv(
                stoRelatedTokenScale,
                offeringDetails.priceInUSD,
                Math.Rounding.Down
            );
    }

    /// @inheritdoc IPriceAndSwapManager
    function getUSDPriceOfPaymentToken(
        IChainlinkPriceFeed paymentTokenOracle, 
        uint256 twapInterval
    ) public view returns (uint256) {

        // If the paymentTokenOracle is address(0) it returns unitari price as it means that
        // the corresponding paymentToken must not be priced.
        // This is expecially true for utility -> equity conversion where the price of the utility doesn't matter
        // Returning an unitary price means assigning the same number to amount and value of X tokens.
        if(address(paymentTokenOracle) == address(0)) {
            return uint256(1e18);
        }

        (uint80 roundId, int256 price, , uint256 updatedAt, ) = paymentTokenOracle.latestRoundData();
        int256 finalPrice = _getChainlinkTWAP(roundId, price, twapInterval, updatedAt, paymentTokenOracle);
        if(finalPrice < 0) revert Errors.NotNegativeValue(finalPrice);

        uint8 chainlinkDecimals = paymentTokenOracle.decimals();

        uint8 base = 18;
        if(chainlinkDecimals <= base) return uint256(finalPrice).mulDiv(10**(base-chainlinkDecimals), 1, Math.Rounding.Up);
        else return uint256(finalPrice).mulDiv(1, 10**(chainlinkDecimals - base), Math.Rounding.Up);
    }

    /// @inheritdoc IPriceAndSwapManager
    function getPriceInPaymentToken(
        PoolDetails memory poolDetails,
        uint256 twapInterval
    ) public view returns (uint256 price) {

        if (poolDetails.tokenAddress == address(poolDetails.paymentToken)) return 10**IERC20Metadata(poolDetails.paymentToken).decimals();

        IUniswapV3Pair pool = IUniswapV3Pair(
            IUniswapV3Factory(
                poolDetails.router.factory()
            ).getPool(
                poolDetails.tokenAddress, // The order doesn't matter since Uniswap populates mappings in both directions
                address(poolDetails.paymentToken), 
                uint24(poolDetails.fees)
            )
        );

        if(address(pool) == address(0)) revert Errors.NotZeroAddress();
        
        address poolToken0 = pool.token0();
        address poolToken1 = pool.token1();

        if ( 
            poolToken0 == address(poolDetails.paymentToken) && poolToken1 == poolDetails.tokenAddress 
        ) {
            address oldToken = poolToken0;
            poolToken0 = poolToken1;
            poolToken1 = oldToken;
        } else if(
            !(poolToken0 == poolDetails.tokenAddress && poolToken1 == address(poolDetails.paymentToken))
        ) revert Errors.WrongUniswapConfig();

        {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = uint32(twapInterval);
            secondsAgos[1] = 0;

            (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            int24 tick = int24(tickCumulativesDelta / int56(int256(twapInterval)));

            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int256(twapInterval) != 0)) {
                tick--;
            }
            
            price = uint256(
                TickMath.getQuoteAtTick(
                    tick, 
                    10 ** IERC20Metadata(poolDetails.tokenAddress).decimals(), 
                    poolDetails.tokenAddress, 
                    address(poolDetails.paymentToken)
                )
            );
        }

    }

    /// @inheritdoc IPriceAndSwapManager
    function resetAllowances(
        address oldAddress, 
        address newAddress,
        address[] memory tokensERC20
    ) external onlyAllowed {
        for (uint256 i = 0; i < tokensERC20.length;) {
            IERC20Metadata _token = IERC20Metadata(
                tokensERC20[i]
            );

            uint256 oldAllowance = _token.allowance(address(this), oldAddress);

            if (oldAllowance > 0) {
                _token.safeDecreaseAllowance(oldAddress, oldAllowance);
            }

            uint256 currentAllowance = _token.allowance(
                address(this),
                address(newAddress)
            );

            if (currentAllowance != 0) {
                _token.safeIncreaseAllowance(
                    address(newAddress),
                    oldAllowance
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IPriceAndSwapManager
    function swapTokensForPaymentTokens(
        PoolDetails calldata poolDetails,
        uint256 tokenAmount,
        uint256 expectedAmount
    ) external onlyAllowed {
        uint256 currentAllowance = IERC20Metadata(poolDetails.tokenAddress).allowance(address(this), address(poolDetails.router));
        
        if(currentAllowance <= tokenAmount) {
            IERC20Metadata(poolDetails.tokenAddress).safeIncreaseAllowance(address(poolDetails.router), tokenAmount - currentAllowance);
        }

        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: address(poolDetails.tokenAddress),
            tokenOut: address(poolDetails.paymentToken),
            fee: uint24(poolDetails.fees),
            recipient: msg.sender,
            amountIn: tokenAmount,
            amountOutMinimum: expectedAmount,
            sqrtPriceLimitX96: 0
        });

        poolDetails.router.exactInputSingle(params); // Uniswap reverts if outputAmount < expectedAmount with "Too little received"      
    }

    /// Internal functions

    /// @dev Calculate the TWAP of the retrieved Chainlink price
    function _getChainlinkTWAP(
        uint80 latestRoundId,
        int256 latestPrice,
        uint256 twapTimeInterval,
        uint256 latestUpdate,
        IChainlinkPriceFeed paymentTokenOracle
    ) internal view returns (int256) {
        int256 priceSum = latestPrice;
        uint256 priceCount = 1;

        uint256 startTime = latestUpdate - twapTimeInterval;

        while (latestRoundId > 0) {
            try paymentTokenOracle.getRoundData(--latestRoundId) returns (
                uint80,
                int256 answer,
                uint256,
                uint256 updatedAt,
                uint80
            ) {
                if (updatedAt < startTime) {
                    break;
                }
                priceSum += answer;
                priceCount++;
            } catch {
                break;
            }
        }

        return priceSum / int256(priceCount);
    }
}