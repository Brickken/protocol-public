/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {Roles} from "../helpers/Roles.sol";
import {DTOCommonErrors} from "../helpers/Errors.sol";
import {DTOTokenUpgradeable, ERC20BurnableUpgradeable} from "./DTOTokenUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {AccessControlEnumerableUpgradeable, AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {IDTOFactoryUpgradeable} from "../interfaces/IDTOFactoryUpgradeable.sol";

/// @title DTOTokenManagedUpgradeable wrapper around DTOTokenUpgradeable contract to add access control and roles
/// @custom:security-contact tech@brickken.com
contract DTOTokenManagedUpgradeable is
    DTOTokenUpgradeable,
    AccessControlEnumerableUpgradeable
{
    /// @dev whether to automatically confiscate tokens upong blacklisting an already whitelisted user.
    /// This can prevent accumulation of debt repayments on users which are permanently banned.
    bool public confiscateOnBlacklist;

    /// @dev Method to initialize the contract. If further initializations are needed, the reinitializer modifier should be changed with the newer version
    /// @dev future initializations will not re-set the roles and will skip the roles assignments. If contract is already initialized once, only the DEFAULT_ADMIN_ROLE can call this function.
    function initialize(
        IDTOFactoryUpgradeable.TokenizationConfig calldata config,
        address newBorrower,
        address admin,
        uint8 version
    ) external reinitializer(version) {
        /// Prevent to initialize the contract with a zero address
        if (newBorrower == address(0) || config.paymentToken == address(0))
            revert DTOCommonErrors.NotZeroAddress();

        /// Prevent to initialize the contract with debt interest rate is gretter than MAX_INTEREST_RATE_LIMIT
        if (config.debtInterestRate > MAX_INTEREST_RATE_LIMIT)
            revert DTOCommonErrors.InterestRateOverLimits(
                config.debtInterestRate
            );

        /// Prevent to initialize the new payment token as EOA
        if (!AddressUpgradeable.isContract(config.paymentToken))
            revert DTOCommonErrors.NotContractAddress();

        if (
            getRoleMemberCount(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) == 0
        ) {
            // It's the first time initializing

            _grantRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, admin);
            _grantRole(Roles.TOKEN_URL_ROLE, admin); // Help borrower with manteinance just in case
            _grantRole(Roles.TOKEN_URL_ROLE, newBorrower);

            _grantRole(Roles.TOKEN_MINTER_ADMIN_ROLE, newBorrower); // Allow borrower to set a new minter
            _grantRole(Roles.TOKEN_MINTER_ADMIN_ROLE, _msgSender()); // Allow factory to set a new minter

            _grantRole(Roles.TOKEN_DEBT_REPAY_TOGGLER_ROLE, _msgSender()); // Allow factory to toggle debt repayment

            _grantRole(Roles.TOKEN_WHITELIST_ADMIN_ROLE, newBorrower);

            _grantRole(Roles.TOKEN_CONFISCATE_ADMIN_ROLE, admin); // Who can pause / unpause / disable confiscation
            _grantRole(Roles.TOKEN_CONFISCATE_EXECUTOR_ROLE, admin); // Who can execute confiscation

            _grantRole(Roles.TOKEN_MINTER_ROLE, newBorrower);

            _grantRole(Roles.TOKEN_WHITELIST_ROLE, newBorrower);
            _grantRole(Roles.TOKEN_DEBT_REPAY_MANAGER_ROLE, newBorrower);
        } else if (
            !hasRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, _msgSender())
        )
            // then, count > 0, check who is calling
            revert DTOCommonErrors.UserIsNotAdmin(_msgSender());

        __DTOTokenUpgradeable_init(
            config.name,
            config.symbol,
            config.paymentToken,
            config.debtInterestRate
        );

        url = config.url;
        supplyCap = config.supplyCap;
        borrower = newBorrower;

        // Whether or not this exceeds the maxSupply has been checked already in the DTOFactoryManaged before initializing this
        for (uint256 i = 0; i < config.initialHolders.length; i++) {
            if (config.initialHolders[i] == address(0))
                revert DTOCommonErrors.NotZeroAddress();
            _mint(config.initialHolders[i], config.preMints[i]);
            _grantRole(Roles.TOKEN_WHITELIST_ROLE, config.initialHolders[i]);
        }

        // Set paymentTokenUsed in already existing distributions
        for (uint256 i = 0; i < numberOfDebtRepayments; i++) {
            debtRepaymentDistributions[i].paymentTokenUsed = address(
                paymentToken
            );
        }
    }

    /// @dev Method to change the current borrower. Used if borrower wallet got's hacked or private keys leaked. Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newBorrower address of the new borrower. Roles will be revoked from old address and granted to the new one.
    function changeBorrower(
        address newBorrower
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _revokeRole(Roles.TOKEN_URL_ROLE, borrower);
        _revokeRole(Roles.TOKEN_MINTER_ROLE, borrower);
        _revokeRole(Roles.TOKEN_WHITELIST_ROLE, borrower);
        _revokeRole(Roles.TOKEN_MINTER_ADMIN_ROLE, borrower);
        _revokeRole(Roles.TOKEN_WHITELIST_ADMIN_ROLE, borrower);
        _revokeRole(Roles.TOKEN_DEBT_REPAY_MANAGER_ROLE, borrower);

        borrower = newBorrower;

        _grantRole(Roles.TOKEN_URL_ROLE, newBorrower);
        _grantRole(Roles.TOKEN_MINTER_ROLE, newBorrower);
        _grantRole(Roles.TOKEN_WHITELIST_ROLE, newBorrower);
        _grantRole(Roles.TOKEN_MINTER_ADMIN_ROLE, newBorrower);
        _grantRole(Roles.TOKEN_WHITELIST_ADMIN_ROLE, newBorrower);
        _grantRole(Roles.TOKEN_DEBT_REPAY_MANAGER_ROLE, newBorrower);

        emit ChangeBorrower(borrower);
    }

    /// @dev Method to whitelist/blacklist lenders after accepting/rejecting their KYC. This method is only available to the account with the TOKEN_WHITELIST_ADMIN_ROLE
    /// @param users to be accepted/rejected
    /// @param statuses whether those users should be accepted or rejected
    function changeWhitelist(
        address[] calldata users,
        bool[] calldata statuses
    ) external onlyRole(Roles.TOKEN_WHITELIST_ADMIN_ROLE) {
        if (users.length != statuses.length || users.length == 0)
            revert DTOCommonErrors.LengthsMismatch();
        for (uint256 i = 0; i < users.length; i++) {
            if (statuses[i]) _grantRole(Roles.TOKEN_WHITELIST_ROLE, users[i]);
            else {
                if (confiscateOnBlacklist)
                    _transfer(users[i], _msgSender(), balanceOf(users[i]));
                _revokeRole(Roles.TOKEN_WHITELIST_ROLE, users[i]);
            }
        }
        emit ChangeWhitelist(users, statuses, _msgSender());
    }

    /// @dev Method to grant minter role to an account. This method is only available to the account with the TOKEN_MINTER_ADMIN_ROLE
    /// @param newMinter the addres whose minter role should be granted
    function addMinter(
        address newMinter
    ) external onlyRole(Roles.TOKEN_MINTER_ADMIN_ROLE) {
        _grantRole(Roles.TOKEN_MINTER_ROLE, newMinter);
        emit ChangeMinter(newMinter);
    }

    /// @dev Method to revoke minter role to an account. This method is only available to the account with the TOKEN_MINTER_ADMIN_ROLE
    /// @param oldMinter the addres whose minter role should be removed
    function removeMinter(
        address oldMinter
    ) external onlyRole(Roles.TOKEN_MINTER_ADMIN_ROLE) {
        _revokeRole(Roles.TOKEN_MINTER_ROLE, oldMinter);
        emit ChangeMinter(oldMinter);
    }

    /// @dev Method to grant debt repayment toggler role to an account. This method is only available to the account with the TOKEN_DEBT_REPAY_TOGGLER_ROLE
    /// @param newToggler the address whose repayment toggler role should be granted
    function addDebtRepayToggler(
        address newToggler
    ) external onlyRole(Roles.TOKEN_DEBT_REPAY_TOGGLER_ROLE) {
        _grantRole(Roles.TOKEN_DEBT_REPAY_TOGGLER_ROLE, newToggler);
        emit ChangeDebtRepayToggler(newToggler);
    }

    /// @dev Method to revoke debt repayment toggler role to an account. This method is only available to the account with the TOKEN_DEBT_REPAY_TOGGLER_ROLE
    /// @param oldToggler the address whose repayment toggler role should be removed
    function removeDebtRepayToggler(
        address oldToggler
    ) external onlyRole(Roles.TOKEN_DEBT_REPAY_TOGGLER_ROLE) {
        _revokeRole(Roles.TOKEN_DEBT_REPAY_TOGGLER_ROLE, oldToggler);
        emit ChangeDebtRepayToggler(oldToggler);
    }

    /// @dev Method to mint tokens directly. This method is only available to the account with the TOKEN_MINTER_ROLE role
    /// @param _to the address to who the tokens should be minted
    /// @param _amount the amount of tokens to be minted
    function mint(
        address _to,
        uint256 _amount
    ) external onlyRole(Roles.TOKEN_MINTER_ROLE) {
        _mintTokens(_to, _amount);
    }

    /// @dev Method to mint tokens directly. This method is only available to the account with the TOKEN_MINTER_ROLE role
    /// @param _addresess the addresses to whom the tokens should be minted
    /// @param _amounts the amount of tokens to be minted for each address
    function mintBatch(
        address[] calldata _addresess,
        uint256[] calldata _amounts
    ) external onlyRole(Roles.TOKEN_MINTER_ROLE) {
        if (_addresess.length == 0 || _addresess.length != _amounts.length)
            revert DTOCommonErrors.LengthsMismatch();
        for (uint256 i = 0; i < _addresess.length; i++) {
            _mintTokens(_addresess[i], _amounts[i]);
        }
    }

    /// @dev Method to setup or update the IPFS URI where the all documents of the tokenization are stored
    /// @dev This method is only available to the account with the TOKEN_URL_ROLE role
    /// @param newURL the new URI to be set
    function changeUrl(
        string memory newURL
    ) external onlyRole(Roles.TOKEN_URL_ROLE) {
        _changeUrl(newURL);
        emit ChangeURL(url);
    }

    /// @dev Method to setup or update the supply cap of the token. This method is only available to the account with the DEFAULT_ADMIN_ROLE role
    /// @param newSupplyCap the new supply cap to set
    function changeSupplyCap(
        uint224 newSupplyCap
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _changeSupplyCap(newSupplyCap);
        emit ChangeSupplyCap(supplyCap);
    }

    /// @dev Method to add a new debt repayment to DTOToken holders
    /// @param _debtCapitalAmount debt capital amount to be repaid
    /// @param _debtInterestAmount debt interest amount to be repaid
    function addDebtRepayment(
        uint256 _debtCapitalAmount,
        uint256 _debtInterestAmount
    ) external onlyRole(Roles.TOKEN_DEBT_REPAY_MANAGER_ROLE) {
        _addDebtRepayment(_debtCapitalAmount, _debtInterestAmount);
        emit NewDebtRepayment(
            address(paymentToken),
            _debtCapitalAmount,
            _debtInterestAmount
        );
    }

    /// @dev Method to change the payment token. This method is only available to account with the DEFAULT_ADMIN_ROLE role
    /// @param _newPaymentToken is the new payment token address
    function changePaymentToken(
        address _newPaymentToken
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        emit NewPaymentToken(address(paymentToken), _newPaymentToken);
        _changePaymentToken(_newPaymentToken);
    }

    /// @dev Method to change interest rate. . This method is only available to account with the DEFAULT_ADMIN_ROLE role
    /// @param _newInterestRate is the new interest rate
    function changeInterestRate(
        uint24 _newInterestRate
    ) external onlyRole(Roles.TOKEN_DEBT_REPAY_MANAGER_ROLE) {
        _changeInterestRate(_newInterestRate);
    }

    /// @dev Method to toggle debt repayment. This method is only available to account with the TOKEN_DEBT_REPAY_MANAGER_ROLE role
    /// @param _newStatus is the new status of the debt repayment
    function toggleDebtRepayment(
        bool _newStatus
    ) public onlyRole(Roles.TOKEN_DEBT_REPAY_TOGGLER_ROLE) {
        _toggleDebtRepayment(_newStatus);
    }

    function addDTOEscrow(address dtoEscrowAddress) external {
        if (address(dtoRelatedEscrow) == address(0)) {
            _addDTOEscrow(dtoEscrowAddress);
        }
    }

    /// @dev Method to claim debt repayments. This method is only available to the accounts with the TOKEN_WHITELIST_ROLE role
    /// @param upTo index up to which distribution the user wants to claim tokens. 0 if has to be ignored. Used if distributions are too many that the claim distribution process runs out of gas. So that it can be done in little steps.
    /// @param onBehalfOf address of the lender who will get the debt repayment
    function claimDebtRepay(uint256 upTo, address onBehalfOf) external {
        address caller = _msgSender();
        if (!hasRole(Roles.TOKEN_WHITELIST_ROLE, caller))
            revert DTOCommonErrors.UserIsNotWhitelisted(caller);

        if (
            onBehalfOf != caller &&
            !hasRole(Roles.TOKEN_WHITELIST_ROLE, onBehalfOf)
        ) revert DTOCommonErrors.UserIsNotWhitelisted(onBehalfOf);

        _claimDebtRepay(upTo, onBehalfOf);
    }

    /// @dev Method to confiscate tokens in case of failure/lost or illegal activity. This method is only available to the TOKEN_CONFISCATE_EXECUTOR_ROLE
    /// @param from Array of addresses of where tokens are lost/illegaly hold
    /// @param amount Array of amounts of tokens to be confiscated
    /// @param to Address of where tokens are to be sent
    function confiscate(
        address[] memory from,
        uint[] memory amount,
        address to
    ) external onlyRole(Roles.TOKEN_CONFISCATE_EXECUTOR_ROLE) {
        _confiscate(from, amount, to);
        emit DTOTokensConfiscated(from, to, amount);
    }

    /// @dev Method to pause/unpause confiscation feature. This method is only available to the TOKEN_CONFISCATE_ADMIN_ROLE
    /// @param _status whether to pause or unpause the confiscation
    /// @param _confiscateOnBlacklist whether to automatically confiscate tokens upon blacklisting
    function changeConfiscation(
        bool _status,
        bool _confiscateOnBlacklist
    ) external onlyRole(Roles.TOKEN_CONFISCATE_ADMIN_ROLE) {
        _changeConfiscation(_status);
        confiscateOnBlacklist = _confiscateOnBlacklist;
        emit DTOTokenConfiscationStatusChanged(
            confiscation,
            _status,
            confiscateOnBlacklist
        );
    }

    /// @dev Method to disable confiscation feature forever. This method is only available to the TOKEN_CONFISCATE_ADMIN_ROLE
    function disableConfiscationFeature()
        external
        onlyRole(Roles.TOKEN_CONFISCATE_ADMIN_ROLE)
    {
        _disableConfiscationFeature();
        emit DTOTokenConfiscationDisabled();
    }

    /// @dev Hook that is called before any transfer of tokens. This includes minting and burning.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (
            (from != address(0)) &&
            (to != address(0)) &&
            (!hasRole(Roles.TOKEN_WHITELIST_ROLE, from)) &&
            !hasRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, to)
        ) revert DTOCommonErrors.UserIsNotWhitelisted(from);

        // Start tracking the user if it's not tracked yet
        if (!trackings(to)) {
            lastClaimedBlock[to] = block.number;
            _startTracking(to);
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    uint256[49] private __gap;
}
