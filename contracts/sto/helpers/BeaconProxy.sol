// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";
import { StorageSlot } from "@openzeppelin/contracts/utils/StorageSlot.sol";
import { IBeacon } from  "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import { ERC1967Upgrade } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import { Address} from "@openzeppelin/contracts/utils/Address.sol";
import { Errors } from "./Errors.sol";

/**
 * @dev This contract implements a proxy that gets the implementation address for each call from a {UpgradeableBeacon}.
 *
 * The beacon address is stored in storage slot `uint256(keccak256('eip1967.proxy.beacon')) - 1`, so that it doesn't
 * conflict with the storage layout of the implementation behind the proxy.
 *
 * _Available since v3.4._
 */
/// @title BeaconProxy
/// @custom:security-contact tech@brickken.com
contract BeaconProxy is Proxy, ERC1967Upgrade {

    /**
     * @dev Initializes the proxy with `beacon`.
     *
     * If `data` is nonempty, it's used as data in a delegate call to the implementation returned by the beacon. This
     * will typically be an encoded function call, and allows initializating the storage of the proxy like a Solidity
     * constructor.
     *
     * Requirements:
     *
     * - `beacon` must be a contract with the interface {IBeacon}.
     */
    constructor(address beacon, address admin, bytes memory data) payable {
        if(
            beacon == address(0) ||
            admin == address(0)
        ) revert Errors.NotZeroAddress();

        StorageSlot.getAddressSlot(_ADMIN_SLOT).value = admin; // Avoid emitting events
        StorageSlot.getAddressSlot(_BEACON_SLOT).value = beacon; // Avoid emitting events
        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon(beacon).implementation(), data);
        }
    }
    
    /**
     * @dev Returns the current implementation address of the associated beacon.
     */
    function _implementation() internal view override returns (address) {
        if(_getImplementation() != address(0)) return _getImplementation();
        return IBeacon(_getBeacon()).implementation();
    }


    /// Make sure that below functions don't clash with implementation function signatures

    /**
	 * @dev Returns the current beacon address.
	 */
	function getImplementation() external view returns (address) {
		return _implementation();
	}

    /**
	 * @dev Change the current admin.
	 */
    function changeProxyAdmin(address _newAdmin) external {
        require(msg.sender == _getAdmin(), "BeaconProxy: only admin");
        _changeAdmin(_newAdmin);
    }

    /**
	 * @dev Override beacon and set implementation manually, if set to non null value, beacon will be ignored.
	 */
    function changeImplementationOverrideBeacon(address newImplementation) external {
        require(msg.sender == _getAdmin(), "BeaconProxy: only admin");
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
	 * @dev Renounce upgradeability forever, will set implementation to current beacon value and will prohibit from further upgrading it
	 */
    function renounceUpgradeability(address finalImplementation) external {
        require(msg.sender == _getAdmin(), "BeaconProxy: only admin");
        require(finalImplementation != address(0), "BeaconProxy: final implementation is null");
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = finalImplementation;
        _changeAdmin(address(0xdead));
    }
}
