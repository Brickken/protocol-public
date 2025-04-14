/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {Roles} from "../helpers/Roles.sol";
import {DTOEscrowErrors, DTOCommonErrors} from "../helpers/Errors.sol";
import {DTOEscrowUpgradeable} from "./DTOEscrowUpgradeable.sol";
import {AccessControlEnumerableUpgradeable, AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

/// @title DTOEscrowManagedUpgradeable wrapper around DTOEscrowUpgradeable contract to add access control and roles
/// @custom:security-contact tech@brickken.com
contract DTOEscrowManagedUpgradeable is
    DTOEscrowUpgradeable,
    AccessControlEnumerableUpgradeable
{
    using MathUpgradeable for uint256;

    /// @dev Method to initialize the contract. If further initializations are needed, the reinitializer modifier should be changed with the newer version
    /// @dev future initializations will not re-set the roles and will skip the roles assignments. If contract is already initialized once, only the DEFAULT_ADMIN_ROLE can call this function.
    function initialize(
        address _dtoToken,
        address _newBorrower,
        address _admin,
        address _paymentToken,
        address _router,
        address _paymentTokenOracle,
        bool _paymentTokenOracleUnused,
        address _treasuryAddress,
        address _priceAndSwapManager,
        uint8 _version
    ) external reinitializer(_version) {
        if (
            getRoleMemberCount(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) == 0
        ) {
            _grantRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, _admin);
            _grantRole(Roles.ESCROW_WITHDRAW_ROLE, _newBorrower);
            _grantRole(Roles.ESCROW_NEW_OFFERING_ROLE, _newBorrower);

            _grantRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE, _admin); // Just in case borrower doesn't finalize an offering leaving lenders to hang
            _grantRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE, _newBorrower);

            _grantRole(Roles.ESCROW_ERC20WHITELIST_ROLE, _admin); // Just in case borrower is not tech savy
            _grantRole(Roles.ESCROW_ERC20WHITELIST_ROLE, _newBorrower);
            _grantRole(Roles.ESCROW_OFFCHAIN_REPORTER_ROLE, _newBorrower);
        } else if (
            !hasRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, _msgSender())
        ) revert DTOCommonErrors.UserIsNotAdmin(_msgSender());

        __DTOEscrowUpgradeable_init(
            _dtoToken,
            _newBorrower,
            _paymentToken,
            _router,
            _paymentTokenOracle,
            _paymentTokenOracleUnused,
            _treasuryAddress,
            _priceAndSwapManager
        );

        // For backward compatibility, go through all issuances again
        for (uint256 i = 1; i <= issuanceIndex; i++) {
            if (issuances[i].raisedAmount > 0)
                issuances[i].paymentTokensCollected = issuances[i]
                    .raisedAmount
                    .mulDiv(
                        10 ** paymentToken.decimals(),
                        1e18,
                        MathUpgradeable.Rounding.Down
                    );

            if (issuances[i].status == IssuanceStatuses.WITHDRAWN)
                issuances[i].partialWithdraw = issuances[i].raisedAmount;
            if (issuances[i].status == IssuanceStatuses.ROLLBACK)
                paymentTokensToRefund[i] = address(paymentToken);
        }
    }

    /// @dev Method to change the current borrower. Used if borrower wallet got's hacked or private keys leaked. Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newBorrower address of the new borrower. Roles will be revoked from old address and granted to the new one.
    function changeBorrower(
        address newBorrower
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _revokeRole(Roles.ESCROW_WITHDRAW_ROLE, borrower);
        _revokeRole(Roles.ESCROW_NEW_OFFERING_ROLE, borrower);
        _revokeRole(Roles.ESCROW_ERC20WHITELIST_ROLE, borrower);
        _revokeRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE, borrower);
        _revokeRole(Roles.ESCROW_OFFCHAIN_REPORTER_ROLE, borrower);

        _changeBorrower(newBorrower);

        _grantRole(Roles.ESCROW_WITHDRAW_ROLE, newBorrower);
        _grantRole(Roles.ESCROW_NEW_OFFERING_ROLE, newBorrower);
        _grantRole(Roles.ESCROW_ERC20WHITELIST_ROLE, newBorrower);
        _grantRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE, newBorrower);
        _grantRole(Roles.ESCROW_OFFCHAIN_REPORTER_ROLE, newBorrower);

        emit ChangeBorrower(newBorrower);
    }

    /// @dev Method to change the current paymentToken. Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newPaymentToken address of the new paymentToken.
    /// @param newPaymentTokenOracle address of the oracle reporting the price of the newPaymentToken in USD
    /// @param newTwapInterval the time window, in seconds, to use as TWAP interval for price sanity check
    function setPaymentToken(
        address newPaymentToken,
        address newPaymentTokenOracle,
        uint256 newTwapInterval
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _setPaymentToken(
            newPaymentToken,
            newPaymentTokenOracle,
            newTwapInterval
        );
        emit ChangePaymentToken(newPaymentToken, newPaymentTokenOracle);
    }

    /// @dev Method to change the current Uniswap v3 router. Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newRouter address of the new Uniswap router.
    function setRouter(
        address newRouter
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _setRouter(newRouter);
        emit ChangeRouterAddress(newRouter);
    }

    /// @dev Method to change the current PriceAndSwapManager. Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newPriceAndSwapManager address of the new PriceAndSwapManager.
    function setPriceAndSwapManager(
        address newPriceAndSwapManager
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _setPriceAndSwapManager(newPriceAndSwapManager);
        emit ChangePriceAndSwapManager(newPriceAndSwapManager);
    }

    /// @dev Method to change the list of whitelisted ERC20 tokens. Only the ESCROW_ERC20WHITELIST_ROLE can call this function.
    /// @param tokensToChange Array of ERC20 tokens to be changed in the whitelist
    /// @param statuses Array of statuses for each ERC20 token
    /// @param fees Array of Uniswap fees to select the right pool
    function changeWhitelist(
        address[] calldata tokensToChange,
        bool[] calldata statuses,
        uint24[] calldata fees
    ) external onlyRole(Roles.ESCROW_ERC20WHITELIST_ROLE) {
        _changeWhitelist(tokensToChange, statuses, fees);
        emit ERC20Whitelisted(borrower, tokensToChange, statuses);
    }

    /// @dev Method to change the withdrawal fee (success fee). Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newFee Fee to be charged for withdrawal
    function changeWithdrawalFee(
        uint24 newFee
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _changeWithdrawalFee(newFee);
        emit ChangeWithdrawalFee(withdrawalFee, newFee);
    }

    /// @dev Method to change the treasury address
    /// @param newTreasuryAddress Address of the new treasury
    function changeTreasuryAddress(
        address newTreasuryAddress
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _changeTreasuryAddress(newTreasuryAddress);
        emit ChangeTreasuryAddress(treasuryAddress, newTreasuryAddress);
    }

    /// @dev Method to start a new offering. Only the borrower with ESCROW_NEW_OFFERING_ROLE can call this function.
    /// @param newIssuance Struct with all the data of the new issuance. Refers to DTOEscrowUpgradeable.Issuance struct definition.
    function newOffering(
        Issuance calldata newIssuance
    ) external onlyRole(Roles.ESCROW_NEW_OFFERING_ROLE) {
        _newOffering(newIssuance);
        emit NewOffering(issuanceIndex, issuances[issuanceIndex]);
    }

    /// @dev Method to finalize an issuance. Only the ESCROW_OFFERING_FINALIZER_ROLE can call this function.
    /// @param withdrawTo address to which the borrower wants to send the withdrawn amount of paymentToken.
    /// It will internally emit either the Withdraw or Rollback events to signal issuance finalization.
    function finalizeIssuance(
        address withdrawTo
    ) external onlyRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE) {
        if (withdrawTo == address(0)) revert DTOCommonErrors.NotZeroAddress();
        _finalizeIssuance(withdrawTo);
    }

    /// @dev Method to partially withdraw payment token if issuance is succesfull. Only the ESCROW_WITHDRAW_ROLE can call this function.
    /// @param amount Amount of payment token to withdraw
    /// @param withdrawTo address to which the borrower wants to send the withdrawn amount of paymentToken
    /// It will internally emit the Withdraw event.
    function partialWithdraw(
        uint256 amount,
        address withdrawTo
    ) external onlyRole(Roles.ESCROW_WITHDRAW_ROLE) {
        address caller = _msgSender();
        uint256 issuanceIndexCached = issuanceIndex;

        if (issuanceIndexCached == 0)
            revert DTOEscrowErrors.IssuanceNotStarted(caller);

        if (!isStarted(issuanceIndexCached))
            revert DTOEscrowErrors.IssuanceNotStarted(caller);

        if (isEnded(issuanceIndexCached))
            revert DTOEscrowErrors.IssuanceEnded(
                caller,
                issuances[issuanceIndexCached].endDate
            );

        if (!isSuccess(issuanceIndexCached))
            revert DTOEscrowErrors.IssuanceNotSuccess(caller);

        if (isWithdrawn(issuanceIndexCached))
            revert DTOEscrowErrors.IssuanceWasWithdrawn(issuanceIndexCached);

        if (withdrawTo == address(0)) revert DTOCommonErrors.NotZeroAddress();

        _partialWithdraw(amount, withdrawTo);
    }

    /// @dev Method to report an offchain amount of USD to assign to the current offering. Only the ESCROW_OFFCHAIN_REPORTER_ROLE can call this function.
    /// This is because by business logic, some investments might come offchain.
    /// This shouldn't be abused and through the metadata in the DTOToken URI the issue will attach a document to justify the offchain report
    /// @param amounts is in paymentToken units, so if paymentToken is USDC, this amount goes with 6 decimals
    /// @param addresses the user that should receive the corresponding tokens from this offchain ticket. Should be wwhitelisted.
    /// @param proofOfPayment is the proof that the lender has payed the amount in the offchain report
    function offchainReporting(
        uint256[] calldata amounts,
        address[] calldata addresses,
        string[] calldata proofOfPayment
    ) external onlyRole(Roles.ESCROW_OFFCHAIN_REPORTER_ROLE) {
        if (amounts.length == 0 || amounts.length != addresses.length)
            revert DTOCommonErrors.LengthsMismatch();

        uint256 totalAmount = 0;
        uint256 issuanceIndexCached = issuanceIndex;
        uint256 availableAmountCached = (issuances[issuanceIndexCached]
            .hardCap - issuances[issuanceIndexCached].raisedAmount).mulDiv(
                10 ** paymentToken.decimals(),
                1e18,
                MathUpgradeable.Rounding.Down
            );
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
            if (totalAmount > availableAmountCached)
                revert DTOEscrowErrors.OffchainAmountExceedsAvailableAmount(
                    availableAmountCached,
                    totalAmount
                );
            if (
                !dtoRelatedToken.hasRole(
                    Roles.TOKEN_WHITELIST_ROLE,
                    addresses[i]
                )
            ) revert DTOCommonErrors.UserIsNotWhitelisted(addresses[i]);
            _offchainReporting(amounts[i], addresses[i], proofOfPayment[i]);
        }
    }

    /// @dev Method to patch an existing offering. Only the DEFAULT_ADMIN_ROLE can call this function.
    /// @param newStart New start date
    /// @param newEnd New end date
    /// @param newSoftCap New soft cap
    /// @param newHardCap New hard cap
    /// @param newMinTicket New min ticket
    /// @param newMaxTicket New max ticket
    function patchOffering(
        uint256 newStart,
        uint256 newEnd,
        uint256 newSoftCap,
        uint256 newHardCap,
        uint256 newMinTicket,
        uint256 newMaxTicket
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _patchOffering(
            newStart,
            newEnd,
            newSoftCap,
            newHardCap,
            newMinTicket,
            newMaxTicket
        );

        emit OfferingPatched(issuanceIndex, issuances[issuanceIndex]);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
