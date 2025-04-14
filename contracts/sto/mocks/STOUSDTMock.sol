/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title STOUSDTMock
/// @custom:security-contact tech@brickken.com
contract STOUSDTMock is Ownable, ERC20 {

    constructor() ERC20("STO Fake USDT", "USDT") {
    }

    function issue(uint256 amount) public onlyOwner() {
		_mint(owner(), amount);
	}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
