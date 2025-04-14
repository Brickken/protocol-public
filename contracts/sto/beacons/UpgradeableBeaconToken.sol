// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { UpgradeableBeacon, IBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @dev This contract implements a proxy that gets the implementation address for each call from a {UpgradeableBeacon}.
 *
 * The beacon address is stored in storage slot `uint256(keccak256('eip1967.proxy.beacon')) - 1`, so that it doesn't
 * conflict with the storage layout of the implementation behind the proxy.
 *
 * _Available since v3.4._
 */
/// @title UpgradeableBeaconToken
/// @custom:security-contact tech@brickken.com
contract UpgradeableBeaconToken is UpgradeableBeacon {

	// Counter for the number (ID) of STOs created (STO Tokens and STO Escrows)
    uint256 public ids;

    // Mapping of STO Implementation Token and their respective STO IDs public stoImplementationToken;
    mapping(uint256 id => address implementation) public stoImplementationTokens;
    /**
     * @dev Sets the address of the initial implementation, and the deployer account as the owner who can upgrade the
     * beacon.
     */
    constructor(address implementation_) UpgradeableBeacon(implementation_) {
        ++ids;
        stoImplementationTokens[ids] = implementation_;
    }

	/**
     * @dev Upgrades the beacon to a new implementation.
     *
     * Emits an {Upgraded} event.
     *
     * Requirements:
     *
     * - msg.sender must be the owner of the contract.
     * - `newImplementation` must be a contract.
     */
    function upgradeTo(address newImplementation) public override onlyOwner {
        ++ids;
        stoImplementationTokens[ids] = newImplementation;
        super.upgradeTo(newImplementation);
    }

}
