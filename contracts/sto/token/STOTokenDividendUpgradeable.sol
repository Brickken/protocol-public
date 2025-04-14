// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { Errors } from "../helpers/Errors.sol";
import { ISTOToken } from "../interfaces/ISTOToken.sol";
import { STOTokenCheckpointsUpgradeable } from "./STOTokenCheckpointsUpgradeable.sol";
import { MathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

/// @title STOTokenDividendUpgradeable dividend distributionb module
/// @custom:security-contact tech@brickken.com
abstract contract STOTokenDividendUpgradeable is
    STOTokenCheckpointsUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;
    using MathUpgradeable for uint256;

    /// @dev Struct to store the a dividend distribution
    struct DividendDistribution {
        /// @dev Total amount of dividends distributed
        uint256 totalAmount;
        /// @dev Block number
        uint256 blockNumber;
        /// @dev payment token used for distribution
        address paymentTokenUsed;
    }

    /// @dev Number of dividend distributions
    uint256 public numberOfDistributions;

    /// @dev Address of STOToken related to these dividends
    ISTOToken private stoRelatedToken_OLD_SLOT; // Keep for back compatibility. Ignore.

    /// @dev Address of ERC20 token used to payout dividends
    IERC20MetadataUpgradeable public paymentToken;

    /// @dev last block at which the user claimed dividends
    mapping(address user => uint256 blockNumber) public lastClaimedBlock;

    /// @dev Mapping of distributions
    mapping(uint256 index => DividendDistribution info) public dividendDistributions;

    /// Events
    event NewDividendDistribution(address indexed token, uint256 totalAmount);

    event DividendClaimed(
        address indexed claimer,
        address indexed token,
        uint256 amountClaimed
    );

    event NewPaymentToken(
        address indexed OldPaymentToken,
        address indexed NewPaymentToken
    );

    /// @dev Method to check getting max amount of dividends to claim
    /// @param _claimer address of claimer of the STOToken
    /// @param upTo index of the distribution up to which the claimer wants to claim tokens. 0 if it has to be ignored
    /// @return paymentTokens list of different payment tokens used during distributions
    /// @return amounts amount of each payment token to distribute
    /// @return latestBlock latest block to mark user claims
    function getMaxAmountToClaim(
        address _claimer,
        uint256 upTo
    )
        public
        view
        returns (
            address[] memory paymentTokens,
            uint256[] memory amounts,
            uint256 latestBlock
        )
    {
        uint256 index = getIndexToClaim(_claimer);
        if (index == numberOfDistributions) {
                paymentTokens = new address[](0);
                amounts = new uint256[](0);

                return(
                    paymentTokens,
                    amounts,
                    block.number + 1
                );
        }

        if(upTo != 0) {
            require(upTo <= numberOfDistributions, "Up to index out of bounds");
        } else {
            upTo = numberOfDistributions;
        }

        paymentTokens = new address[](upTo-index);
        amounts = new uint256[](upTo-index);
        uint256 counter = 0;

        uint256 blockNumber;

        for (uint256 i = index; i < upTo; i++) {
            blockNumber = dividendDistributions[i].blockNumber;
            uint256 pastBalance = getPastBalance(
                _claimer,
                blockNumber
            );
            uint256 pastTotalSupply = getPastTotalSupply(blockNumber);
            uint256 percentage = pastBalance.mulDiv(1 ether, pastTotalSupply);
            
            // Doing this array might be inefficient if payment token is switched back and forth through same tokens several times
            // But we consider this being an unlikely edge case and this logic is way easier than mapping all different tokens into a potentially shorter list
            // We consider that the payment token shouldn't change too often

            amounts[
                counter
            ] = percentage.mulDiv(
                dividendDistributions[i].totalAmount,
                1 ether
            );

            paymentTokens[
                counter
            ] = dividendDistributions[i].paymentTokenUsed;

            counter++;
        }

        return(
            paymentTokens,
            amounts,
            blockNumber + 1
        );
    }

    /// @dev Method to check the index of where start to claim dividend for the claimer
    /// @param _claimer address of the claimer of STOToken
    /// @return index after the entry point of claimer
    function getIndexToClaim(address _claimer) public view returns (uint256 index) {
        uint256 lastBlock = lastClaimedBlock[_claimer];
        for (uint256 i = numberOfDistributions - 1; i >= 0; i--) {
            if (dividendDistributions[i].blockNumber < lastBlock) {
                index = i +1;
                return index;
            }
            if (i == 0) {
                index = i;
                return index;
            }
        }
    }

    // INTERNAL / PRIVATE FUNCTIONS

    /// @dev Init Dividend Feature
    function __STOTokenDividend_init(
        address newPaymentToken,
        string calldata _name,
        string calldata _symbol
    ) internal {
        paymentToken = IERC20MetadataUpgradeable(newPaymentToken);
        
        __STOTokenCheckpoints_init(_name, _symbol);
        __ReentrancyGuard_init();

    }

    /// @dev Method to add a new dividends distribution among STOToken holders
    /// @param _totalAmount Total Amount of Dividend
    function _addDistDividend(uint256 _totalAmount) internal {
        address caller = _msgSender();

        if (_totalAmount == 0) revert Errors.DividendAmountIsZero();

        /// Safe Transfer
        if (paymentToken.balanceOf(caller) < _totalAmount)
            revert Errors.InsufficientBalance(
                caller,
                address(paymentToken),
                _totalAmount
            );

        dividendDistributions[numberOfDistributions].totalAmount = _totalAmount;
        dividendDistributions[numberOfDistributions].blockNumber = block.number - 1; // avoid front-running within the same block. This doesn't prevent doing the same one block before.
        dividendDistributions[numberOfDistributions].paymentTokenUsed = address(paymentToken);

        numberOfDistributions++;

        SafeERC20Upgradeable.safeTransferFrom(
            paymentToken,
            caller,
            address(this),
            _totalAmount
        );
    }

    /// @dev Method to claim dividends of the token
    function _claimDividends(uint256 upTo, address onBehalfOf) internal nonReentrant {
        
        if (
            !trackings(onBehalfOf) ||
            balanceOf(onBehalfOf) == 0
        ) revert Errors.NotAvailableToClaim(onBehalfOf);

        (address[] memory paymentTokens, uint256[] memory amounts, uint256 latestBlock) = getMaxAmountToClaim(onBehalfOf, upTo);

        lastClaimedBlock[onBehalfOf] = latestBlock;

        for(uint256 i = 0; i < paymentTokens.length;) {
            uint256 amount = amounts[i];
            IERC20MetadataUpgradeable paymentTokenToUse = IERC20MetadataUpgradeable(paymentTokens[i]);

            if (amount > paymentTokenToUse.balanceOf(address(this)))
                revert Errors.ExceedAmountAvailable(
                    onBehalfOf,
                    paymentTokenToUse.balanceOf(address(this)),
                    amount
                );

            SafeERC20Upgradeable.safeTransfer(
                paymentTokenToUse,
                onBehalfOf,
                amount
            );

            emit DividendClaimed(onBehalfOf, address(paymentTokenToUse), amount);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Method to change the payment token
    /// @dev This method is only available to account with the DEFAULT_ADMIN_ROLE role
    /// @param _newPaymentToken is the new payment token address
    function _changePaymentToken(address _newPaymentToken) internal {
		if (!_newPaymentToken.isContract()) revert Errors.InvalidPaymentToken(_newPaymentToken);
        paymentToken = IERC20MetadataUpgradeable(_newPaymentToken);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[47] private __gap;
}
