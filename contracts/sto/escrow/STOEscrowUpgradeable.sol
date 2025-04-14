/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {Errors} from "../helpers/Errors.sol";
import {Roles} from "../helpers/Roles.sol";
import {ISTOToken} from "../interfaces/ISTOToken.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPriceAndSwapManager} from "../helpers/PriceAndSwapManager.sol";
import {IChainlinkPriceFeed} from "../interfaces/ChainlinkInterfaces.sol";
import {IUniswapV3Router, IUniswapV3Factory, IUniswapV3Pair} from "../interfaces/UniswapInterfaces.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20MetadataUpgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

/// @title STOEscrowUpgradeable
/// @custom:security-contact tech@brickken.com
contract STOEscrowUpgradeable is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address;
    using MathUpgradeable for uint256;

    /// @dev An issuance can be ACTIVE, WITHDRAWN (The issuance was successful and the issuer withdrawn),
    /// ROLLBACK (The issuance was not successful and the issuer has finalized it)
    enum IssuanceStatuses {
        ACTIVE,
        WITHDRAWN,
        ROLLBACK
    }

    /// @dev Issuance struct
    /// @param status Issuance status based on previous enum
    /// @param minTicket Min amount in USD (18 decimals) for issuance participation
    /// @param maxTicket Max amount in USD (18 decimals) for issuance participation
    /// @param startDate Unix timestamp of when the issuance will start
    /// @param endDate Unix timestamp of when the issuance will end
    /// @param hardCap Amount in USD (18 decimals) that can be collected at most
    /// @param softCap Amount in USD (18 decimals) that must be collected at least for an issuance to be succesfull
    /// @param raisedAmount Amount in USD (18 decimals) raised in the issuance so far
    /// @param issuanceAmount Amount of STO tokens issued
    /// @param priceInUSD Price in USD (18 decimals) of each STO token unit -> hardCap / issuanceAmount
    /// @param partialWithdraw Amount of paymentToken that has been already partially withdrawn (only if soft cap has been reached)
    /// @param paymentTokensCollected Amount of payment tokens that have been escrowed so far
    struct Issuance {
        IssuanceStatuses status;
        uint256 minTicket;
        uint256 maxTicket;
        uint256 startDate;
        uint256 endDate;
        uint256 hardCap;
        uint256 softCap;
        uint256 raisedAmount;
        uint256 issuanceAmount;
        uint256 priceInUSD;
        uint256 partialWithdraw;
        uint256 paymentTokensCollected;
    }

    /// @dev Struct to whitelist a new ERC20 token
    /// @param status status to enable or disable the token
    /// @param fees Fees of the pool to select (Uniswap might have different pools of same pairs with different fees)
    /// ERC20 tokens that are whitelisted must have:
    /// 1) A Uniswap v3 pool against the paymentToken
    /// 2) Enough liquidity
    /// 3) Since many pools of same pair but with different fees can exists, fees parameter is used to select the chose pool
    struct ERC20Token {
        bool status;
        uint24 fees;
    }

    /// @dev Investor struct
    /// @param redeemed whether the user has redeemed the STO tokens or not
    /// @param refunded whether the user has been refunded or not
    /// @param amountInPaymentToken Amount of paymentToken used to buy STO tokens in the issuance
    /// @param amountInSTO Amount of STO tokens estimated in this issuance
    struct Investor {
        bool redeemed;
        bool refunded;
        uint256 amountInPaymentToken;
        uint256 amountInSTO;
    }

    /// @dev Address of the STO token related to this escrow service
    ISTOToken public stoRelatedToken;

    /// @dev Address of the ERC20 token used for the issuer to withdraw the funds or investors being refunded
    IERC20MetadataUpgradeable public paymentToken;

    /// @dev Address of Uniswap v3 router to swap whitelisted ERC20 tokens to paymentToken
    IUniswapV3Router public router;

    /// @dev Address of the issuer of new STO token offerings
    address public issuer;

    ///@dev Treasury address
    address public treasuryAddress;

    /// @dev Array of Address ERC20 Token Whitelisted
    address[] private tokensERC20;

    /// @dev Fee for each withdraw in payment Token in each issuance. (from 1 to 10000, equivalent to 0.01% to 100%)
    uint256 public withdrawalFee;

    /// @dev Index of latest issuance
    uint256 public issuanceIndex;

    /// @dev Max fee limit in order to guarantee that fees for each withdraw doesn't exceed 100%
    uint256 public constant MAX_FEE_LIMIT = 1e4;

    /// @dev Mapping of ERC20 whitelisted tokens
    mapping(address tokenAddress => ERC20Token config)
        public tokenERC20Whitelist;

    /// @dev Issuances by issuance index
    mapping(uint256 index => Issuance info) public issuances;

    /// @dev Issuance Index ---> Address of investor ---> Investor struct
    mapping(uint256 issuanceIndex => mapping(address investorAddress => Investor info))
        public investors;

    /// @dev Chainlink price feed for paymentToken/USD conversion
    /// For paymentTokens that don't have a Chainlink Price Feed custom oracles can be used
    /// as long as they respect the Chainlink Price Feed interface.
    /// so for tokens that don't have a price, an oracle returning 1 can be used
    /// for tokens that have liquidity pools, an oracle that retrieves price from there and serve it through
    /// Chainlink interface can be used too. Usually, paymentToken is a stable, and this is needed to avoid depeg affecting the calculations
    /// So that issuer value is preserved.
    IChainlinkPriceFeed public paymentTokenOracle;

    /// @dev TWAP window that is configurable thorugh oracle configuration
    uint256 public twapInterval; // 15 minutes twap;

    /// @dev It manages swaps between the tokens that investors wants to use (it must be whitelisted in tokenERC20Whitelist)
    /// and the paymentToken so that the investors exclusively receives paymenToken. It uses Uniswap v3 so it only works
    /// with assets that have liquidity there. This is used only if the users decides to invest with a token different from
    /// paymentToken (if the ERC20 whitelist allows so).
    IPriceAndSwapManager public priceAndSwapManager;

    /// @dev Issuance Index ---> Address of payment token stored once an offering goes into rollabck
    mapping(uint256 issuanceIndex => address paymentTokenForRefund)
        public paymentTokensToRefund;

    /// @dev Issuance Index ---> Fee Accumulated in Payment Token
    mapping(uint256 issuanceIndex => uint256 feeAccumulatedInPaymentToken)
        internal feeAccumulated;

    /// Events

    /// @dev Event to signal that a new offering has been created
    /// @param issuanceIndex index of the new issuance
    /// @param issuance Initial struct of the new issuance
    event NewOffering(uint256 indexed issuanceIndex, Issuance issuance);

    /// @dev Event to signal that the list of whitelisted ERC20 tokens has changed
    /// @param issuer Issuer address
    /// @param token Array of ERC20 tokens where whitelist changed
    /// @param status Array of statuses applied to each ERC20 token
    event ERC20Whitelisted(
        address indexed issuer,
        address[] token,
        bool[] status
    );

    /// @dev Event to signal that an user redeemed his tokens
    /// @param investor User address
    /// @param issuanceIndex Index of the issuance
    /// @param amountInSTO Amount of STO token redeemed
    event Redeemed(
        address indexed investor,
        uint256 indexed issuanceIndex,
        uint256 indexed amountInSTO
    );

    /// @dev Event to signal that an user has been refunded
    /// @param investor User address
    /// @param issuanceIndex Index of the issuance
    /// @param amountInPaymentToken Amount of payment Token equivalent to the user investment that has been refunded
    event Refunded(
        address indexed investor,
        uint256 indexed issuanceIndex,
        uint256 indexed amountInPaymentToken
    );

    /// @dev Event to signal that an user made an offer to buy STO tokens
    /// @param investor User address
    /// @param ERC20Token ERC20 token used by the user
    /// @param issuanceIndex Index of the issuance
    /// @param amountInPaymentToken Amount of payment Token offered by the user
    /// @param amountInSTO Amount of STO tokens offered to the user
    event TicketOffered(
        address indexed investor,
        address indexed ERC20Token,
        uint256 indexed issuanceIndex,
        uint256 amountInPaymentToken,
        uint256 amountInSTO
    );

    /// @dev Event to signal that the issuer has withdrawn all the funds collected in the issuance
    /// @param issuer Issuer address
    /// @param issuanceIndex Index of the issuance
    /// @param fee Brickken success fee (amount of paymentToken)
    /// @param amountInPaymentToken Amount of payment Token raised in the issuance
    event Withdrawn(
        address indexed issuer,
        uint256 indexed issuanceIndex,
        uint256 fee,
        uint256 indexed amountInPaymentToken
    );

    /// @dev Event to signal that an issuance has entered into rollback state, funds will be refunded
    /// @param issuer Issuer address
    /// @param issuanceIndex Index of the issuance
    /// @param amountInPaymentToken Amount of payment Token raised during the issuance
    event RollBack(
        address indexed issuer,
        uint256 indexed issuanceIndex,
        uint256 indexed amountInPaymentToken
    );

    /// @dev Event to signal that the issuer has changed
    /// @param issuer New issuer address
    event ChangeIssuer(address indexed issuer);

    /// @dev Event to signal that the paymentToken change
    /// @param newPaymentTokenAddress paymentToken address
    /// @param newPaymentTokenOracle paymentTokenOracle address
    event ChangePaymentToken(
        address indexed newPaymentTokenAddress,
        address indexed newPaymentTokenOracle
    );

    /// @dev Event to signal that the PriceAndSwapManager change
    /// @param newPriceAndSwapManager the new address of the PriceAndSwapManager
    event ChangePriceAndSwapManager(address indexed newPriceAndSwapManager);

    /// @dev Event to signal that the router changed address
    /// @param newRouterAddress New router address
    event ChangeRouterAddress(address indexed newRouterAddress);

    /// @dev Event to signal that the success fee has changed, (from 1 to 10000, equivalent to 0.01% to 100%)
    /// @param oldFee Old fee percentage
    /// @param newFee New fee percentage
    event ChangeWithdrawalFee(uint256 indexed oldFee, uint256 indexed newFee);

    /// @dev Event to signal that the treasury address has changed
    /// @param oldTreasuryAddress Old treasury address
    /// @param newTreasuryAddress New treasury address
    event ChangeTreasuryAddress(
        address indexed oldTreasuryAddress,
        address indexed newTreasuryAddress
    );

    /// @dev Event emitted when buying tokens if the amount of USD value provided exceeds the hardcap
    /// @dev in these circumstances, only a partial amount of paymentTokens are used, the difference is sent back to the user
    /// @param partialTicket amount of STO tokens actually bought
    /// @param refund amount of paymentToken sent back to the user
    event PartialTicketBought(
        uint256 indexed partialTicket,
        uint256 indexed refund
    );

    /// @dev Event emitted when a ticket is bought offchain and reported onchain
    /// @param amount amount of STO tokens being reported
    /// @param to who should receive the corresponding tokens from this offchain ticket
    /// @param proofOfPayment proof of payment
    event OffchainReport(
        uint256 indexed amount,
        address indexed to,
        string indexed proofOfPayment
    );

    /// @dev Event to signal that an offering has been patched
    /// @param issuanceIndex index of the new issuance
    /// @param issuance Initial struct of the new issuance
    event OfferingPatched(uint256 indexed issuanceIndex, Issuance issuance);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Method for the user to either redeem the STO tokens or be refunded in paymentTokens
    /// @param index Index of the issuance
    /// @param onBehalfOf Address that will become the investor and receive the STO tokens or refund the paymentTokens
    function getTokens(
        uint256 index,
        address onBehalfOf
    ) external nonReentrant {
        address caller = _msgSender();

        if (
            !stoRelatedToken.hasRole(Roles.TOKEN_WHITELIST_ROLE, caller) &&
            !stoRelatedToken.whitelist_OLD_SLOT(caller)
        ) revert Errors.UserIsNotWhitelisted(caller);

        if (isSuccess(index)) {
            _redeemToken(index, onBehalfOf);
        } else {
            _refundToken(index, onBehalfOf);
        }
    }

    /// @dev Method to buy a ticket in the current offering
    /// @param tokenUsed ERC20 token to be used to buy the ticket
    /// @param amountOfTokens Amount of tokens to offer, exchanged for paymentToken. Decimals are the ones of the `tokenUsed`.
    /// @param minAmountExpected Minimum amount of payment tokens to obtain in exchange if swapping. This is for slippage control.
    /// @param onBehalfOf Address that will become the investor and receive the STO tokens or refund the paymentTokens
    function buyToken(
        address tokenUsed,
        uint256 amountOfTokens,
        uint256 minAmountExpected,
        address onBehalfOf
    ) external nonReentrant {
        address caller = _msgSender();
        uint256 actualAmount;

        _checkValidStatus(caller, tokenUsed, onBehalfOf);

        IERC20MetadataUpgradeable paymentTokenCached = paymentToken;
        Investor storage investor = investors[issuanceIndex][onBehalfOf];
        if (investor.redeemed) revert Errors.TokensAlreadyReedemed(onBehalfOf);

        if (tokenUsed != address(paymentTokenCached)) {
            bool isBalanceEnough = IERC20Upgradeable(tokenUsed).balanceOf(
                caller
            ) >= amountOfTokens;
            if (!isBalanceEnough)
                revert Errors.InsufficientBalance(
                    caller,
                    tokenUsed,
                    amountOfTokens
                );

            SafeERC20Upgradeable.safeTransferFrom(
                IERC20Upgradeable(tokenUsed),
                caller,
                address(priceAndSwapManager), // Send to priceAndSwapManager
                amountOfTokens
            );

            uint256 previewBalance = paymentTokenCached.balanceOf(
                address(this)
            );

            // This contract will be the receiver of the swap
            // Swap token for paymentToken
            priceAndSwapManager.swapTokensForPaymentTokens(
                IPriceAndSwapManager.PoolDetails(
                    tokenUsed,
                    address(paymentToken),
                    router,
                    tokenERC20Whitelist[tokenUsed].fees
                ),
                amountOfTokens,
                minAmountExpected
            );

            uint256 balance = paymentTokenCached.balanceOf(address(this));
            // Uniswap would have reverted if minAmountExpected is not satisfied
            actualAmount = balance - previewBalance;
        } else {
            SafeERC20Upgradeable.safeTransferFrom(
                IERC20Upgradeable(paymentTokenCached),
                caller,
                address(this),
                amountOfTokens
            );

            actualAmount = amountOfTokens;
        }

        uint256 usdPriceOfPaymentToken = priceAndSwapManager
            .getUSDPriceOfPaymentToken(paymentTokenOracle, twapInterval);

        uint256 maxAmount = _validateInputs(
            actualAmount,
            usdPriceOfPaymentToken,
            10 ** paymentTokenCached.decimals(), // paymentTokenScale,
            onBehalfOf
        );

        if (maxAmount > 0 && actualAmount > maxAmount) {
            // Send back the difference;
            SafeERC20Upgradeable.safeTransfer(
                paymentTokenCached,
                caller,
                actualAmount - maxAmount
            );
            emit PartialTicketBought(maxAmount, actualAmount - maxAmount);
            actualAmount = maxAmount;
        }

        // Avoid stack too deep error
        {
            /// Logic to store the ticket to the investor
            Issuance storage issuanceCached = issuances[issuanceIndex];

            uint256 actualValue = actualAmount.mulDiv(
                usdPriceOfPaymentToken,
                10 ** paymentTokenCached.decimals(), // paymentTokenScale
                MathUpgradeable.Rounding.Up
            );

            uint256 newAmountInSTO = actualValue.mulDiv(
                10 ** stoRelatedToken.decimals(), // stoRelatedTokenScale
                issuanceCached.priceInUSD,
                MathUpgradeable.Rounding.Down
            );

            uint256 newAmountInPaymentToken = investor.amountInPaymentToken +
                actualAmount;
            investor.amountInPaymentToken = newAmountInPaymentToken;
            investor.amountInSTO = investor.amountInSTO + newAmountInSTO;

            uint256 newRaisedAmount = issuanceCached.raisedAmount + actualValue;
            issuanceCached.raisedAmount = newRaisedAmount;

            // It shoudn't be greater than hardCap and it has been check before this point
            // but due to roundings we want to avoid the invariant to break on edge cases
            // In which the 100% of the raise has been reached but the rounding are some weis off
            if (newRaisedAmount > issuanceCached.hardCap)
                issuanceCached.raisedAmount = issuanceCached.hardCap;

            issuanceCached.paymentTokensCollected =
                issuanceCached.paymentTokensCollected +
                actualAmount;

            emit TicketOffered(
                onBehalfOf,
                tokenUsed,
                issuanceIndex,
                actualAmount,
                newAmountInSTO
            );
        }
    }

    /// @dev Method to getting the token Whitelisted
    /// @return result Array of whitelisted ERC20 tokens
    function getAllTokenERC20Whitelist()
        external
        view
        returns (address[] memory result)
    {
        uint256 index;
        uint256 length = tokensERC20.length;
        for (uint256 i = 0; i < length; ) {
            if (tokenERC20Whitelist[tokensERC20[i]].status) {
                unchecked {
                    ++index;
                }
            }
            unchecked {
                ++i;
            }
        }
        result = new address[](index);
        index = 0;
        for (uint256 j = 0; j < length; ) {
            address element = tokensERC20[j];
            if (tokenERC20Whitelist[element].status) {
                result[index] = element;
                unchecked {
                    ++index;
                }
            }
            unchecked {
                ++j;
            }
        }
    }

    /// Helpers

    /// @dev Method to estimate how many STO tokens are received based on amountOfTokens of tokenUsed
    /// @param tokenUsed Address of the ERC20 token used
    /// @param amountOfTokens Amount of tokenUsed tokens
    /// @return expectedAmount Amount of STO tokens expected to be received
    function getEstimationSTOToken(
        address tokenUsed,
        uint256 amountOfTokens
    ) external view returns (uint256 expectedAmount) {
        Issuance memory issuanceCached = issuances[issuanceIndex];
        address caller = _msgSender();

        return
            priceAndSwapManager.getEstimationSTOToken(
                caller,
                IPriceAndSwapManager.OfferingDetails(
                    isEnded(issuanceIndex),
                    issuanceCached.hardCap,
                    issuanceCached.minTicket,
                    issuanceCached.maxTicket,
                    issuanceCached.priceInUSD,
                    issuanceCached.raisedAmount,
                    issuanceIndex
                ),
                IPriceAndSwapManager.UserDetails(
                    isInvestor(issuanceIndex, caller),
                    investors[issuanceIndex][caller].amountInPaymentToken
                ),
                IPriceAndSwapManager.TokenUsedDetails(
                    tokenERC20Whitelist[tokenUsed].status,
                    tokenUsed,
                    amountOfTokens,
                    tokenERC20Whitelist[tokenUsed].fees
                ),
                IPriceAndSwapManager.EscrowDetails(
                    address(paymentToken),
                    twapInterval,
                    ISTOToken(stoRelatedToken),
                    IChainlinkPriceFeed(paymentTokenOracle),
                    IUniswapV3Router(router)
                )
            );
    }

    /// @dev Method to validate it tokenContract is part of the list of whitelisted ERC20 tokens
    /// @param tokenContract is the ERC20 contract to validate
    /// @return flag indicating if the token is whitelisted
    function isTokenERC20(address tokenContract) public view returns (bool) {
        uint256 length = tokensERC20.length;
        for (uint256 i = 0; i < length; ) {
            if (tokensERC20[i] == tokenContract) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @dev Method to validate if an issuance has started
    /// @param issuanceIndexQueried Index of the issuance
    /// @return True if the issuance started
    function isStarted(
        uint256 issuanceIndexQueried
    ) public view returns (bool) {
        return block.timestamp >= issuances[issuanceIndexQueried].startDate;
    }

    /// @dev Method to validate if an issuance has ended
    /// @param issuanceIndexQueried Index of the issuance
    /// @return True if the issuance ended
    function isEnded(uint256 issuanceIndexQueried) public view returns (bool) {
        return block.timestamp >= issuances[issuanceIndexQueried].endDate;
    }

    /// @dev Method to validate if an issuance is active
    /// @param issuanceIndexQueried Index of the issuance
    /// @return True if the issuance is active
    function isActive(uint256 issuanceIndexQueried) public view returns (bool) {
        return
            isStarted(issuanceIndexQueried) && !isEnded(issuanceIndexQueried);
    }

    /// @dev Method to validate if an issuance was succesfull
    /// @param issuanceIndexQueried Index of the issuance
    /// @return True if the issuance was succesfull
    function isSuccess(
        uint256 issuanceIndexQueried
    ) public view returns (bool) {
        return
            issuances[issuanceIndexQueried].raisedAmount >=
            issuances[issuanceIndexQueried].softCap;
    }

    /// @dev Method validate if the issuance is in rollback state
    /// @param issuanceIndexQueried Index of the Issuance Process
    /// @return True if the issuance is in rollback state
    function isRollback(
        uint256 issuanceIndexQueried
    ) public view returns (bool) {
        return
            issuances[issuanceIndexQueried].status == IssuanceStatuses.ROLLBACK;
    }

    /// @dev Method to validate if the issuance reached hardCap
    /// @param issuanceIndexQueried Index of the Issuance Process
    /// @return True if the issuance raisedAmount is equal to hardCap
    function isHardcapReached(
        uint256 issuanceIndexQueried
    ) public view returns (bool) {
        return
            issuances[issuanceIndexQueried].raisedAmount ==
            issuances[issuanceIndexQueried].hardCap;
    }

    /// @dev Method validate if the issuance is in withdrawn state
    /// @param issuanceIndexQueried Index of the Issuance Process
    /// @return True if the issuance is in withdrawn state
    function isWithdrawn(
        uint256 issuanceIndexQueried
    ) public view returns (bool) {
        return
            issuances[issuanceIndexQueried].status ==
            IssuanceStatuses.WITHDRAWN;
    }

    /// @dev Method if an user position has been redeemed or not
    /// @param issuanceIndexQueried Index of the issuance
    /// @param user Address of the user/investor
    /// @return True if the has reedemed the STO tokens
    function isRedeemed(
        uint256 issuanceIndexQueried,
        address user
    ) public view returns (bool) {
        return investors[issuanceIndexQueried][user].redeemed;
    }

    /// @dev Method if a user position has been refunded or not
    /// @param issuanceIndexQueried Index of the issuance
    /// @param user Address of the user/investor
    /// @return True if the has been refunded
    function isRefunded(
        uint256 issuanceIndexQueried,
        address user
    ) public view returns (bool) {
        return investors[issuanceIndexQueried][user].refunded;
    }

    /// @dev Method to validate if an user is an investor in the issuance
    /// @param issuanceIndexQueried Index of the issuance
    /// @param user Address of the user/investor
    /// @return True if the user has an opened position in the issuance
    function isInvestor(
        uint256 issuanceIndexQueried,
        address user
    ) public view returns (bool) {
        return
            investors[issuanceIndexQueried][user].amountInSTO > 0 &&
            // investors[issuanceIndexQueried][user].amountInPaymentToken > 0 && Removed to allow offchain reported users to redeem tokens
            !investors[issuanceIndexQueried][user].redeemed &&
            !investors[issuanceIndexQueried][user].refunded;
    }

    /// @dev Method to calculate amount of USD left that can be invested
    /// @dev It is equal or less to the max ticket allowed per investor in the issuance
    function amountAvailable(
        uint256 issuanceIndexQueried
    ) external view returns (uint256) {
        if (
            isActive(issuanceIndexQueried) &&
            !isHardcapReached(issuanceIndexQueried)
        ) {
            Issuance memory issuanceCached = issuances[issuanceIndexQueried];
            return
                issuanceCached.hardCap - issuanceCached.raisedAmount >
                    issuanceCached.maxTicket
                    ? issuanceCached.maxTicket
                    : issuanceCached.hardCap - issuanceCached.raisedAmount;
        } else {
            return 0;
        }
    }

    /// @dev Method to get accumulated fee amount in payment token (18 decimals)
    /// @param issuanceIndexQueried Index of the Issuance Process
    /// @return _feeAccumulated Accumulated fee amount
    function getFeeAccumulated(
        uint256 issuanceIndexQueried
    ) public view returns (uint256 _feeAccumulated) {
        _feeAccumulated = feeAccumulated[issuanceIndexQueried];
        // backwards compatibility for old issuances
        if (_feeAccumulated == 0) {
            Issuance memory issuanceCached = issuances[issuanceIndexQueried];
            if (issuanceCached.partialWithdraw > 0) {
                _feeAccumulated = issuanceCached.partialWithdraw.mulDiv(
                    withdrawalFee,
                    MAX_FEE_LIMIT,
                    MathUpgradeable.Rounding.Down
                );
            }
        }
        return _feeAccumulated;
    }

    /// @dev Method to get the price of 1 token of tokenAddress if swapped for paymentToken
    /// @param tokenAddress ERC20 token address of a whitelisted ERC20 token
    /// @return price in paymentToken equivalent with its decimals
    function getPriceInPaymentToken(
        address tokenAddress
    ) public view returns (uint256) {
        return
            priceAndSwapManager.getPriceInPaymentToken(
                IPriceAndSwapManager.PoolDetails(
                    tokenAddress,
                    address(paymentToken),
                    router,
                    tokenERC20Whitelist[tokenAddress].fees
                ),
                twapInterval
            );
    }

    /// @dev Method to get the price of 1 token of paymentToken in USD price
    /// @return price in USD of 1 paymentToken unit, scaled to 18 decimals
    function getUSDPriceOfPaymentToken() public view returns (uint256) {
        return
            priceAndSwapManager.getUSDPriceOfPaymentToken(
                paymentTokenOracle,
                twapInterval
            );
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function version() external view returns (uint8) {
        return _getInitializedVersion();
    }

    // INTERNAL / PRIVATE FUNCTIONS

    /// @dev initializable function called by parent contract
    function __STOEscrowUpgradeable_init(
        address _stoToken,
        address _newIssuer,
        address _paymentToken,
        address _router,
        address _paymentTokenOracle,
        bool _paymentTokenOracleUnused,
        address _treasuryAddress,
        address _priceAndSwapManager
    ) internal {
        if (_newIssuer == address(0) || _treasuryAddress == address(0))
            revert Errors.NotZeroAddress();

        if (!_paymentTokenOracleUnused && _paymentTokenOracle == address(0))
            revert Errors.NotZeroAddress();

        if (
            !_stoToken.isContract() ||
            !_paymentToken.isContract() ||
            !_router.isContract() ||
            !_priceAndSwapManager.isContract()
        ) revert Errors.NotContractAddress();

        __ReentrancyGuard_init();

        stoRelatedToken = ISTOToken(_stoToken);
        router = IUniswapV3Router(_router);
        priceAndSwapManager = IPriceAndSwapManager(_priceAndSwapManager);

        issuer = _newIssuer;
        treasuryAddress = _treasuryAddress;
        withdrawalFee = 300; /// 3%

        ERC20Token storage tokenStructNew = tokenERC20Whitelist[_paymentToken];

        tokenStructNew.status = true;

        paymentTokenOracle = IChainlinkPriceFeed(_paymentTokenOracle);
        paymentToken = IERC20MetadataUpgradeable(_paymentToken);

        twapInterval = 60 * 15;
    }

    /// @dev Method to change the issuer of the contract
    /// @param newIssuer The new issuer
    function _changeIssuer(address newIssuer) internal {
        if (newIssuer == address(0)) revert Errors.NotZeroAddress();

        issuer = newIssuer;
    }

    /// @dev Method to change the Uniswap router address
    /// @param newRouter Address of the new router contract
    /// This function should not be called with an active issuance going on
    function _setRouter(address newRouter) internal {
        if (!newRouter.isContract()) revert Errors.NotContractAddress();

        address oldRouter = address(router);
        router = IUniswapV3Router(newRouter);

        priceAndSwapManager.resetAllowances(oldRouter, newRouter, tokensERC20);
    }

    /// @dev Method to change the current PriceAndSwapManager. Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newPriceAndSwapManager address of the new PriceAndSwapManager.
    function _setPriceAndSwapManager(address newPriceAndSwapManager) internal {
        if (!newPriceAndSwapManager.isContract())
            revert Errors.NotContractAddress();

        priceAndSwapManager = IPriceAndSwapManager(newPriceAndSwapManager);
    }

    /// @dev Method to change the list of whitelisted ERC20 tokens
    /// @param tokensToChange Array of ERC20 tokens to be changed in the whitelist
    /// @param statuses Array of statuses for each ERC20 token
    /// @param fees Array of Uniswap fees to select the right pool
    function _changeWhitelist(
        address[] calldata tokensToChange,
        bool[] calldata statuses,
        uint24[] calldata fees
    ) internal {
        if (
            tokensToChange.length != statuses.length &&
            statuses.length != fees.length
        ) revert Errors.LengthsMismatch();

        for (uint256 i = 0; i < tokensToChange.length; i++) {
            address token = tokensToChange[i];

            if (!token.isContract()) revert Errors.NotContractAddress();

            if (!isTokenERC20(token)) tokensERC20.push(token);

            uint256 allowance = IERC20Upgradeable(token).allowance(
                address(this),
                address(router)
            );

            tokenERC20Whitelist[token].status = statuses[i];
            tokenERC20Whitelist[token].fees = fees[i];

            if (statuses[i] && allowance != type(uint256).max) {
                SafeERC20Upgradeable.safeIncreaseAllowance(
                    IERC20Upgradeable(token),
                    address(router),
                    type(uint256).max - allowance
                );
            } else if (!statuses[i] && allowance > 0) {
                SafeERC20Upgradeable.safeDecreaseAllowance(
                    IERC20Upgradeable(token),
                    address(router),
                    allowance
                );
            }
        }
    }

    /// @dev Method to change the withdrawal fee (success fee)
    /// @param newFee Fee to be charged for withdrawal
    function _changeWithdrawalFee(uint256 newFee) internal {
        if (newFee > MAX_FEE_LIMIT) revert Errors.FeeOverLimits(newFee);
        withdrawalFee = newFee;
    }

    /// @dev Method to change the treasury address
    /// @param _newTreasuryAddress Address of the new treasury
    function _changeTreasuryAddress(address _newTreasuryAddress) internal {
        if (_newTreasuryAddress == address(0)) revert Errors.NotZeroAddress();
        treasuryAddress = _newTreasuryAddress;
    }

    /// @dev Method to start a new offering
    /// @param newIssuance Struct with all the data of the new issuance
    function _newOffering(Issuance calldata newIssuance) internal {
        address caller = _msgSender();
        uint256 issuanceIndexCached = issuanceIndex;

        if (
            (issuanceIndexCached != 0) &&
            !(isWithdrawn(issuanceIndexCached) ||
                isRollback(issuanceIndexCached))
        ) revert Errors.IssuanceNotFinalized(caller);

        if (
            newIssuance.maxTicket < newIssuance.minTicket ||
            newIssuance.startDate < block.timestamp ||
            newIssuance.endDate <= newIssuance.startDate ||
            newIssuance.hardCap < newIssuance.softCap ||
            newIssuance.paymentTokensCollected != 0 ||
            newIssuance.partialWithdraw != 0 ||
            newIssuance.raisedAmount != 0 ||
            newIssuance.issuanceAmount == 0 ||
            newIssuance.priceInUSD !=
            newIssuance.hardCap.mulDiv(1 ether, newIssuance.issuanceAmount)
        ) revert Errors.InitialValueWrong(caller);

        ISTOToken stoRelatedTokenCached = stoRelatedToken;

        if (
            stoRelatedTokenCached.supplyCap() > 0 &&
            newIssuance.issuanceAmount >
            (stoRelatedTokenCached.supplyCap() -
                stoRelatedTokenCached.totalSupply())
        ) revert Errors.SupplyCapExceeded();

        if (
            newIssuance.issuanceAmount + stoRelatedTokenCached.totalSupply() >
            type(uint224).max
        ) revert Errors.MaxSupplyExceeded();

        ++issuanceIndex;
        issuanceIndexCached = issuanceIndex;

        issuances[issuanceIndexCached] = Issuance({
            status: IssuanceStatuses.ACTIVE,
            minTicket: newIssuance.minTicket,
            maxTicket: newIssuance.maxTicket,
            startDate: newIssuance.startDate,
            endDate: newIssuance.endDate,
            hardCap: newIssuance.hardCap,
            softCap: newIssuance.softCap,
            raisedAmount: 0,
            issuanceAmount: newIssuance.issuanceAmount,
            priceInUSD: newIssuance.priceInUSD,
            partialWithdraw: 0,
            paymentTokensCollected: 0
        });
    }

    /// @dev Method to finalize an issuance
    /// @param withdrawTo address to which the issuer wants to send the withdrawn amount of paymentToken
    function _finalizeIssuance(address withdrawTo) internal nonReentrant {
        address caller = _msgSender();
        uint256 issuanceIndexCached = issuanceIndex;

        _checkIssuanceCompleteness(caller, issuanceIndexCached);

        if (isSuccess(issuanceIndexCached)) {
            _withdraw(withdrawTo);
        } else {
            _rollBack();
        }
    }

    /// @dev Internal method to check whether the issuance is started AND ended
    function _checkIssuanceCompleteness(
        address caller,
        uint256 index
    ) internal view {
        if (index == 0) revert Errors.IssuanceNotStarted(caller);

        if (!isStarted(index)) revert Errors.IssuanceNotStarted(caller);

        if (!isEnded(index) && !isHardcapReached(index))
            revert Errors.IssuanceNotEnded(caller, issuances[index].endDate);
    }

    /// @dev Internal method to check whether the issuance is valid status and that the caller and the token are whitelisted
    function _checkValidStatus(
        address caller,
        address tokenUsed,
        address onBehalfOf
    ) internal view {
        uint256 issuanceIndexCached = issuanceIndex;

        uint256 endDate = issuances[issuanceIndexCached].endDate;
        uint256 raisedAmount = issuances[issuanceIndexCached].raisedAmount;
        uint256 hardCap = issuances[issuanceIndexCached].hardCap;

        if (
            !stoRelatedToken.hasRole(Roles.TOKEN_WHITELIST_ROLE, caller) &&
            !stoRelatedToken.whitelist_OLD_SLOT(caller)
        ) revert Errors.UserIsNotWhitelisted(caller);

        if (onBehalfOf != caller) {
            if (
                !stoRelatedToken.hasRole(
                    Roles.TOKEN_WHITELIST_ROLE,
                    onBehalfOf
                ) && !stoRelatedToken.whitelist_OLD_SLOT(onBehalfOf)
            ) revert Errors.UserIsNotWhitelisted(onBehalfOf);
        }

        if (issuanceIndexCached == 0)
            revert Errors.IssuanceNotStarted(onBehalfOf);

        if (!isStarted(issuanceIndexCached))
            revert Errors.IssuanceNotStarted(onBehalfOf);

        if (isEnded(issuanceIndexCached))
            revert Errors.IssuanceEnded(onBehalfOf, endDate);

        if (!tokenERC20Whitelist[tokenUsed].status)
            revert Errors.TokenIsNotWhitelisted(tokenUsed, onBehalfOf);

        if (raisedAmount == hardCap) revert Errors.HardCapRaised();
    }

    /// @dev internal method to check if the caller try to buy the rest of the issuance, and the value is less than the minTicket
    /// @param amount Amount of tokens to buy
    /// @param usdPriceOfPaymentToken Price of 1 paymentToken in USD
    /// @param paymentTokenScale Scale of the paymentToken
    /// @param onBehalfOf Address of the investor
    /// @return usdValue Value in USD of the amount of tokens to buy
    function _validateInputs(
        uint256 amount,
        uint256 usdPriceOfPaymentToken,
        uint256 paymentTokenScale,
        address onBehalfOf
    ) internal view returns (uint256) {
        Issuance storage issuanceCached = issuances[issuanceIndex];

        uint256 usdValue = amount.mulDiv(
            usdPriceOfPaymentToken,
            paymentTokenScale,
            MathUpgradeable.Rounding.Down
        );

        uint256 minTicket = issuanceCached.minTicket;
        uint256 raisedAmount = issuanceCached.raisedAmount;
        uint256 hardCap = issuanceCached.hardCap;

        if (
            // alllow quantities less than minTicket only if what's left is minor than minTicket
            (usdValue < minTicket) && (hardCap - raisedAmount) >= minTicket
        ) revert Errors.InsufficientAmount(onBehalfOf, usdValue, minTicket);

        uint256 maxTicket = issuanceCached.maxTicket;

        if (usdValue > maxTicket)
            revert Errors.AmountExceeded(onBehalfOf, usdValue, maxTicket);

        // If investor already invested previously, check that his total ticket doesn't exceed maxTicket
        if (isInvestor(issuanceIndex, onBehalfOf)) {
            uint256 amountInSTO = investors[issuanceIndex][onBehalfOf]
                .amountInSTO;

            uint256 actualAmountInPaymentToken = amountInSTO
                .mulDiv(
                    issuanceCached.priceInUSD,
                    10 ** stoRelatedToken.decimals(), // stoRelatedTokenScale,
                    MathUpgradeable.Rounding.Up
                )
                .mulDiv(
                    10 ** paymentToken.decimals(),
                    usdPriceOfPaymentToken,
                    MathUpgradeable.Rounding.Down
                );

            uint256 newAmountInPaymentToken = actualAmountInPaymentToken +
                amount;

            uint256 totalValue = newAmountInPaymentToken.mulDiv(
                usdPriceOfPaymentToken,
                paymentTokenScale,
                MathUpgradeable.Rounding.Down
            );

            if (totalValue > maxTicket)
                revert Errors.AmountExceeded(
                    onBehalfOf,
                    newAmountInPaymentToken,
                    maxTicket
                );
        }

        if (usdValue + raisedAmount > hardCap) {
            // Raised amount can't be greater than hardCap
            uint256 difference = hardCap - raisedAmount;
            return (
                difference.mulDiv(
                    paymentTokenScale,
                    usdPriceOfPaymentToken,
                    MathUpgradeable.Rounding.Up
                )
            );
        }

        return (0);
    }

    /// @dev Internal method for the investor to redeem the STO tokens bought
    /// @param index Index of the issuance
    /// @param onBehalfOf Address that will become the investor and receive the STO tokens
    function _redeemToken(uint256 index, address onBehalfOf) internal {
        if (isRedeemed(index, onBehalfOf))
            revert Errors.RedeemedAlready(onBehalfOf, index);

        if (!isInvestor(index, onBehalfOf))
            revert Errors.NotInvestor(onBehalfOf, index);

        if (!isWithdrawn(index) && issuances[index].partialWithdraw == 0)
            revert Errors.IssuanceNotWithdrawn(issuer);

        uint256 amountInSTO = investors[index][onBehalfOf].amountInSTO;

        investors[index][onBehalfOf].redeemed = true;

        stoRelatedToken.mint(onBehalfOf, amountInSTO);

        emit Redeemed(onBehalfOf, index, amountInSTO);
    }

    /// @dev Internal method for the investor to be refunded during paymentToken
    /// @param index Index of the issuance
    /// @param onBehalfOf Address that will become the investor and refund the paymentTokens
    function _refundToken(uint256 index, address onBehalfOf) internal {
        if (isRefunded(index, onBehalfOf))
            revert Errors.RefundedAlready(onBehalfOf, index);

        if (!isInvestor(index, onBehalfOf))
            revert Errors.NotInvestor(onBehalfOf, index);

        if (!isRollback(index)) revert Errors.IssuanceNotInRollback(index);

        uint256 amountInPaymentToken = investors[index][onBehalfOf]
            .amountInPaymentToken;

        address paymentTokenUsed = paymentTokensToRefund[index];

        // Here there might be an attempt of an user who has been
        // offchain reported to try to get a refund.
        // In this case amountInPaymentToken is 0 and will revert.

        investors[index][onBehalfOf].refunded = true;

        SafeERC20Upgradeable.safeTransfer(
            IERC20Upgradeable(paymentTokenUsed),
            onBehalfOf,
            amountInPaymentToken
        );

        emit Refunded(onBehalfOf, index, amountInPaymentToken);
    }

    /// @dev Internal method to partially withdraw payment token if issuance is succesfull
    /// @param amountToWithdraw Amount of payment token to withdraw
    /// @param withdrawTo address to which the issuer wants to send the withdrawn amount of paymentToken
    function _partialWithdraw(
        uint256 amountToWithdraw,
        address withdrawTo
    ) internal {
        uint256 issuanceIndexCached = issuanceIndex;
        uint256 partialWithdrawn = issuances[issuanceIndexCached]
            .partialWithdraw;
        (
            ,
            uint256 feeToPay,
            uint256 amountToReceive,
            uint256 feeCoverageShortfall
        ) = getFeeEstimation(amountToWithdraw);

        if (feeCoverageShortfall > 0) {
            revert Errors.FeeExceedsBalance(feeToPay, feeCoverageShortfall);
        }

        SafeERC20Upgradeable.safeTransfer(
            paymentToken,
            treasuryAddress,
            feeToPay
        );
        feeAccumulated[issuanceIndexCached] += feeToPay;

        SafeERC20Upgradeable.safeTransfer(
            paymentToken,
            withdrawTo,
            amountToReceive
        );

        issuances[issuanceIndexCached].partialWithdraw =
            partialWithdrawn +
            amountToWithdraw;

        emit Withdrawn(issuer, issuanceIndexCached, feeToPay, amountToReceive);
    }

    /// @dev Internal method to withdraw the payment token funds after a successfull issuance
    /// @dev Brickken is getting a successfull fee
    function _withdraw(address withdrawTo) internal {
        uint256 issuanceIndexCached = issuanceIndex;
        if (isWithdrawn(issuanceIndexCached))
            revert Errors.IssuanceWasWithdrawn(issuer);

        uint256 amount = issuances[issuanceIndexCached].paymentTokensCollected -
            issuances[issuanceIndexCached].partialWithdraw;

        issuances[issuanceIndexCached].status = IssuanceStatuses.WITHDRAWN;

        _partialWithdraw(amount, withdrawTo);
    }

    /// @dev Internal method to rollback the payment Token funds after an unsuccessfull issuance
    function _rollBack() internal {
        uint256 issuanceIndexCached = issuanceIndex;
        if (isRollback(issuanceIndexCached))
            revert Errors.IssuanceWasRollbacked(issuer);

        issuances[issuanceIndexCached].status = IssuanceStatuses.ROLLBACK;

        // Store payment token in case it changes and a refund must be triggered
        paymentTokensToRefund[issuanceIndexCached] = address(paymentToken);

        emit RollBack(
            issuer,
            issuanceIndexCached,
            issuances[issuanceIndexCached].raisedAmount
        );
    }

    /// @dev Internal method to change the payment token, its oracle and the twap window
    function _setPaymentToken(
        address _newPaymentToken,
        address _newPaymentTokenOracle,
        uint256 _twapInterval
    ) internal {
        // Check to ensure no issuance is ongoing
        if (
            (issuanceIndex != 0) &&
            !(isWithdrawn(issuanceIndex) || isRollback(issuanceIndex))
        ) revert Errors.IssuanceNotFinalized(issuer);

        // Validations
        if (
            _newPaymentToken == address(0) // Not checking whether payment token oracle is zero, because zero is a valid value
        ) revert Errors.NotZeroAddress();

        if (_twapInterval > type(uint32).max || _twapInterval == 0)
            revert Errors.BadTwapIntervalValue(_twapInterval);

        ERC20Token storage tokenStructNew = tokenERC20Whitelist[
            _newPaymentToken
        ];

        tokenERC20Whitelist[address(paymentToken)].status = false;
        tokenStructNew.status = true;

        paymentTokenOracle = IChainlinkPriceFeed(_newPaymentTokenOracle);
        paymentToken = IERC20MetadataUpgradeable(_newPaymentToken);

        twapInterval = _twapInterval;
    }

    /// @dev Internal method to report an offchain amount of USD to assign to the current offering
    /// This is because by business logic, some investments might come offchain.
    /// This shouldn't be abused and through the metadata in the STOToken URI the issue will attach a document to justify the offchain report
    /// @param offchainAmount is in paymentToken units, so if paymentToken is USDC, this amount goes with 6 decimals
    /// @param toAssign is the address of the investor that has to be assigned the offchain payment
    /// @param proofOfPayment is the proof that the investor has payed the amount in the offchain report
    function _offchainReporting(
        uint256 offchainAmount,
        address toAssign,
        string calldata proofOfPayment
    ) internal {
        address caller = _msgSender();
        uint256 issuanceIndexCached = issuanceIndex;
        if (isEnded(issuanceIndexCached))
            revert Errors.IssuanceEnded(
                caller,
                issuances[issuanceIndexCached].endDate
            );

        Issuance storage issuanceCached = issuances[issuanceIndexCached];
        Investor storage investor = investors[issuanceIndexCached][toAssign];
        if (investor.redeemed) revert Errors.TokensAlreadyReedemed(toAssign);

        uint256 usdPriceOfPaymentToken = priceAndSwapManager
            .getUSDPriceOfPaymentToken(paymentTokenOracle, twapInterval);

        uint256 maxAmount = _validateInputs(
            offchainAmount,
            usdPriceOfPaymentToken,
            10 ** paymentToken.decimals(), // paymentTokenScale
            toAssign
        );

        if (maxAmount > 0) {
            offchainAmount = maxAmount;
        }

        uint256 actualValue = offchainAmount.mulDiv(
            usdPriceOfPaymentToken,
            10 ** paymentToken.decimals(), // paymentTokenScale
            MathUpgradeable.Rounding.Down
        );

        uint256 newAmountInSTO = actualValue.mulDiv(
            10 ** stoRelatedToken.decimals(), // stoRelatedTokenScale
            issuanceCached.priceInUSD,
            MathUpgradeable.Rounding.Up
        );

        // We dont update investor.amountInPaymentToken because it didn't deposit any token at all. Instead is an offchain record.
        // For the same reason we don't update issuanceCached.paymentTokensCollected

        investor.amountInSTO = investor.amountInSTO + newAmountInSTO;

        uint256 newRaisedAmount = issuanceCached.raisedAmount + actualValue;
        issuanceCached.raisedAmount = newRaisedAmount;

        if (newRaisedAmount > issuanceCached.hardCap)
            issuanceCached.raisedAmount = issuanceCached.hardCap;

        emit OffchainReport(newAmountInSTO, toAssign, proofOfPayment);
    }

    /// @dev Method to get the amount of fee to be paid and coverage shortfall
    /// @param amountToWithdraw Amount of payment token to withdraw
    function getFeeEstimation(
        uint256 amountToWithdraw
    )
        public
        view
        returns (
            bool hasEnoughBalance,
            uint256 feeToPay,
            uint256 amountToReceive,
            uint256 feeCoverageShortfall
        )
    {
        uint256 issuanceIndexCached = issuanceIndex;
        if (!isActive(issuanceIndexCached))
            return (
                hasEnoughBalance,
                feeToPay,
                amountToReceive,
                feeCoverageShortfall
            );

        uint256 partialWithdrawn = issuances[issuanceIndexCached]
            .partialWithdraw;
        uint256 paymentTokensCollected = issuances[issuanceIndexCached]
            .paymentTokensCollected;

        uint256 raisedAmountInPaymentToken = issuances[issuanceIndexCached]
            .raisedAmount
            .mulDiv(
                10 ** paymentToken.decimals(),
                getUSDPriceOfPaymentToken(),
                MathUpgradeable.Rounding.Down
            );

        uint256 feeTotal = raisedAmountInPaymentToken.mulDiv(
            withdrawalFee,
            MAX_FEE_LIMIT,
            MathUpgradeable.Rounding.Up
        );

        uint256 remainingfee = feeTotal -
            getFeeAccumulated(issuanceIndexCached);

        uint256 feeTotalPercentageToWithdraw = uint256(withdrawalFee).mulDiv(
            remainingfee,
            feeTotal,
            MathUpgradeable.Rounding.Up
        );

        uint256 available = paymentTokensCollected - partialWithdrawn;
        feeToPay = remainingfee;

        if (available > amountToWithdraw) {
            uint256 amountToWithdrawPercentage = raisedAmountInPaymentToken
                .mulDiv(
                    amountToWithdraw,
                    available,
                    MathUpgradeable.Rounding.Up
                );
            feeToPay = amountToWithdrawPercentage.mulDiv(
                feeTotalPercentageToWithdraw,
                MAX_FEE_LIMIT,
                MathUpgradeable.Rounding.Up
            );
        }

        // On V2 payment token balance should be checked based on payment tokens collected (necessary for offchain reporting)
        uint256 paymentTokenBalance = paymentToken.balanceOf(address(this));
        hasEnoughBalance = paymentTokenBalance >= feeToPay;
        if (hasEnoughBalance) {
            if (amountToWithdraw >= paymentTokenBalance) {
                amountToReceive = paymentTokenBalance - feeToPay;
            } else {
                if (amountToWithdraw >= feeToPay) {
                    amountToReceive = amountToWithdraw - feeToPay;
                }
            }
        } else {
            feeCoverageShortfall = feeToPay - paymentTokenBalance;
        }

        return (
            hasEnoughBalance,
            feeToPay,
            amountToReceive,
            feeCoverageShortfall
        );
    }

    /// @dev Internal method to patch an existing offering.
    /// @param newStart New start date
    /// @param newEnd New end date
    /// @param newSoftCap New soft cap
    /// @param newHardCap New hard cap
    /// @param newMinTicket New min ticket
    /// @param newMaxTicket New max ticket
    function _patchOffering(
        uint256 newStart,
        uint256 newEnd,
        uint256 newSoftCap,
        uint256 newHardCap,
        uint256 newMinTicket,
        uint256 newMaxTicket
    ) internal {
        address caller = _msgSender();
        uint256 issuanceIndexCached = issuanceIndex;

        if (issuanceIndexCached == 0) revert Errors.IssuanceNotStarted(caller);
        if (isWithdrawn(issuanceIndexCached))
            revert Errors.IssuanceWasWithdrawn(caller);
        if (isRollback(issuanceIndexCached))
            revert Errors.IssuanceWasRollbacked(caller);

        Issuance storage issuanceCached = issuances[issuanceIndexCached];

        if (newStart != issuanceCached.startDate) {
            if (newStart < block.timestamp)
                revert Errors.PatchValueWrong(
                    issuanceCached.startDate,
                    newStart
                );
            issuanceCached.startDate = newStart;
        }

        if (newEnd != issuanceCached.endDate) {
            if (newEnd < block.timestamp || newEnd < newStart)
                revert Errors.PatchValueWrong(issuanceCached.endDate, newEnd);
            issuanceCached.endDate = newEnd;
        }

        if (newSoftCap != issuanceCached.softCap) {
            issuanceCached.softCap = newSoftCap;
        }

        if (newHardCap != issuanceCached.hardCap) {
            if (newHardCap < newSoftCap)
                revert Errors.PatchValueWrong(
                    issuanceCached.hardCap,
                    newHardCap
                );
            issuanceCached.hardCap = newHardCap;
        }

        if (newMinTicket != issuanceCached.minTicket) {
            if (newMinTicket > newMaxTicket)
                revert Errors.PatchValueWrong(
                    issuanceCached.minTicket,
                    newMinTicket
                );
            issuanceCached.minTicket = newMinTicket;
        }

        if (newMaxTicket != issuanceCached.maxTicket) {
            if (newMaxTicket < newMinTicket)
                revert Errors.PatchValueWrong(
                    issuanceCached.maxTicket,
                    newMaxTicket
                );
            issuanceCached.maxTicket = newMaxTicket;
        }
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[34] private __gap;
}
