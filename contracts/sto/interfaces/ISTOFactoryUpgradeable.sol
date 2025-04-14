/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

interface ISTOFactoryUpgradeable {
    /// @dev Struct with tokenization config
    /// @param url URI for offchain records stored in IPFS referring to one specific tokenization
    /// @param name Name of the STOToken
    /// @param symbol Symbol of the STOToken
    /// @param supplyCap Cap on the supply of the STOToken, 0 if unlimited supply (unlimited up to type(uint224).max because of checkpoints feature)
    /// @param paymentToken Token used to denominate issuer's withdraw on succesfull tokenization
    /// @param paymentTokenOracle Chainlink oracle used to retrieve price of paymentToken
    /// @param paymentTokenOracleUnused explicitly set to true whenever paymentTokenOracle is allowed to be zero
    /// @param preMints Amounts of the STOToken to be minted to each initial holder
    /// @param initialHolders Wallets of the initial holders of the STOToken
    struct TokenizationConfig {
        string url;
        string name;
        string symbol;
        uint224 supplyCap;
        address paymentToken;
        address paymentTokenOracle;
        bool    paymentTokenOracleUnused;
        uint256[] preMints;
        address[] initialHolders;
    }

    /// @dev Struct with Offchain Price Reporting config
    /// @param price bkn price sent offchain 
    /// @param deadline Unix timestamp of the price signature expiration
    /// @param nonce nonce of the offchain price reporter address
    /// @param signature Bytes resulting of the offchain report signature
    struct OffchainPriceReport {
        uint256 price;
        uint256 deadline;
        uint256 nonce;
        bytes signature;
    }

    /// @dev Struct with permit signature
    /// @param deadline Unix timestamp of the permit signature expiration
    /// @param signer address of the permit signer
    /// @param spender address of the spender
    /// @param amount amount of the permit signature
    /// @param v v of the permit signature
    /// @param r r of the permit signature
    /// @param s s of the permit signature
    struct PermitStruct {
        uint256 deadline;
        address signer;
        address spender;
        uint256 amount;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @dev Event emitted when a new STO is created
    /// @param id ID of the STO
    /// @param token smart contract address of the STOToken
    /// @param escrow smart contract address of the STOEscrow
    event NewTokenization(
        uint256 indexed id,
        address indexed token,
        address indexed escrow
    );

    /// @dev Event emitted when wallets are changed in the whitelist
    /// @param addresses Addresses of the wallet to modify in the whitelist
    /// @param account account with FACTORY_WHITELISTER_ROLE role that changed the whitelist
    /// @param statuses statuses that indicate if the corresponding address has been either removed or added to the whitelist
    event ChangeWhitelist(
        address[] addresses,
        bool[] statuses,
        address indexed account
    );

    /// @dev Event emitted when price in BKN and/or USD changed
    /// @param newPriceInBKN New price in BKN
    /// @param newPriceInUSD New price in USD
    event ChangeFee(
        uint256 indexed newPriceInBKN,
        uint256 indexed newPriceInUSD
    );

    /// @dev Event emitted when BKN price validity period changed
    /// @param newTWAP the new time window to use
    event BKNPriceTWAPIntervalChanged(uint256 indexed newTWAP);

    /// @dev Event emitted when fees are charged for each new tokenization
    /// @param issuer wallet address of the issuer
    /// @param currency token used to pay the fee, usually BKN
    /// @param amount Amount of fees charged
    event ChargeFee(address indexed issuer, string currency, uint256 amount);

    function pauseFactory() external;

    /// @dev Method to unpause the factory. Only FACTORY_PAUSER_ROLE can call this function.
    function unpauseFactory() external;

    /// @dev Method to deploy a new tokenization (escrow + token). Only users with FACTORY_ISSUER_ROLE can call this function.
    /// @param config Configuration of the token to be deployed
    /// @param priceReport the offchain price report struct if any
    /// @param permit the permit signature struct if any 
    function newTokenization(
        TokenizationConfig calldata config,
        OffchainPriceReport calldata priceReport,
        PermitStruct calldata permit
    ) external;

    /// @dev Method to change the fee price in BKN and USD. Only DEFAULT_ADMIN_ROLE can call this function.
    /// @param newPriceInBKN New price in BKN
    /// @param newPriceInUSD New price in USD
    function changeFee(
        uint256 newPriceInBKN,
        uint256 newPriceInUSD
    ) external;

    /// @dev Method to change the validity period of the BKN price. Only DEFAULT_ADMIN_ROLE can call thgis function.
    /// @param newTWAP the new time window to be used
    function changeBKNPriceTWAPInterval(
        uint256 newTWAP
    ) external;

    /// @dev Method to change configured parameters within the contract. Only DEFAULT_ADMIN_ROLE can call this function.
    /// @param vault this will change where fees are sent
    /// @param beaconToken this will change the beacon token used for new tokenizations
    /// @param beaconEscrow this will change the beacon escrow used for new tokenizations
    /// @param allowedEscrows escrows whose status must be changed in the PriceAndSwapManager
    /// @param allowedEscrowsStatuses statuses to be applied to the above escrows
    function changeConfig(
        address vault,
        address beaconToken,
        address beaconEscrow,
        address[] calldata allowedEscrows,
        bool[] calldata allowedEscrowsStatuses
    ) external;

    /// @dev Method to whitelist or blacklist users from running new tokenizations. Only FACTORY_WHITELISTER_ROLE can call this function.
    /// @param users whose whitelist status must change
    /// @param statuses statuses of above users to be set
    /// @param credits number of credits for new tokenization of above users to be set
    function changeWhitelist(
        address[] calldata users,
        bool[] calldata statuses,
        uint256[] calldata credits
    ) external;

    /// @dev Public method to calculate how many BKN are needed in fees
    /// @param priceReport offchain price report, if any
    /// @return amountToPay number of BKNs to be transferred
    function getFeesInBkn(OffchainPriceReport calldata priceReport) external view returns(uint256 amountToPay);

    /// @dev Get BKN price from liquidity pool
    /// If BKN liquidity is moved somewhere else, this function must be upgraded
    /// Returns 0 if price is too old
    function getBKNPrice() external view returns(uint256);

    /// @dev get the implementation address behind the proxy
    /// @return the implementation address
    function getImplementation() external view returns (address);

    /// @dev get the nonce of the offchain price signer to be used
    /// @param owner the address of the price offchain signer
    /// @return the nonce to be used
    function nonces(address owner) external view returns (uint256);
}