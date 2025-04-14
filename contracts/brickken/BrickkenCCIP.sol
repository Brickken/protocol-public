// SPDX-License-Identifier: MIT
// https://github.com/Brickken/license/blob/main/README.md
pragma solidity <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract Brickken is ERC20, AccessControl, ERC20Permit {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(
        address _issuer
    ) ERC20("Brickken", "BKN") ERC20Permit("Brickken") {
        _grantRole(DEFAULT_ADMIN_ROLE, _issuer);
        _grantRole(MINTER_ROLE, _issuer);
        _grantRole(BURNER_ROLE, _issuer);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Mint `amount` tokens to the `to` address.
     *
     * See {ERC20-_mint}.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        super._mint(to, amount);
    }
}
