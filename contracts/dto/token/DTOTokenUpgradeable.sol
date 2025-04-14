/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {DTOTokenConfiscateUpgradeable, DTOCommonErrors} from "./DTOTokenConfiscateUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {DTOTokenCheckpointsUpgradeable, ERC20BurnableUpgradeable, ERC20Upgradeable} from "./DTOTokenCheckpointsUpgradeable.sol";

/// @title DTOTokenUpgradeable ERC20 Template for DTO/Debt
/// @custom:security-contact tech@brickken.com
contract DTOTokenUpgradeable is Initializable, DTOTokenConfiscateUpgradeable {
    string public url;
    uint224 public supplyCap; // This is unrelated to the _maxSupply of the checkpoints feature. This is optional, while the other is mandatory to be respected at any point.
    address public borrower;
    uint256 public totalHolders;

    /// @dev Mapping to store whether an address is already a holder or not
    mapping(address user => bool isHolder) public holders;

    /// @dev Event to signal that the borrower changed
    /// @param borrower New borrower address
    event ChangeBorrower(address indexed borrower);

    /// @dev Event to signal that the minter changed
    /// @param newMinter New minter address
    event ChangeMinter(address indexed newMinter);

    /// @dev Event to signal that the  debt repayment toggler changed
    /// @param newToggler New minter address
    event ChangeDebtRepayToggler(address indexed newToggler);

    /// @dev Event to signal that the url changed
    /// @param newURL New url
    event ChangeURL(string newURL);

    /// @dev Event to signal that the max supply changed
    /// @param newSupplyCap New max supply
    event ChangeSupplyCap(uint224 newSupplyCap);

    /// @dev Event emitted when any group of wallet is added or remove to the whitelist
    /// @param addresses array of addresses of the wallets changed in the whitelist
    /// @param statuses array of boolean status to define if add or remove the wallet to the whitelist
    /// @param account address of the account with the TOKEN_WHITELIST_ADMIN_ROLE role
    event ChangeWhitelist(
        address[] addresses,
        bool[] statuses,
        address account
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // INTERNAL / PRIVATE FUNCTIONS

    function __DTOTokenUpgradeable_init(
        string calldata newName,
        string calldata newSymbol,
        address newPaymentToken,
        uint24 newDebtInterestRate
    ) internal {
        __DTOTokenConfiscate_init(
            newPaymentToken,
            newName,
            newSymbol,
            newDebtInterestRate
        );
    }

    /// @dev Method to setup or update the max supply of STOToken
    /// @param newSupplyCap the new max supply to set
    function _changeSupplyCap(uint224 newSupplyCap) internal {
        if (totalSupply() > newSupplyCap && newSupplyCap != 0)
            revert DTOCommonErrors.SupplyCapExceeded();
        supplyCap = newSupplyCap;
    }

    /// @dev Method to setup or update the IPFS URI where the all documents of the tokenization are stored
    /// @param newURL the new URI to be set
    function _changeUrl(string memory newURL) internal {
        url = newURL;
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function version() external view returns (uint8) {
        return _getInitializedVersion();
    }

    /// Method to mint tokens directly
    /// @param _to the address to who the tokens should be minted
    /// @param _amount the amount of tokens to be minted
    function _mintTokens(address _to, uint256 _amount) internal {
        if (supplyCap > 0 && totalSupply() + _amount > supplyCap)
            revert DTOCommonErrors.SupplyCapExceeded();
        _mint(_to, _amount); // Whether the amount exceeds type(uint224).max is checked internally
    }

    /// @dev Hook that is called after any transfer of tokens. This includes minting and burning.
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(DTOTokenCheckpointsUpgradeable) {
        uint256 balanceFrom = balanceOf(from);

        // If it's minting, the from is address(0) so no need to account for that
        // If it's burning, the balanceFrom will account if now the original user has no tokens
        if (from != address(0) && balanceFrom == 0 && amount > 0) {
            totalHolders = totalHolders - 1;
            holders[from] = false;
        }

        // If it's minting, the `to` is checked to already exist as holder or not
        // If it's burning, the `to` is the zero address so no need to account for it
        if (amount > 0 && !holders[to] && to != address(0)) {
            totalHolders = totalHolders + 1;
            holders[to] = true;
        }

        super._afterTokenTransfer(from, to, amount);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[43] private __gap;
}
