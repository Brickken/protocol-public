// SPDX-License-Identifier: MIT

pragma solidity <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPriceOracleGetter {
  function getAssetPrice(address asset) external view returns (uint256);
}

contract Escrow is Ownable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    event BoughtOffline(address indexed recipient, uint256 indexed amount);
    event ERC20Deposited(address indexed payee, address indexed token, uint256 indexed amount);
    event ERC20Withdrawn(address indexed payee, address indexed token, uint256 indexed amount);
    event Deposited(address indexed payee, uint256 indexed weiAmount);
    event Withdrawn(address indexed payee, uint256 indexed weiAmount);
    
    mapping(address => bool) public whitelistedTokens;
    mapping(address => uint256) public conversionRates;

    address public offlineSpender;
    uint256 public pricePerUnitInUSD;
    uint256 public lastRecordedPrice;
    uint256 public minimumTicket;
    uint256 public constant ONE = 10**18;
    bool public paused;
    
    IERC20 public wbkn;
    IPriceOracleGetter public ethUSDCFeed;

    modifier onlySpender {
        require(msg.sender == offlineSpender, "Caller is not spender");
        _;
    }
    
    modifier whenNotPaused {
        require(!paused, "Functionality is paused");
        _;
    }
    
    constructor(
        address _wbkn,
        address _offlineSpender,
        uint256 _pricePerUnitInUsd,
        uint256 _minimumTicket,
        address _priceOracleGetter,
        address[] memory _whitelistedTokens,
        uint256[] memory _conversionRates
    ) {
        require(_whitelistedTokens.length == _conversionRates.length, "Lengths mismatch");
        require(_wbkn != address(0), "Invalid WBKN address");

        pricePerUnitInUSD = _pricePerUnitInUsd;        
        wbkn = IERC20(_wbkn);
        minimumTicket = _minimumTicket;
        offlineSpender = _offlineSpender;
        ethUSDCFeed = IPriceOracleGetter(_priceOracleGetter);
        lastRecordedPrice = ethUSDCFeed.getAssetPrice(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        
        for(uint8 i = 0; i<_whitelistedTokens.length; i++) {
            whitelistedTokens[_whitelistedTokens[i]] = true;
            conversionRates[_whitelistedTokens[i]] =_conversionRates[i];
        }
    }
    
    function pause(bool _pause) public onlyOwner {
        paused = _pause;
    }
    
    function configERC20(address token, uint256 conversionRate) public onlyOwner {
        if(conversionRate != 0) {
            if(!whitelistedTokens[token]) whitelistedTokens[token] = true;
        } else {
            if(whitelistedTokens[token]) whitelistedTokens[token] = false;
        }
        
        if(conversionRate != conversionRates[token]) conversionRates[token] = conversionRate;
    }
    
    function configUSDPrice(uint256 newValue) public onlyOwner {
        pricePerUnitInUSD = newValue;
    }

    function configMinimumTicket(uint256 newValue) public onlyOwner {
        minimumTicket = newValue;
    }
    
    function buyOffline(uint256 amountBought, address recipient) public onlySpender {
        require(amountBought <= wbkn.balanceOf(address(this)), "Amount exceeds contract's reserve");
        require(amountBought >= minimumTicket, "Minimum ticket not satisfied");

        wbkn.safeTransfer(recipient, amountBought);
        
        emit BoughtOffline(recipient, amountBought);
    }
    
    function buyWithERC20(address token, uint256 amount) public whenNotPaused {
        require(whitelistedTokens[token], "This address is not whitelisted");
        require(conversionRates[token] > 0, "Invalid conversion rate");
        require(amount > 0, "Zero amount not allowed");
        require(IERC20(token).allowance(msg.sender, address(this)) >= amount, "Contract has not enough allowance");
        
        uint256 amountBought = amount * conversionRates[token];
        require(amountBought >= minimumTicket, "Minimum ticket not satisfied");
        require(amountBought <= wbkn.balanceOf(address(this)), "Amount exceeds contract's reserve");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        wbkn.safeTransfer(msg.sender, amountBought);

        emit ERC20Deposited(msg.sender, token, amount);
    }

    function buyWithETH() public payable whenNotPaused {
        uint256 amount = msg.value;
        require(amount > 0, "Zero amount not allowed");

        lastRecordedPrice = ethUSDCFeed.getAssetPrice(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        
        uint256 amountInUSD = amount*ONE / lastRecordedPrice;
        uint256 amountBought = amountInUSD*ONE / pricePerUnitInUSD;

        require(amountBought >= minimumTicket, "Minimum ticket not satisfied");
        require(amountBought <= wbkn.balanceOf(address(this)), "Amount exceeds contract's reserve");
        
        wbkn.safeTransfer(msg.sender, amountBought);
        
        emit Deposited(msg.sender, amountInUSD);
    }

    function withdrawETH(address payable recipient) public onlyOwner {
        emit Withdrawn(recipient, address(this).balance);
        recipient.sendValue(address(this).balance);
    }
    
    function withdrawERC20(address token, address recipient) public onlyOwner {

        IERC20(token).safeTransfer(recipient, IERC20(token).balanceOf(address(this)));

        emit ERC20Withdrawn(recipient, token, IERC20(token).balanceOf(address(this)));
    }
}