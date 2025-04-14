// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { ISTOToken } from "./ISTOToken.sol";
import { IChainlinkPriceFeed } from "./ChainlinkInterfaces.sol";
import { IUniswapV3Router } from "./UniswapInterfaces.sol";

interface IPriceAndSwapManager {

    /// @dev auxiliary struct referring to a specific offering and its details
    struct OfferingDetails {
        bool isEnded; // Whether the offering is still active or not
        uint256 hardCap; // configured hardcap to be reached
        uint256 minTicket; // configured minimum ticket that can be invested
        uint256 maxTicket; // configured maximum ticket that can be invested 
        uint256 priceInUSD; // configured price in USD of one token with 18 decimals
        uint256 raisedAmount; // how many USD have been raised so far
        uint256 issuanceIndex; // the index of the current issuance
    }

    /// @dev auxiliary struct referring to an investor of a specific offering.
    struct UserDetails {
        bool isUserInvestor; // whether the user is already an investor or not
        uint256 userAmountOfPaymentTokens; // how many paymentToken tokens the user is putting in
    }

    /// @dev auxiliary struct with all the details of the token used by the investor in the offering.
    struct TokenUsedDetails {
        bool isTokenWhitelisted; // whether the used token is whitelisted in the escrow contract
        address tokenAddress; // the used token address
        uint256 amountOfTokens; // the amount of tokens being sent by the user
        uint256 whitelistedTokenFeesOnSwap; // fees so that the right Uniswap pool can be selected
    }

    /// @dev auxiliary struct with all the details about the escrow from where the requests are coming from.
    struct EscrowDetails {
        address paymentToken; // the payment token configured in the escrow
        uint256 twapInterval; // TWAP interval to use in price validation of the payment token
        ISTOToken stoRelatedToken; // the address of the token related to the tokenization
        IChainlinkPriceFeed paymentTokenOracle; // oracle address to retrieve paymentToken price
        IUniswapV3Router router; // Uniswap v3 router to be used for swaps
    }

    /// @dev auxiliary struct with all the details about Uniswap pool of the token used (see TokenUsedDetails above).
    /// @dev This contains some redundant information with TokenUsedDetails but is not used concurrently with the TokenUsedDetails
    struct PoolDetails {
        address tokenAddress; // Token address being used for buying a ticket
        address paymentToken; // paymentToken configured in the escrow
        IUniswapV3Router router; // Uniswap v3 router used
        uint24 fees; // fees to select the right Uniswap v3 pool
    }

    /// @dev Method to estimate the amount of tokens that the user will get by participating in a specifing offering according to the current offering details.
    /// @param caller the user buying a ticket in the offering
    /// @param offeringDetails current details of the offering in which the user wish to participate
    /// @param userDetails whether the user is currently an investor and how many payment tokens is using
    /// @param tokenUsedDetails the details of the token being used by the investor to buy a ticket
    /// @param escrowDetails the details of the escrow calling this contract for every request
    /// @return expectedAmount the expected amount of tokens bought by the user
    function getEstimationSTOToken(
        address caller,
        OfferingDetails calldata offeringDetails,
        UserDetails calldata userDetails,
        TokenUsedDetails calldata tokenUsedDetails,
        EscrowDetails calldata escrowDetails
    ) external view returns (uint256 expectedAmount);

    /// @dev Method to retrieve the USD price of the paymentToken through its paymentTokenOracle with 18 decimals of precision
    /// @param paymentTokenOracle the oracle of the paymentToken to be priced
    /// @param twapInterval what twap interval should be used
    /// @return the USD price of the paymenToken in USD with 18 decimals of precision
    function getUSDPriceOfPaymentToken(IChainlinkPriceFeed paymentTokenOracle, uint256 twapInterval) external view returns (uint256);

    /// @dev Method to retrieve the price of a given token used by the user in terms of paymentToken, provided that a Uniswap v3 pool of such token against the paymentToken exists.
    /// @param poolDetails the Uniswap v3 pool of the token used against the paymentToken
    /// @param twapInterval what twap interval should be used
    /// @return price the price of the token used against the paymenToken with 18 decimals of precision
    function getPriceInPaymentToken(
        PoolDetails calldata poolDetails,
        uint256 twapInterval
    ) external view returns (uint256 price);

    /// @dev Method to swap a given token for paymentToken using an existing Uniswap v3 pool
    /// @param poolDetails the Uniswap v3 pool of the token used against the paymentToken
    /// @param tokenAmount the amount of tokens being swapped
    /// @param expectedAmount the expected amount of paymentToken to control slippage
    function swapTokensForPaymentTokens(
        PoolDetails calldata poolDetails,
        uint256 tokenAmount,
        uint256 expectedAmount
    ) external;

    /// @dev Method to reset all allowances in case the Uniswap router must be changed in the escrow contract
    /// @param oldAddress the old Uniswap router
    /// @param newAddress the new Uniswap router
    /// @param tokensERC20 the list of tokens whose allowances must be reset
    function resetAllowances(
        address oldAddress, 
        address newAddress,
        address[] memory tokensERC20
    ) external;

    /// @dev Method restricted in access to be called by the factory to allow/disallow specific escrows from calling this contract
    /// @param toBeSet the address of the escrow to allow/disallow
    /// @param status whether to allow it or not
    function setAllowed(address toBeSet, bool status) external;
}