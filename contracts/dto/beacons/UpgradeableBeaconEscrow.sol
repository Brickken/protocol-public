
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
/// @title UpgradeableBeaconEscrow
/// @custom:security-contact tech@brickken.com
contract UpgradeableBeaconEscrow is UpgradeableBeacon {

	// Counter for the number (ID) of DTOs created (DTO Tokens and DTO Escrows)
    uint256 public ids;

    // Mapping of DTO Implementation Token and their respective DTO IDs
    mapping(uint256 id => address implementation) public dtoImplementationEscrow;
    /**
     * @dev Sets the address of the initial implementation, and the deployer account as the owner who can upgrade the
     * beacon.
     */
    constructor(address implementation_) UpgradeableBeacon(implementation_) {
        ++ids;
        dtoImplementationEscrow[ids] = implementation_;
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
        dtoImplementationEscrow[ids] = newImplementation;
        super.upgradeTo(newImplementation);
    }

}
