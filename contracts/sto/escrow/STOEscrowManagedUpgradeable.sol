/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {Roles} from "../helpers/Roles.sol";
import {Errors} from "../helpers/Errors.sol";
import {STOEscrowUpgradeable} from "./STOEscrowUpgradeable.sol";
import {AccessControlEnumerableUpgradeable, AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

/// @title STOEscrowManagedUpgradeable wrapper around STOEscrowUpgradeable contract to add access control and roles
/// @custom:security-contact tech@brickken.com
contract STOEscrowManagedUpgradeable is
    STOEscrowUpgradeable,
    AccessControlEnumerableUpgradeable
{
    using MathUpgradeable for uint256;

    /// @dev Method to initialize the contract. If further initializations are needed, the reinitializer modifier should be changed with the newer version
    /// @dev future initializations will not re-set the roles and will skip the roles assignments. If contract is already initialized once, only the DEFAULT_ADMIN_ROLE can call this function.
    function initialize(
        address _stoToken,
        address _newIssuer,
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
            _grantRole(Roles.ESCROW_WITHDRAW_ROLE, _newIssuer);
            _grantRole(Roles.ESCROW_NEW_OFFERING_ROLE, _newIssuer);

            _grantRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE, _admin); // Just in case issuer doesn't finalize an offering leaving investors to hang
            _grantRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE, _newIssuer);

            _grantRole(Roles.ESCROW_ERC20WHITELIST_ROLE, _admin); // Just in case issuer is not tech savy
            _grantRole(Roles.ESCROW_ERC20WHITELIST_ROLE, _newIssuer);
            _grantRole(Roles.ESCROW_OFFCHAIN_REPORTER_ROLE, _newIssuer);
        } else if (
            !hasRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, _msgSender())
        ) revert Errors.UserIsNotAdmin(_msgSender());

        __STOEscrowUpgradeable_init(
            _stoToken,
            _newIssuer,
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

    /// @dev Method to change the current issuer. Used if issuer wallet got's hacked or private keys leaked. Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newIssuer address of the new issuer. Roles will be revoked from old address and granted to the new one.
    function changeIssuer(
        address newIssuer
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _revokeRole(Roles.ESCROW_WITHDRAW_ROLE, issuer);
        _revokeRole(Roles.ESCROW_NEW_OFFERING_ROLE, issuer);
        _revokeRole(Roles.ESCROW_ERC20WHITELIST_ROLE, issuer);
        _revokeRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE, issuer);
        _revokeRole(Roles.ESCROW_OFFCHAIN_REPORTER_ROLE, issuer);

        _changeIssuer(newIssuer);

        _grantRole(Roles.ESCROW_WITHDRAW_ROLE, newIssuer);
        _grantRole(Roles.ESCROW_NEW_OFFERING_ROLE, newIssuer);
        _grantRole(Roles.ESCROW_ERC20WHITELIST_ROLE, newIssuer);
        _grantRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE, newIssuer);
        _grantRole(Roles.ESCROW_OFFCHAIN_REPORTER_ROLE, newIssuer);

        emit ChangeIssuer(newIssuer);
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
        emit ERC20Whitelisted(issuer, tokensToChange, statuses);
    }

    /// @dev Method to change the withdrawal fee (success fee). Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newFee Fee to be charged for withdrawal
    function changeWithdrawalFee(
        uint256 newFee
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        emit ChangeWithdrawalFee(withdrawalFee, newFee);
        _changeWithdrawalFee(newFee);
    }

    /// @dev Method to change the treasury address
    /// @param newTreasuryAddress Address of the new treasury
    function changeTreasuryAddress(
        address newTreasuryAddress
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        emit ChangeTreasuryAddress(treasuryAddress, newTreasuryAddress);
        _changeTreasuryAddress(newTreasuryAddress);
    }

    /// @dev Method to start a new offering. Only the issuer with ESCROW_NEW_OFFERING_ROLE can call this function.
    /// @param newIssuance Struct with all the data of the new issuance. Refers to STOEscrowUpgradeable.Issuance struct definition.
    function newOffering(
        Issuance calldata newIssuance
    ) external onlyRole(Roles.ESCROW_NEW_OFFERING_ROLE) {
        _newOffering(newIssuance);
        emit NewOffering(issuanceIndex, issuances[issuanceIndex]);
    }

    /// @dev Method to finalize an issuance. Only the ESCROW_OFFERING_FINALIZER_ROLE can call this function.
    /// @param withdrawTo address to which the issuer wants to send the withdrawn amount of paymentToken.
    /// It will internally emit either the Withdraw or Rollback events to signal issuance finalization.
    function finalizeIssuance(
        address withdrawTo
    ) external onlyRole(Roles.ESCROW_OFFERING_FINALIZER_ROLE) {
        if (withdrawTo == address(0)) revert Errors.NotZeroAddress();
        _finalizeIssuance(withdrawTo);
    }

    /// @dev Method to partially withdraw payment token if issuance is succesfull. Only the ESCROW_WITHDRAW_ROLE can call this function.
    /// @param amount Amount of payment token to withdraw
    /// @param withdrawTo address to which the issuer wants to send the withdrawn amount of paymentToken
    /// It will internally emit the Withdraw event.
    function partialWithdraw(
        uint256 amount,
        address withdrawTo
    ) external onlyRole(Roles.ESCROW_WITHDRAW_ROLE) {
        address caller = _msgSender();
        uint256 issuanceIndexCached = issuanceIndex;

        if (issuanceIndexCached == 0) revert Errors.IssuanceNotStarted(caller);

        if (!isStarted(issuanceIndexCached))
            revert Errors.IssuanceNotStarted(caller);

        if (isEnded(issuanceIndexCached))
            revert Errors.IssuanceEnded(
                caller,
                issuances[issuanceIndexCached].endDate
            );

        if (!isSuccess(issuanceIndexCached))
            revert Errors.IssuanceNotSuccess(caller);

        if (isWithdrawn(issuanceIndexCached))
            revert Errors.IssuanceWasWithdrawn(issuer);

        if (withdrawTo == address(0)) revert Errors.NotZeroAddress();

        _partialWithdraw(amount, withdrawTo);
    }

    /// @dev Method to report an offchain amount of USD to assign to the current offering. Only the ESCROW_OFFCHAIN_REPORTER_ROLE can call this function.
    /// This is because by business logic, some investments might come offchain.
    /// This shouldn't be abused and through the metadata in the STOToken URI the issue will attach a document to justify the offchain report
    /// @param amounts is in paymentToken units, so if paymentToken is USDC, this amount goes with 6 decimals
    /// @param addresses the user that should receive the corresponding tokens from this offchain ticket. Should be wwhitelisted.
    /// @param proofOfPayment is the proof that the investor has payed the amount in the offchain report
    function offchainReporting(
        uint256[] calldata amounts,
        address[] calldata addresses,
        string[] calldata proofOfPayment
    ) external onlyRole(Roles.ESCROW_OFFCHAIN_REPORTER_ROLE) {
        if (amounts.length == 0 || amounts.length != addresses.length)
            revert Errors.LengthsMismatch();

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
                revert Errors.OffchainAmountExceedsAvailableAmount(
                    availableAmountCached,
                    totalAmount
                );
            if (
                !stoRelatedToken.hasRole(
                    Roles.TOKEN_WHITELIST_ROLE,
                    addresses[i]
                ) && !stoRelatedToken.whitelist_OLD_SLOT(addresses[i])
            ) revert Errors.UserIsNotWhitelisted(addresses[i]);
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
