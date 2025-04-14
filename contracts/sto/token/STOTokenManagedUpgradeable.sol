/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {Roles} from "../helpers/Roles.sol";
import {Errors} from "../helpers/Errors.sol";
import {STOTokenUpgradeable, ERC20BurnableUpgradeable} from "./STOTokenUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {AccessControlEnumerableUpgradeable, AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {ISTOFactoryUpgradeable} from "../interfaces/ISTOFactoryUpgradeable.sol";

/// @title STOTokenManagedUpgradeable wrapper around STOTokenUpgradeable contract to add access control and roles
/// @custom:security-contact tech@brickken.com
contract STOTokenManagedUpgradeable is
    STOTokenUpgradeable,
    AccessControlEnumerableUpgradeable
{
    /// @dev whether to automatically confiscate tokens upong blacklisting an already whitelisted user.
    /// This can prevent accumulation of dividends on users which are permanently banned.
    bool public confiscateOnBlacklist;

    /// @dev Method to initialize the contract. If further initializations are needed, the reinitializer modifier should be changed with the newer version
    /// @dev future initializations will not re-set the roles and will skip the roles assignments. If contract is already initialized once, only the DEFAULT_ADMIN_ROLE can call this function.
    function initialize(
        ISTOFactoryUpgradeable.TokenizationConfig calldata config,
        address newIssuer,
        address admin,
        uint8 version
    ) external reinitializer(version) {
        /// Prevent to initialize the contract with a zero address
        if (newIssuer == address(0) || config.paymentToken == address(0))
            revert Errors.NotZeroAddress();

        /// Prevent to initialize the new payment token as EOA
        if (!AddressUpgradeable.isContract(config.paymentToken))
            revert Errors.NotContractAddress();

        if (
            getRoleMemberCount(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) == 0
        ) {
            // It's the first time initializing

            _grantRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, admin);
            _grantRole(Roles.TOKEN_URL_ROLE, admin); // Help issuer with manteinance just in case
            _grantRole(Roles.TOKEN_URL_ROLE, newIssuer);

            _grantRole(Roles.TOKEN_MINTER_ADMIN_ROLE, newIssuer); // Allow factory to set a new minter
            _grantRole(Roles.TOKEN_MINTER_ADMIN_ROLE, _msgSender()); // Allow factory to set a new minter

            _grantRole(Roles.TOKEN_WHITELIST_ADMIN_ROLE, newIssuer);

            _grantRole(Roles.TOKEN_CONFISCATE_ADMIN_ROLE, admin); // Who can pause / unpause / disable confiscation
            _grantRole(Roles.TOKEN_CONFISCATE_EXECUTOR_ROLE, admin); // Who can execute confiscation

            _grantRole(Roles.TOKEN_MINTER_ROLE, newIssuer);
            _grantRole(Roles.TOKEN_MINTER_ROLE, minter_OLD_SLOT);

            _grantRole(Roles.TOKEN_WHITELIST_ROLE, newIssuer);
            _grantRole(Roles.TOKEN_DIVIDEND_DISTRIBUTOR_ROLE, newIssuer);
        } else if (
            !hasRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, _msgSender())
        )
            // then, count > 0, check who is calling
            revert Errors.UserIsNotAdmin(_msgSender());

        __STOTokenUpgradeable_init(
            config.name,
            config.symbol,
            config.paymentToken
        );

        url = config.url;
        supplyCap = config.supplyCap;
        issuer = newIssuer;

        // Whether or not this exceeds the maxSupply has been checked already in the STOFactoryManaged before initializing this
        for (uint256 i = 0; i < config.initialHolders.length; i++) {
            if (config.initialHolders[i] == address(0))
                revert Errors.NotZeroAddress();
            _mint(config.initialHolders[i], config.preMints[i]);
            _grantRole(Roles.TOKEN_WHITELIST_ROLE, config.initialHolders[i]);
        }

        // Set paymentTokenUsed in already existing distributions
        for (uint256 i = 0; i < numberOfDistributions; i++) {
            dividendDistributions[i].paymentTokenUsed = address(paymentToken);
        }
    }

    /// @dev Method to change the current issuer. Used if issuer wallet got's hacked or private keys leaked. Only The DEFAULT_ADMIN_ROLE can call this function.
    /// @param newIssuer address of the new issuer. Roles will be revoked from old address and granted to the new one.
    function changeIssuer(
        address newIssuer
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _revokeRole(Roles.TOKEN_URL_ROLE, issuer);
        _revokeRole(Roles.TOKEN_MINTER_ROLE, issuer);
        _revokeRole(Roles.TOKEN_WHITELIST_ROLE, issuer);
        if (whitelist_OLD_SLOT[issuer]) whitelist_OLD_SLOT[issuer] = false;
        _revokeRole(Roles.TOKEN_MINTER_ADMIN_ROLE, issuer);
        _revokeRole(Roles.TOKEN_WHITELIST_ADMIN_ROLE, issuer);
        _revokeRole(Roles.TOKEN_DIVIDEND_DISTRIBUTOR_ROLE, issuer);

        issuer = newIssuer;

        _grantRole(Roles.TOKEN_URL_ROLE, newIssuer);
        _grantRole(Roles.TOKEN_MINTER_ROLE, newIssuer);
        _grantRole(Roles.TOKEN_WHITELIST_ROLE, newIssuer);
        _grantRole(Roles.TOKEN_MINTER_ADMIN_ROLE, newIssuer);
        _grantRole(Roles.TOKEN_WHITELIST_ADMIN_ROLE, newIssuer);
        _grantRole(Roles.TOKEN_DIVIDEND_DISTRIBUTOR_ROLE, newIssuer);

        emit ChangeIssuer(issuer);
    }

    /// @dev Method to whitelist/blacklist investors after accepting/rejecting their KYC. This method is only available to the account with the TOKEN_WHITELIST_ADMIN_ROLE
    /// @param users to be accepted/rejected
    /// @param statuses whether those users should be accepted or rejected
    function changeWhitelist(
        address[] calldata users,
        bool[] calldata statuses
    ) external onlyRole(Roles.TOKEN_WHITELIST_ADMIN_ROLE) {
        if (users.length != statuses.length || users.length == 0)
            revert Errors.LengthsMismatch();
        for (uint256 i = 0; i < users.length; i++) {
            if (statuses[i]) _grantRole(Roles.TOKEN_WHITELIST_ROLE, users[i]);
            else {
                if (confiscateOnBlacklist)
                    _transfer(users[i], _msgSender(), balanceOf(users[i]));
                _revokeRole(Roles.TOKEN_WHITELIST_ROLE, users[i]);
                if (whitelist_OLD_SLOT[users[i]])
                    whitelist_OLD_SLOT[users[i]] = false;
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
        if(_addresess.length == 0 || _addresess.length != _amounts.length ) 
            revert Errors.LengthsMismatch();
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

    /// @dev Method to add a new dividends distribution among token holders. This method is only available to the account with the TOKEN_DIVIDEND_DISTRIBUTOR_ROLE role
    /// @param _totalAmount Total Amount of Dividend
    function addDistDividend(
        uint256 _totalAmount
    ) external onlyRole(Roles.TOKEN_DIVIDEND_DISTRIBUTOR_ROLE) {
        _addDistDividend(_totalAmount);
        emit NewDividendDistribution(address(paymentToken), _totalAmount);
    }

    /// @dev Method to change the payment token. This method is only available to account with the DEFAULT_ADMIN_ROLE role
    /// @param _newPaymentToken is the new payment token address
    function changePaymentToken(
        address _newPaymentToken
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        emit NewPaymentToken(address(paymentToken), _newPaymentToken);
        _changePaymentToken(_newPaymentToken);
    }

    /// @dev Method to claim dividends of the token. This method is only available to the accounts with the TOKEN_WHITELIST_ROLE role
    /// @param upTo index up to which distribution the user wants to claim tokens. 0 if has to be ignored. Used if distributions are too many that the claim distribution process runs out of gas. So that it can be done in little steps.
    /// @param onBehalfOf address of the investor who will get the dividends
    function claimDividends(uint256 upTo, address onBehalfOf) external {
        address caller = _msgSender();
        if (
            !hasRole(Roles.TOKEN_WHITELIST_ROLE, caller) &&
            !whitelist_OLD_SLOT[caller]
        ) revert Errors.UserIsNotWhitelisted(caller); // Do this instead of using onlyRole for backward compatibility with whitelist_OLD_SLOT mapping

        if (
            onBehalfOf != caller &&
            !hasRole(Roles.TOKEN_WHITELIST_ROLE, onBehalfOf) &&
            !whitelist_OLD_SLOT[onBehalfOf]
        ) revert Errors.UserIsNotWhitelisted(onBehalfOf);

        _claimDividends(upTo, onBehalfOf);
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
        emit STOTokensConfiscated(from, to, amount);
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
        emit STOTokenConfiscationStatusChanged(
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
        emit STOTokenConfiscationDisabled();
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
            (!hasRole(Roles.TOKEN_WHITELIST_ROLE, from) &&
                !whitelist_OLD_SLOT[from]) &&
            !hasRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, to)
        ) revert Errors.UserIsNotWhitelisted(from);

        // Start tracking the user if it's not tracked yet
        if (!trackings(to)) {
            lastClaimedBlock[to] = block.number;
            _startTracking(to);
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    uint256[49] private __gap;
}
