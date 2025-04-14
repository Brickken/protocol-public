/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
interface IDTOToken is IERC20MetadataUpgradeable {
    function addMinter(address newMinter) external;
    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);
    function renounceRole(bytes32 role, address account) external;
    function mint(address to, uint256 amount) external;
    function mintBatch(
        address[] calldata _addresess,
        uint256[] calldata _amounts
    ) external;
    function supplyCap() external view returns (uint224);
    function toggleDebtRepayment(bool _status) external;
    function addDebtRepayToggler(address newToggler) external;
    function removeDebtRepayToggler(address oldToggler) external;
    function burn(uint256 amount) external;
    function addDTOEscrow(address dtoEscrowAddress) external;
}
