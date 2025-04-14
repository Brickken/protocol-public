/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { Roles } from "../helpers/Roles.sol";
import { STOFactoryUpgradeable } from "./STOFactoryUpgradeable.sol";
import { Errors } from "../helpers/Errors.sol";
import { IBeacon } from "../helpers/BeaconProxy.sol";
import { ISTOToken } from "../interfaces/ISTOToken.sol";
import { AccessControlEnumerableUpgradeable, AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import { IPriceAndSwapManager } from "../helpers/PriceAndSwapManager.sol";

/// @title STOFactoryManaged wrapper around STOFactoryUpgradeable contract to add access control and roles
/// @custom:security-contact tech@brickken.com
contract STOFactoryManagedUpgradeable is STOFactoryUpgradeable, AccessControlEnumerableUpgradeable {

    // Initial default values aimed to change in the future
    uint256 constant PRICE_IN_BKN = 31250e18;
    uint256 constant PRICE_IN_USD = 5000e18;

    mapping(address tokenizer => uint256 credits) public tokenizationCredits;

    modifier hasEnoughCredits {
        address caller = _msgSender();
        if(tokenizationCredits[caller] == 0) revert Errors.NotEnoughCredits();
        _;
        tokenizationCredits[caller] -= 1;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @dev constructor to set immutable variables
    constructor(
        address _bkn,
        address _router,
        address _priceAndSwapManager
    ) STOFactoryUpgradeable(_bkn, _router, _priceAndSwapManager) {}

    /// @dev Method to initialize the contract. If further initializations are needed, the reinitializer modifier should be changed with the newer version
    /// @dev future initializations will not re-set the roles and will skip the roles assignments. If contract is already initialized once, only the DEFAULT_ADMIN_ROLE can call this function.
    function initialize(
        address beaconToken,
        address beaconEscrow,
        address vault,
        address admin,
        address[] calldata _whitelist,
        uint8 version
    ) external reinitializer(version) {

        __AccessControlEnumerable_init();
        __STOFactory_init();

        if (admin == address(0)) revert Errors.NotZeroAddress();

        if (
            getRoleMemberCount(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) != 0 && 
            !hasRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, _msgSender())
        )
            revert Errors.UserIsNotAdmin(_msgSender());
        
        if (getRoleMemberCount(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) == 0) {
            _grantRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, admin);
            _grantRole(Roles.FACTORY_WHITELISTER_ROLE, admin);
            _grantRole(Roles.FACTORY_ISSUER_ROLE, admin);
            _grantRole(Roles.FACTORY_PAUSER_ROLE, admin);
        }

        if (vault == address(0)) revert Errors.NotZeroAddress();

        brickkenVault = vault;
        stoBeaconToken = beaconToken;
        stoBeaconEscrow = beaconEscrow;
        priceInBKN = PRICE_IN_BKN;
        priceInUSD = PRICE_IN_USD;

        for(uint256 i; i <_whitelist.length;) {
            _grantRole(Roles.FACTORY_ISSUER_ROLE, _whitelist[i]);
            tokenizationCredits[_whitelist[i]] = 1;
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Method to pause the factory. Only FACTORY_PAUSER_ROLE can call this function.
    function pauseFactory() external whenNotPaused onlyRole(Roles.FACTORY_PAUSER_ROLE) {
        _pause();
    }

    /// @dev Method to unpause the factory. Only FACTORY_PAUSER_ROLE can call this function.
    function unpauseFactory() external whenPaused onlyRole(Roles.FACTORY_PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Method to deploy a new tokenization (escrow + token). Only users with FACTORY_ISSUER_ROLE can call this function.
    /// @param config Configuration of the token to be deployed,
    /// @param priceReport the offchain price report struct if any
    function newTokenization(
        TokenizationConfig calldata config,
        OffchainPriceReport calldata priceReport,
        PermitStruct calldata permit
    ) external whenNotPaused hasEnoughCredits {
        address caller = _msgSender();
        if(!hasRole(Roles.FACTORY_ISSUER_ROLE, caller) && !whitelist_OLD_SLOT[caller]) revert Errors.UserIsNotWhitelisted(caller); // Do this instead of using onlyRole for backward compatibility with whitelist_OLD_SLOT mapping
        /// By default each new token and escrow is owned by Brickken. Adminship can be handed over at any moment.
        (address stoToken, address stoEscrow ) = _newTokenization(
            config,
            priceReport,
            permit,
            getRoleMember(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE, 0) // admin
        );

        // Setup the escrow as a valid minter
        ISTOToken(stoToken).addMinter(stoEscrow);

        // Renounce being minter admin, permission given termporary to set the escrow as a minter
        ISTOToken(stoToken).renounceRole(Roles.TOKEN_MINTER_ADMIN_ROLE, address(this));

        emit NewTokenization(idSTOs, stoTokens[idSTOs], stoEscrows[idSTOs]);
    }

    /// @dev Method to change the fee price in BKN and USD. Only DEFAULT_ADMIN_ROLE can call this function.
    /// @param newPriceInBKN New price in BKN
    /// @param newPriceInUSD New price in USD
    function changeFee(
        uint256 newPriceInBKN,
        uint256 newPriceInUSD
    ) external whenNotPaused onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _changeFee(newPriceInBKN, newPriceInUSD);
        emit ChangeFee(newPriceInBKN, newPriceInUSD);
    }

    /// @dev Method to change the TWAP interval used to retrieve the price of BKN. Only DEFAULT_ADMIN_ROLE can call thgis function.
    /// @param newTWAP the new TWAP Interval
    function changeBKNPriceTWAPInterval(
        uint256 newTWAP
    ) external whenNotPaused onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        _changeBKNPriceTWAPInterval(newTWAP);
        emit BKNPriceTWAPIntervalChanged(newTWAP);
    }

    /// @dev Method to change configured parameters within the contract. Only DEFAULT_ADMIN_ROLE can call this function.
    /// @param vault this will change where fees are sent
    /// @param beaconToken this will change the beacon token used for new tokenizations
    /// @param beaconEscrow this will change the beacon escrow used for new tokenizations
    /// @param allowedEscrows escrows whose status must be changed in the PriceAndSwapManager
    /// @param allowedEscrowsStatuses statuses to be applied to the above escrows
    function changeConfig(
        address vault,
        address beaconToken,
        address beaconEscrow,
        address[] calldata allowedEscrows,
        bool[] calldata allowedEscrowsStatuses
    ) external onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {
        uint256 length = allowedEscrows.length;

        if(
            length != allowedEscrowsStatuses.length
        ) revert Errors.LengthsMismatch();

        _changeConfig(
            vault,
            beaconToken,
            beaconEscrow
        );

        for(uint256 i; i < length;) {
            if(allowedEscrows[i] == address(0)) revert Errors.NotZeroAddress();
            IPriceAndSwapManager(priceAndSwapManager).setAllowed(allowedEscrows[i], allowedEscrowsStatuses[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Method to whitelist or blacklist users from running new tokenizations. Only FACTORY_WHITELISTER_ROLE can call this function.
    /// @param users whose whitelist status must change
    /// @param statuses statuses of above users to be set
    function changeWhitelist(
        address[] calldata users,
        bool[] calldata statuses,
        uint256[] calldata credits
    ) external whenNotPaused onlyRole(Roles.FACTORY_WHITELISTER_ROLE) {
        if (users.length != statuses.length || users.length == 0)
            revert Errors.LengthsMismatch();

        for (uint256 i = 0; i < users.length;) {
            if(statuses[i] && !hasRole(Roles.FACTORY_ISSUER_ROLE, users[i])) _grantRole(Roles.FACTORY_ISSUER_ROLE, users[i]);
            else if(!statuses[i] && hasRole(Roles.FACTORY_ISSUER_ROLE, users[i])) {
                _revokeRole(Roles.FACTORY_ISSUER_ROLE, users[i]);
                if(whitelist_OLD_SLOT[users[i]]) whitelist_OLD_SLOT[users[i]] = false;
            }
            if(credits.length > 0) tokenizationCredits[users[i]] = credits[i];
            else tokenizationCredits[users[i]] = 1;
            unchecked {
                ++i;
            }
        }

        emit ChangeWhitelist(users, statuses, _msgSender());
    }

    /// @dev Override OpenZeppelin contracts function to restrict upgradeability to only accounts with the DEFAULT_ADMIN_ROLE
    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyRole(AccessControlUpgradeable.DEFAULT_ADMIN_ROLE) {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}