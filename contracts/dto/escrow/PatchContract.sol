/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { IDTOToken } from "../interfaces/IDTOToken.sol";
import { IPriceAndSwapManager } from "../helpers/PriceAndSwapManager.sol";
import { IChainlinkPriceFeed} from "../interfaces/ChainlinkInterfaces.sol";
import { IUniswapV3Router } from "../interfaces/UniswapInterfaces.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract PatchContract {

    enum IssuanceStatuses {
        ACTIVE,
        WITHDRAWN,
        ROLLBACK
    }

    struct Issuance {
        IssuanceStatuses status;
        uint256 minTicket;
        uint256 maxTicket;
        uint256 startDate;
        uint256 endDate;
        uint256 hardCap;
        uint256 softCap;
        uint256 raisedAmount;
        uint256 issuanceAmount;
        uint256 priceInUSD;
        uint256 partialWithdraw;
        uint256 paymentTokensCollected;
    }

    struct ERC20Token {
        bool status;
        uint24 fees;
    }

    struct Lender {
        bool redeemed;
        bool refunded;
        uint256 amountInPaymentToken;
        uint256 amountInDTO;
    }

    uint8 private _initialized;
    bool private _initializing;
    uint256[50] private __gap1;
    address private _owner;
    uint256[49] private __gap2;
    uint256 private _status;
    uint256[49] private __gap3;

    IDTOToken private dtoRelatedToken;
    IERC20MetadataUpgradeable private paymentToken;
    IUniswapV3Router private router;
    address private borrower;
    address private treasuryAddress;
    address[] private tokensERC20;
    uint256 private withdrawalFee;
    uint256 private issuanceIndex;
    uint256 private constant MAX_FEE_LIMIT = 1e4;
    mapping(address tokenAddress => ERC20Token config) private tokenERC20Whitelist;
    mapping(uint256 index => Issuance info) private issuances;
    mapping(uint256 issuanceIndex => mapping(address lenderAddress => Lender info)) private lenders;
    IChainlinkPriceFeed private paymentTokenOracle;
    uint256 private twapInterval;
    IPriceAndSwapManager private priceAndSwapManager;
    mapping(uint256 issuanceIndex => address paymentTokenForRefund) private paymentTokensToRefund;

    uint256[35] private __gap;

    function patch(
        uint256 modifyIndex, 
        uint256 newStart, 
        uint256 newEnd, 
        uint256 newSoftCap, 
        uint256 newHardCap, 
        uint256 newMinTicket, 
        uint256 newMaxTicket
    ) external {
        Issuance storage issuanceToModify = issuances[modifyIndex];
        if(newStart != issuanceToModify.startDate) issuanceToModify.startDate = newStart;
        if(newEnd != issuanceToModify.endDate) issuanceToModify.endDate = newEnd; 
        if(newSoftCap != issuanceToModify.softCap) issuanceToModify.softCap = newSoftCap; 
        if(newHardCap != issuanceToModify.hardCap) issuanceToModify.hardCap = newHardCap; 
        if(newMinTicket != issuanceToModify.minTicket) issuanceToModify.minTicket = newMinTicket; 
        if(newMaxTicket != issuanceToModify.maxTicket) issuanceToModify.maxTicket = newMaxTicket; 
    }
}
