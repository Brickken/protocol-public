// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {DTOTokenErrors, DTOCommonErrors} from "../helpers/Errors.sol";
import {IDTOToken} from "../interfaces/IDTOToken.sol";
import {DTOTokenCheckpointsUpgradeable} from "./DTOTokenCheckpointsUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IDTOEscrow} from "../interfaces/IDTOEscrow.sol";

/// @title DTODebtRepayUpgradeable debt repayment module
/// @custom:security-contact tech@brickken.com
abstract contract DTODebtRepayUpgradeable is
    DTOTokenCheckpointsUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;
    using MathUpgradeable for uint256;

    /// @dev Number of debt repayment distributions
    uint256 public numberOfDebtRepayments;

    /// @dev Debt's interest rate. (from 1 to 10000, equivalent to 0.01% to 100%)
    uint24 public debtInterestRate;

    /// @dev Total of debt repaid in USD
    uint256 public totalDebtRepaid;

    /// @dev Total interest of debt repaid in USD
    uint256 public totalInterestRepaid;

    /// @dev Total capital repaid in USD
    uint256 public totalCapitalRepaid;

    /// @dev Flag to toggle debt repayment
    bool public debtRepaymentToggled;

    /// @dev Address of the DTO token related to this escrow service
    IDTOEscrow public dtoRelatedEscrow;

    /// @dev Max debt interest rate limit in order to guarantee that interest doesn't exceed 100%
    uint24 public constant MAX_INTEREST_RATE_LIMIT = 1e4;

    /// @dev Address of ERC20 token used to repay debt
    IERC20MetadataUpgradeable public paymentToken;

    /// @dev last block at which the user got debt repaid
    mapping(address user => uint256 blockNumber) public lastClaimedBlock;

    /// @dev Struct to store the a debt repayment
    struct DebtRepaymentDistribution {
        /// @dev Total amount of debt repaid in USD
        uint256 totalAmount;
        /// @dev Block number
        uint256 blockNumber;
        /// @dev payment token used for distribution
        address paymentTokenUsed;
        /// @dev amount of Debt Repaid in USD
        uint256 debtRepaid;
        /// @dev amount of Capital Repaid in USD
        uint256 capitalRepaid;
        /// @dev amount of Interest Repaid in USD
        uint256 interestRepaid;
    }

    /// @dev Mapping of distributions
    mapping(uint256 index => DebtRepaymentDistribution info)
        public debtRepaymentDistributions;

    /// Events
    event NewDebtRepayment(
        address indexed token,
        uint256 debtCapitalAmount,
        uint256 debtInterestAmount
    );

    event DebtRepaid(
        address indexed claimer,
        address indexed token,
        uint256 amountClaimed
    );

    event NewPaymentToken(
        address indexed OldPaymentToken,
        address indexed NewPaymentToken
    );

    event ChangeDebtInterestRate(
        uint256 indexed oldDebtInterestRate,
        uint256 indexed newDebtInterestRate
    );

    event DebtRepaymentToggled(bool indexed debtRepaymentToggled);

    // Only the factory contract can call functions with this modifer
    modifier onlyWhenDebtRepayToggled() {
        if (!isDebtRepaymentToggled())
            revert DTOTokenErrors.DebtRepaymentNotToggled();
        _;
    }

    /// @dev Method to check getting max amount of debt repaid
    /// @param _claimer address of claimer of the DTOToken
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
        if (index == numberOfDebtRepayments) {
            paymentTokens = new address[](0);
            amounts = new uint256[](0);

            return (paymentTokens, amounts, block.number + 1);
        }

        if (upTo != 0) {
            require(
                upTo <= numberOfDebtRepayments,
                "Up to index out of bounds"
            );
        } else {
            upTo = numberOfDebtRepayments;
        }

        paymentTokens = new address[](upTo - index);
        amounts = new uint256[](upTo - index);
        uint256 counter = 0;

        uint256 blockNumber;

        for (uint256 i = index; i < upTo; i++) {
            blockNumber = debtRepaymentDistributions[i].blockNumber;
            uint256 pastBalance = getPastBalance(_claimer, blockNumber);
            uint256 pastTotalSupply = getPastTotalSupply(blockNumber);
            uint256 percentage = pastBalance.mulDiv(1 ether, pastTotalSupply);

            // Doing this array might be inefficient if payment token is switched back and forth through same tokens several times
            // But we consider this being an unlikely edge case and this logic is way easier than mapping all different tokens into a potentially shorter list
            // We consider that the payment token shouldn't change too often

            amounts[counter] = percentage.mulDiv(
                debtRepaymentDistributions[i].totalAmount,
                1 ether
            );

            paymentTokens[counter] = debtRepaymentDistributions[i]
                .paymentTokenUsed;

            counter++;
        }

        return (paymentTokens, amounts, blockNumber + 1);
    }

    /// @dev Method to check the index of where start to claim debt repayment for the claimer
    /// @param _claimer address of the claimer of DTOToken
    /// @return index after the entry point of claimer
    function getIndexToClaim(
        address _claimer
    ) public view returns (uint256 index) {
        uint256 lastBlock = lastClaimedBlock[_claimer];
        if (numberOfDebtRepayments > 0) {
            for (uint256 i = numberOfDebtRepayments - 1; i >= 0; i--) {
                if (debtRepaymentDistributions[i].blockNumber < lastBlock) {
                    index = i + 1;
                    return index;
                }
                if (i == 0) {
                    index = i;
                    return index;
                }
            }
        }
    }

    /// @dev Method to check if debt repayment is toggled
    function isDebtRepaymentToggled() public view returns (bool) {
        return debtRepaymentToggled;
    }

    /// @dev Method to check if debt is paid
    /// @return true if debt is paid and remaining debt to pay
    function isDebtRepaid() public view returns (bool) {
        uint256 totalCapitalDebt = totalSupply();
        uint256 issuanceIndexCached = dtoRelatedEscrow.issuanceIndex();
        IDTOEscrow.Issuance memory currentIssuance = dtoRelatedEscrow.issuances(
            issuanceIndexCached
        );
        if (
            address(dtoRelatedEscrow) != address(0) && issuanceIndexCached > 0
        ) {
            totalCapitalDebt = totalCapitalDebt.mulDiv(
                currentIssuance.priceInUSD,
                1 ether,
                MathUpgradeable.Rounding.Down
            );
        }

        uint256 totalInterestDebt = totalCapitalDebt.mulDiv(
            debtInterestRate,
            MAX_INTEREST_RATE_LIMIT,
            MathUpgradeable.Rounding.Up
        );

        uint256 remainingCapitalDebt = totalCapitalDebt.sub(totalCapitalRepaid);
        uint256 remainingInterestDebt = totalInterestDebt.sub(
            totalInterestRepaid
        );
        return (remainingCapitalDebt == 0 && remainingInterestDebt == 0);
    }

    function getRemainingDebt()
        public
        view
        returns (uint256 remainingCapitalDebt, uint256 remainingInterestDebt)
    {
        uint256 issuanceIndexCached = dtoRelatedEscrow.issuanceIndex();

        uint256 totalCapitalDebt = totalSupply();
        IDTOEscrow.Issuance memory currentIssuance = dtoRelatedEscrow.issuances(
            issuanceIndexCached
        );
        if (
            address(dtoRelatedEscrow) != address(0) && issuanceIndexCached > 0
        ) {
            totalCapitalDebt = totalCapitalDebt.mulDiv(
                currentIssuance.priceInUSD,
                1 ether,
                MathUpgradeable.Rounding.Down
            );
        }
        uint256 totalInterestDebt = totalCapitalDebt.mulDiv(
            debtInterestRate,
            MAX_INTEREST_RATE_LIMIT,
            MathUpgradeable.Rounding.Up
        );

        remainingCapitalDebt = totalCapitalDebt.sub(totalCapitalRepaid);
        remainingInterestDebt = totalInterestDebt.sub(totalInterestRepaid);
        return (remainingCapitalDebt, remainingInterestDebt);
    }

    // INTERNAL / PRIVATE FUNCTIONS

    /// @dev Init Debt Repayment Feature
    function __DTOTokenDebtRepayment_init(
        address newPaymentToken,
        string calldata _name,
        string calldata _symbol,
        uint24 newDebtInterestRate
    ) internal {
        paymentToken = IERC20MetadataUpgradeable(newPaymentToken);
        debtInterestRate = newDebtInterestRate;

        __DTOTokenCheckpoints_init(_name, _symbol);
        __ReentrancyGuard_init();
    }

    /// @dev Method to add a new debt repayment to DTOToken holders
    /// @param _debtCapitalAmount debt capital amount to be repaid in payment token
    /// @param _debtInterestAmount debt interest amount to be repaid in payment token
    function _addDebtRepayment(
        uint256 _debtCapitalAmount,
        uint256 _debtInterestAmount
    ) internal onlyWhenDebtRepayToggled {
        address caller = _msgSender();

        if (_debtCapitalAmount == 0 && _debtInterestAmount == 0)
            revert DTOTokenErrors.DebtRepaymentAmountIsZero();

        /// check remaining debt to be paid

        if (isDebtRepaid()) revert DTOTokenErrors.DebtRepaid();
        (
            uint256 remainingCapitalDebt,
            uint256 remainingInterestDebt
        ) = getRemainingDebt();

        uint256 debtCapitalAmountUSD = _debtCapitalAmount.mulDiv(
            dtoRelatedEscrow.getUSDPriceOfPaymentToken(),
            1 ether,
            MathUpgradeable.Rounding.Down
        );
        uint256 debtInterestAmountUSD = _debtInterestAmount.mulDiv(
            dtoRelatedEscrow.getUSDPriceOfPaymentToken(),
            1 ether,
            MathUpgradeable.Rounding.Down
        );

        if (remainingCapitalDebt < debtCapitalAmountUSD) {
            _debtCapitalAmount = remainingCapitalDebt;
        }
        if (remainingInterestDebt < debtInterestAmountUSD) {
            _debtInterestAmount = remainingInterestDebt;
        }

        uint256 _totalAmount = _debtCapitalAmount.add(_debtInterestAmount);
        uint256 _totalAmountUSD = _totalAmount.mulDiv(
            dtoRelatedEscrow.getUSDPriceOfPaymentToken(),
            1 ether,
            MathUpgradeable.Rounding.Down
        );

        /// Safe Transfer
        if (paymentToken.balanceOf(caller) < _totalAmount)
            revert DTOTokenErrors.InsufficientBalance(
                caller,
                address(paymentToken),
                _totalAmount
            );

        debtRepaymentDistributions[numberOfDebtRepayments]
            .totalAmount = _totalAmountUSD;
        totalDebtRepaid = totalDebtRepaid.add(_totalAmountUSD);

        debtRepaymentDistributions[numberOfDebtRepayments]
            .capitalRepaid = debtCapitalAmountUSD;
        totalCapitalRepaid = totalCapitalRepaid.add(debtCapitalAmountUSD);

        debtRepaymentDistributions[numberOfDebtRepayments]
            .interestRepaid = debtInterestAmountUSD;
        totalInterestRepaid = totalInterestRepaid.add(debtInterestAmountUSD);

        debtRepaymentDistributions[numberOfDebtRepayments].blockNumber =
            block.number -
            1; // avoid front-running within the same block. This doesn't prevent doing the same one block before.
        debtRepaymentDistributions[numberOfDebtRepayments]
            .paymentTokenUsed = address(paymentToken);

        numberOfDebtRepayments++;

        SafeERC20Upgradeable.safeTransferFrom(
            paymentToken,
            caller,
            address(this),
            _totalAmount
        );
        // when debt has been repaid deactivate debt repayment until a new offering is created
        if (isDebtRepaid()) _toggleDebtRepayment(false);
    }

    /// @dev Method to claim debt repayment of the token
    function _claimDebtRepay(
        uint256 upTo,
        address onBehalfOf
    ) internal nonReentrant onlyWhenDebtRepayToggled {
        if (!trackings(onBehalfOf) || balanceOf(onBehalfOf) == 0)
            revert DTOTokenErrors.NotAvailableToClaim(onBehalfOf);

        (
            address[] memory paymentTokens,
            uint256[] memory amounts,
            uint256 latestBlock
        ) = getMaxAmountToClaim(onBehalfOf, upTo);

        lastClaimedBlock[onBehalfOf] = latestBlock;

        for (uint256 i = 0; i < paymentTokens.length; ) {
            uint256 amountInPaymentTokens = amounts[i].mulDiv(
                1 ether,
                dtoRelatedEscrow.getUSDPriceOfPaymentToken(),
                MathUpgradeable.Rounding.Up
            );
            IERC20MetadataUpgradeable paymentTokenToUse = IERC20MetadataUpgradeable(
                    paymentTokens[i]
                );

            if (
                amountInPaymentTokens >
                paymentTokenToUse.balanceOf(address(this))
            )
                revert DTOTokenErrors.ExceedAmountAvailable(
                    onBehalfOf,
                    paymentTokenToUse.balanceOf(address(this)),
                    amountInPaymentTokens
                );

            SafeERC20Upgradeable.safeTransfer(
                paymentTokenToUse,
                onBehalfOf,
                amountInPaymentTokens
            );

            if (isDebtRepaid()) {
                uint256 _balance = this.balanceOf(onBehalfOf);
                _burn(onBehalfOf, _balance);
            }

            emit DebtRepaid(
                onBehalfOf,
                address(paymentTokenToUse),
                amountInPaymentTokens
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Method to change the payment token
    /// @dev This method is only available to account with the DEFAULT_ADMIN_ROLE role
    /// @param _newPaymentToken is the new payment token address
    function _changePaymentToken(address _newPaymentToken) internal {
        if (!_newPaymentToken.isContract())
            revert DTOTokenErrors.InvalidPaymentToken(_newPaymentToken);
        paymentToken = IERC20MetadataUpgradeable(_newPaymentToken);
    }

    /// @dev Method to change interest rate
    /// @dev This method is only available to the owner of the contract
    /// @param newInterestRate is the new interest rate
    function _changeInterestRate(uint24 newInterestRate) internal {
        if (newInterestRate > MAX_INTEREST_RATE_LIMIT)
            revert DTOCommonErrors.InterestRateOverLimits(newInterestRate);
        uint24 oldInterestRate = debtInterestRate;
        debtInterestRate = newInterestRate;
        emit ChangeDebtInterestRate(oldInterestRate, newInterestRate);
    }

    function _toggleDebtRepayment(bool status) internal {
        require(
            status != debtRepaymentToggled,
            "debtRepaymentToggled already set"
        );
        debtRepaymentToggled = status;
        emit DebtRepaymentToggled(debtRepaymentToggled);
    }

    function _addDTOEscrow(address dtoEscrowAddress) internal {
        dtoRelatedEscrow = IDTOEscrow(dtoEscrowAddress);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[47] private __gap;
}
