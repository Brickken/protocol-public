/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DTOUSDTMock
/// @custom:security-contact tech@brickken.com
contract DTOUSDTMock is Ownable, ERC20 {
    constructor() ERC20("DTO Fake USDT", "USDT") {}

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
