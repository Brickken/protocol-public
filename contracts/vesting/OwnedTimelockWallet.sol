// SPDX-License-Identifier: MIT
// https://github.com/Brickken/license/blob/main/README.md
pragma solidity <0.9.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OwnedTimelockWallet is Ownable, ReentrancyGuard {
    address private _beneficiary;
    uint256 private _end;

    event TokensReleased(address indexed token, uint256 indexed amount);
    event BeneficiarySet(address indexed newBeneficiary, address indexed oldBeneficiary);
    event NewEndSet(uint256 indexed newValue, uint256 indexed oldValue);

    modifier onlyBeneficiary() {
        require(beneficiary() == _msgSender(), "Access restricted to beneficiary");
        _;
    }

    modifier afterEnd() {
        require(block.timestamp > end(), "It didn't end yet");
        _;
    }

    constructor(
        address beneficiary_,
        uint256 end_
    ) {
        require(beneficiary_ != address(0x0), "Beneficiary is zero address");
        require(end_ >= block.timestamp, "Can't set end in the past");

        _end = end_;
        _beneficiary = beneficiary_;

        emit BeneficiarySet(_beneficiary, address(0));
    }

    function beneficiary() public view virtual returns (address) {
        return _beneficiary;
    }

    function end() public view virtual returns (uint256) {
        return _end;
    }

    /**
    * @dev Release the tokens to beneficiary.
    */
    function release(address token) external nonReentrant() afterEnd() {
        uint256 balance = IERC20(token).balanceOf(address(this));
        emit TokensReleased(token, balance);
        SafeERC20.safeTransfer(IERC20(token), beneficiary(), balance);
    }

    function setBeneficiary(address recipient_) external onlyOwner() {
        require(recipient_ != address(0), "Can't set it to the zero address");
        emit BeneficiarySet(recipient_, _beneficiary);
        _beneficiary = recipient_;
    }

    function changeEnd(uint256 newEnd_) external onlyOwner() {
        require(newEnd_ > block.timestamp, "Can't set it to the past");
        emit NewEndSet(newEnd_, _end);
        _end = newEnd_;
    }

    function emergencyWithdraw(address token) external nonReentrant() onlyOwner() {
        uint256 balance = IERC20(token).balanceOf(address(this));
        emit TokensReleased(token, balance);
        SafeERC20.safeTransfer(IERC20(token), owner(), balance);
    }
}