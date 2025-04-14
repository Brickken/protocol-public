// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { STOTokenDividendUpgradeable, Errors } from  "./STOTokenDividendUpgradeable.sol";

/// @title STOTokenConfiscateUpgradeable confiscation module
/// @custom:security-contact tech@brickken.com
abstract contract STOTokenConfiscateUpgradeable is STOTokenDividendUpgradeable {
    /// confiscation feature is enabled by default
    bool public confiscation;
    /// flag to disable forever confiscation feature
    bool public confiscationFeatureDisabled;

    /// @dev Event to signal that STO tokens have been confiscated
    /// @param from  array of addresses from where STO tokens are lost
    /// @param to address where STO tokens are being sent
    /// @param amount array of amounts of STO tokens to be confiscated
    event STOTokensConfiscated(
        address[] from, 
        address to, 
        uint[] amount 
    );

    /// @dev Event to signal that the STO tokens have been confiscated
    /// @param confiscation previews status of the STO tokens confiscation
    /// @param status changed status of the STO tokens confiscation 
    /// @param confiscateOnBlacklist whether blacklisting automatically triggers a confiscation
    event STOTokenConfiscationStatusChanged(bool confiscation, bool status, bool confiscateOnBlacklist);

    /// @dev Event to signal that the STOToken has confiscation feature disabled now
    event STOTokenConfiscationDisabled();

    // INTERNAL / PRIVATE FUNCTIONS

    function __STOTokenConfiscate_init(
        address paymentToken_,
        string calldata name_,
        string calldata symbol_
    ) internal {
        confiscation = true;

        __STOTokenDividend_init(paymentToken_, name_, symbol_);
    }

    /// @dev Method to confiscate STO tokens in case of failure/lost or illegal activity
    /// @param from Array of addresses of where STO tokens are lost
    /// @param amount Array of amounts of STO tokens to be confiscated
    /// @param to Address of where STO tokens to be sent
    function _confiscate(
        address[] memory from,
        uint[] memory amount,
        address to
    ) internal {
        if(
            from.length != amount.length
        ) revert Errors.LengthsMismatch();

        if (confiscationFeatureDisabled || !confiscation)
            revert Errors.ConfiscationDisabled();
        for (uint256 i = 0; i < from.length;) {
            _transfer(from[i], to, amount[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Method to pause/unpause confiscation feature
    /// @param status whether to pause or unpause the confiscation
    function _changeConfiscation(bool status) internal {
        if (confiscationFeatureDisabled) revert Errors.ConfiscationDisabled();
        confiscation = status;
    }

    /// @dev Method to disable confiscation feature forever
    function _disableConfiscationFeature() internal {
        confiscationFeatureDisabled = true;
        confiscation = false;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
