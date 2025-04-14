/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {DTOFactoryErrors, DTOCommonErrors} from "../helpers/Errors.sol";
import {DTOBeaconProxy, IBeacon} from "../helpers/BeaconProxy.sol";

import {IDTOToken} from "../interfaces/IDTOToken.sol";
import {IPriceAndSwapManager} from "../helpers/PriceAndSwapManager.sol";
import {IDTOFactoryUpgradeable} from "../interfaces/IDTOFactoryUpgradeable.sol";
import {IUniswapV2Pair, IUniswapV3Router} from "../interfaces/UniswapInterfaces.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol";

/// @title DTOFactory
/// @custom:security-contact tech@brickken.com
abstract contract DTOFactoryUpgradeable is
    IDTOFactoryUpgradeable,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using AddressUpgradeable for address;
    using MathUpgradeable for uint256;

    // EIP712 Domain parameters

    // Address of the Offchain Price Report Signer
    address public constant OFFCHAIN_PRICE_SIGNER =
        address(0xB610470ae0fEa78A1B27cD3F0D4011eb5361fAf1);

    bytes32 public constant HASH_NAME = keccak256(bytes("OffchainPriceReport"));
    bytes32 public constant HASH_VERSION = keccak256(bytes("1.0"));

    // TypeHash of EIP712 Domain
    bytes32 private constant _OFFCHAIN_PRICE_REPORT_TYPE_HASH =
        keccak256(
            "OffchainPriceReport(uint256 price,uint256 deadline,uint256 nonce)"
        );
    bytes32 private constant _TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    // Uniswap v3 BKN constants
    address private constant USDT_ADDRESS =
        address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    uint24 private constant UNISWAP_V3_POOL_FEE = uint24(10000); // 1%

    /// Replacing old variables for immutable constants, to save gas.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable priceAndSwapManager;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable bkn;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable router;

    address public brickkenVault; // Brickken Vault Address
    address public dtoBeaconToken; // Beacon Token Address
    address public dtoBeaconEscrow; // Beacon Escrow Address

    uint256 public priceInBKN; // Price of DTO in BKN, this is used as a fixed amount of BKN to pay if priceInUSD is 0
    uint256 public priceInUSD; // Price of DTO in USD, used to calculate how many BKNs are charged based on oracle price
    uint256 public idDTOs; // DTO ID

    // Mapping of DTOTokens and DTOEscrows addresses to their respective DTO IDs
    mapping(uint256 id => address tokenAddress) public dtoTokens;
    mapping(uint256 id => address escrowAddress) public dtoEscrows;
    mapping(address => uint256) private _nonces;

    uint256 public bknPriceTWAPInterval; // Time window used to invalidate the BKN price from the liquidity pool

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @dev constructor to set immutable values
    constructor(address _bkn, address _router, address _priceAndSwapManager) {
        if (_bkn == address(0) || _router == address(0))
            revert DTOCommonErrors.NotZeroAddress();

        bkn = _bkn;
        router = _router;
        priceAndSwapManager = _priceAndSwapManager;
        _disableInitializers();
    }

    /// @dev Public method to calculate how many BKN are needed in fees
    /// @param priceReport the offchain price report struct if any
    /// @return amountToPay number of BKNs to be transferred
    function getFeesInBkn(
        OffchainPriceReport calldata priceReport
    ) public view returns (uint256 amountToPay) {
        /// Always defaults to priceInBKN first
        amountToPay = priceInBKN;

        /// If a fixed fee in dollar is set, it then overwrites it with it
        if (priceInUSD > 0) {
            uint256 priceOfBKNInUSDT = 0;

            if (priceReport.price > 0) {
                // If there's an offchain price reported, use it
                priceOfBKNInUSDT = _validateOffchainSignedPrice(priceReport);
                if (priceOfBKNInUSDT == type(uint256).max) {
                    priceOfBKNInUSDT = 0;
                    amountToPay = 0;
                }
            } else {
                // Otherwise retrieve it from liquidity pool
                priceOfBKNInUSDT = getBKNPrice();
            }

            if (priceOfBKNInUSDT != 0)
                // If a price has been find, then overwrites amountToPay
                amountToPay = priceInUSD.mulDiv(
                    1e18,
                    priceOfBKNInUSDT,
                    MathUpgradeable.Rounding.Up
                );
        }

        return amountToPay;
    }

    /// @dev Get BKN price from liquidity pool
    /// If BKN liquidity is moved somewhere else, this function must be upgraded
    function getBKNPrice() public view returns (uint256) {
        uint256 intermediatePrice = IPriceAndSwapManager(priceAndSwapManager)
            .getPriceInPaymentToken(
                IPriceAndSwapManager.PoolDetails(
                    bkn, // BKN Address, quoted asset
                    USDT_ADDRESS, // USDT Address, base asset
                    IUniswapV3Router(router), // Uniswap v3 router used
                    UNISWAP_V3_POOL_FEE // fees to select the right Uniswap v3 pool
                ),
                bknPriceTWAPInterval
            );

        return intermediatePrice * (1e12); // Uniswap will retrieve price of 1 BKN in USDT, we want price with 18 decimals
    }

    /// @dev get the implementation address behind the proxy
    /// @return the implementation address
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    function nonces(address owner) external view returns (uint256) {
        return _nonces[owner];
    }

    // INTERNAL / PRIVATE FUNCTIONS

    /// @dev Internal method initialize the contract. To be called by a parent contract.
    function __DTOFactory_init() internal {
        bknPriceTWAPInterval = 5 minutes;
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    /// @dev Method to change the fee price in BKN and USD
    /// @param newPriceInBKN New price in BKN
    /// @param newPriceInUSD New price in USD
    function _changeFee(uint256 newPriceInBKN, uint256 newPriceInUSD) internal {
        priceInBKN = newPriceInBKN;
        priceInUSD = newPriceInUSD;
    }

    /// @dev Method to change the TWAP period of the BKN price
    /// @param newTWAP the new time window to be used
    function _changeBKNPriceTWAPInterval(uint256 newTWAP) internal {
        if (newTWAP == 0) revert DTOCommonErrors.NotZeroValue();
        bknPriceTWAPInterval = newTWAP;
    }

    /// @dev Method to change configured parameters within the contract.
    /// @param vault this will change where fees are sent
    /// @param beaconToken this will change the beacon token used for new tokenizations
    /// @param beaconEscrow this will change the beacon escrow used for new tokenizations
    function _changeConfig(
        address vault,
        address beaconToken,
        address beaconEscrow
    ) internal {
        if (
            vault == address(0) ||
            beaconToken == address(0) ||
            beaconEscrow == address(0)
        ) revert DTOCommonErrors.NotZeroAddress();

        brickkenVault = vault;
        dtoBeaconToken = beaconToken;
        dtoBeaconEscrow = beaconEscrow;
    }

    /// @dev Method to deploy a new tokenization (escrow + token)
    /// @param config Configuration of the token to be deployed
    /// @param priceReport the offchain price report struct if any
    /// @param admin Who is going to be the DEFAULT_ADMIN_ROLE account both for escrow and token
    /// @return addresses of escrow and token
    function _newDebtTokenization(
        TokenizationConfig calldata config,
        OffchainPriceReport calldata priceReport,
        PermitStruct calldata permit,
        address admin
    ) internal returns (address, address) {
        address borrower = _msgSender();

        {
            _chargeFee(borrower, priceReport, permit);

            uint256 length = config.preMints.length;

            if (config.initialHolders.length != length)
                revert DTOCommonErrors.LengthsMismatch();

            uint256 totalPremint;

            for (uint256 i = 0; i < length; ) {
                totalPremint += config.preMints[i];
                unchecked {
                    ++i;
                }
            }

            if (config.supplyCap == 0)
                revert DTOFactoryErrors.DebtSupplycapIsZero();

            if (totalPremint > config.supplyCap)
                revert DTOFactoryErrors.PremintGreaterThanMaxSupply();

            // Due to Checkpoints feature, uint224.max is the max supply
            if (totalPremint > type(uint224).max)
                revert DTOCommonErrors.SupplyCapExceeded();

            ++idDTOs;
        }

        dtoTokens[idDTOs] = address(
            new DTOBeaconProxy(
                dtoBeaconToken,
                admin,
                abi.encodeWithSignature(
                    "initialize((string,string,string,uint224,address,address,bool,uint256[],address[],uint24),address,address,uint8)",
                    config,
                    borrower,
                    admin,
                    2
                )
            )
        );

        dtoEscrows[idDTOs] = address(
            new DTOBeaconProxy(
                dtoBeaconEscrow,
                admin,
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,address,address,bool,address,address,uint8)",
                    dtoTokens[idDTOs],
                    borrower,
                    admin,
                    config.paymentToken,
                    router,
                    config.paymentTokenOracle,
                    config.paymentTokenOracleUnused,
                    brickkenVault,
                    priceAndSwapManager,
                    2
                )
            )
        );

        IDTOToken(dtoTokens[idDTOs]).addDTOEscrow(dtoEscrows[idDTOs]);

        IPriceAndSwapManager(priceAndSwapManager).setAllowed(
            dtoEscrows[idDTOs],
            true
        );

        return (dtoTokens[idDTOs], dtoEscrows[idDTOs]);
    }

    /// @dev Internal method to charge the fee in BKN using a fixed USD or BKN price.
    /// @param user address of the borrower
    /// @param priceReport the offchain price report struct if any
    function _chargeFee(
        address user,
        OffchainPriceReport calldata priceReport,
        PermitStruct calldata permit
    ) internal {
        OffchainPriceReport memory indexedPriceReport = priceReport;
        indexedPriceReport.nonce = _useNonce(OFFCHAIN_PRICE_SIGNER); // Todo do not use nonce if there's no price report
        uint256 amountToPay = getFeesInBkn(priceReport);

        /// Finally is there any positive amount of BKN to be transferred, transfer them
        if (amountToPay > 0) {
            if (permit.deadline > 0)
                IERC20PermitUpgradeable(bkn).permit(
                    permit.signer,
                    permit.spender,
                    permit.amount,
                    permit.deadline,
                    permit.v,
                    permit.r,
                    permit.s
                );

            SafeERC20Upgradeable.safeTransferFrom(
                IERC20Upgradeable(bkn),
                user,
                brickkenVault,
                amountToPay
            );
            emit ChargeFee(user, "BKN", amountToPay);
        }
    }

    /// @dev Method to validate the offchain price report
    /// @param priceReport Configuration of the offchain price report
    function _validateOffchainSignedPrice(
        OffchainPriceReport memory priceReport
    ) internal view returns (uint256) {
        if (block.timestamp > priceReport.deadline) {
            revert DTOFactoryErrors.ExpiredSignature(
                priceReport.deadline,
                block.timestamp
            );
        }

        bytes32 structHash = keccak256(
            abi.encode(
                _OFFCHAIN_PRICE_REPORT_TYPE_HASH,
                priceReport.price,
                priceReport.deadline,
                priceReport.nonce
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSAUpgradeable.recover(hash, priceReport.signature);

        if (signer != OFFCHAIN_PRICE_SIGNER) {
            revert DTOFactoryErrors.InvalidSigner(
                signer,
                OFFCHAIN_PRICE_SIGNER
            );
        }

        return priceReport.price;
    }

    /// INTERNAL FUNCTIONS FOR EIP712 DOMAIN

    function _hashTypedDataV4(
        bytes32 structHash
    ) internal view virtual returns (bytes32) {
        return
            ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return _buildDomainSeparator(_TYPE_HASH, HASH_NAME, HASH_VERSION);
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    typeHash,
                    nameHash,
                    versionHash,
                    block.chainid,
                    address(this)
                )
            );
    }

    function _useNonce(address owner) internal returns (uint256) {
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        unchecked {
            // It is important to do x++ and not ++x here.
            return _nonces[owner]++;
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[38] private __gap;
}
