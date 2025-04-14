/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

/// Import all OZ intefaces from which it extends
/// Add custom functions

/// @title IDTOEscrow
/// @custom:security-contact tech@brickken.com
interface IDTOEscrow {
    /// @dev An issuance can be ACTIVE, WITHDRAWN (The issuance was successful and the borrower withdrawn),
    /// ROLLBACK (The issuance was not successful and the borrower has finalized it)
    enum IssuanceStatuses {
        ACTIVE,
        WITHDRAWN,
        ROLLBACK
    }

    /// @dev Issuance struct
    /// @param status Issuance status based on previous enum
    /// @param minTicket Min amount in USD (18 decimals) for issuance participation
    /// @param maxTicket Max amount in USD (18 decimals) for issuance participation
    /// @param startDate Unix timestamp of when the issuance will start
    /// @param endDate Unix timestamp of when the issuance will end
    /// @param hardCap Amount in USD (18 decimals) that can be collected at most
    /// @param softCap Amount in USD (18 decimals) that must be collected at least for an issuance to be succesfull
    /// @param raisedAmount Amount in USD (18 decimals) raised in the issuance so far
    /// @param issuanceAmount Amount of DTO tokens issued
    /// @param priceInUSD Price in USD (18 decimals) of each DTO token unit -> hardCap / issuanceAmount
    /// @param partialWithdraw Amount of paymentToken that has been already partially withdrawn (only if soft cap has been reached)
    /// @param paymentTokensCollected Amount of payment tokens that have been escrowed so far
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

    /// @dev Struct to whitelist a new ERC20 token
    /// @param status status to enable or disable the token
    /// @param multiplier Multiplier of ERC20 token (1 ether = 1e18 by default, otherwise specified)
    /// @param fees Fees of the pool to select (Uniswap might have different pools of same pairs with different fees)
    struct ERC20Token {
        bool status;
        uint256 multiplier;
        uint24 fees;
    }

    /// @dev Borrower struct
    /// @param redeemed whether the user has redeemed the DTO tokens or not
    /// @param refunded whether the user has been refunded or not
    /// @param amountInPaymentToken Amount of paymentToken used to buy DTO tokens in the issuance
    /// @param amountInDTO Amount of DTO tokens estimated in this issuance
    struct Borrower {
        bool redeemed;
        bool refunded;
        uint256 amountInPaymentToken;
        uint256 amountInDTO;
    }

    /// Events

    /// @dev Event to signal that a new offering has been created
    /// @param issuanceIndex index of the new issuance
    /// @param issuance Initial struct of the new issuance
    event NewOffering(uint256 indexed issuanceIndex, Issuance issuance);

    /// @dev Event to signal that the list of whitelisted ERC20 tokens has changed
    /// @param borrower Borrower address
    /// @param token Array of ERC20 tokens where whitelist changed
    /// @param multiplier Array of multipliers applied to each ERC20 token
    /// @param status Array of statuses applied to each ERC20 token
    event ERC20Whitelisted(
        address indexed borrower,
        address[] token,
        uint256[] multiplier,
        bool[] status
    );

    /// @dev Event to signal that an user redeemed his tokens
    /// @param borrower User address
    /// @param issuanceIndex Index of the issuance
    /// @param amountInDTO Amount of DTO token redeemed
    event Redeemed(
        address indexed borrower,
        uint256 indexed issuanceIndex,
        uint256 indexed amountInDTO
    );

    /// @dev Event to signal that an user has been refunded
    /// @param borrower User address
    /// @param issuanceIndex Index of the issuance
    /// @param amountInPaymentToken Amount of payment Token equivalent to the user investment that has been refunded
    event Refunded(
        address indexed borrower,
        uint256 indexed issuanceIndex,
        uint256 indexed amountInPaymentToken
    );

    /// @dev Event to signal that an user made an offer to buy DTO tokens
    /// @param borrower User address
    /// @param ERC20Token ERC20 token used by the user
    /// @param issuanceIndex Index of the issuance
    /// @param amountInPaymentToken Amount of payment Token offered by the user
    event TicketOffered(
        address indexed borrower,
        address indexed ERC20Token,
        uint256 indexed issuanceIndex,
        uint256 amountInPaymentToken
    );

    /// @dev Event to signal that the borrower has withdrawn all the funds collected in the issuance
    /// @param borrower Borrower address
    /// @param issuanceIndex Index of the issuance
    /// @param fee Brickken success fee (amount of paymentToken)
    /// @param amountInPaymentToken Amount of payment Token raised in the issuance
    event Withdrawn(
        address indexed borrower,
        uint256 indexed issuanceIndex,
        uint256 fee,
        uint256 indexed amountInPaymentToken
    );

    /// @dev Event to signal that an issuance has entered into rollback state, funds will be refunded
    /// @param borrower Borrower address
    /// @param issuanceIndex Index of the issuance
    /// @param amountInPaymentToken Amount of payment Token raised during the issuance
    event RollBack(
        address indexed borrower,
        uint256 indexed issuanceIndex,
        uint256 indexed amountInPaymentToken
    );

    /// @dev Event to signal that the borrower has changed
    /// @param borrower New borrower address
    event ChangeBorrower(address indexed borrower);

    /// @dev Event to signal that the paymentToken change
    /// @param newPaymentTokenAddress paymentToken address
    /// @param newPaymentTokenOracle paymentTokenOracle address
    event ChangePaymentToken(
        address indexed newPaymentTokenAddress,
        address indexed newPaymentTokenOracle
    );

    /// @dev Event to signal that the router changed address
    /// @param newRouterAddress New router address
    event ChangeRouterAddress(address indexed newRouterAddress);

    /// @dev Event to signal that the success fee has changed, (from 1 to 10000, equivalent to 0.01% to 100%)
    /// @param oldFee Old fee percentage
    /// @param newFee New fee percentage
    event ChangeWithdrawalFee(uint256 indexed oldFee, uint256 indexed newFee);

    /// @dev Event to signal that the treasury address has changed
    /// @param oldTreasuryAddress Old treasury address
    /// @param newTreasuryAddress New treasury address
    event ChangeTreasuryAddress(
        address indexed oldTreasuryAddress,
        address indexed newTreasuryAddress
    );

    /// @dev Event emitted when buying tokens if the amount of USD value provided exceeds the hardcap
    /// @dev in these circumstances, only a partial amount of paymentTokens are used, the difference is sent back to the user
    /// @param partialTicket amount of DTO tokens actually bought
    /// @param refund amount of paymentToken sent back to the user
    event PartialTicketBought(
        uint256 indexed partialTicket,
        uint256 indexed refund
    );

    /// @dev Method for Change de Borrower of the Contract
    /// @param _newBorrower is the new Borrower of the Contract
    function changeBorrower(address _newBorrower) external;

    /// @dev Method to Add an New Offering to the Issuance Process and Verify all previews process were finalized
    /// @param _issuance Struct with all the data of the new Issuance Process
    function newOffering(Issuance memory _issuance) external;

    /// @dev Method for Whitelisting an ERC20 Smart Contract to the Issuance Process
    /// @param _tokenERC20 is the ERC20 Smart Contract to be Whitelisted
    /// @param _multiplier is the Multiplier of the Token ERC20 Whitelisted
    function addWhitelist(address _tokenERC20, uint256 _multiplier) external;

    /// @dev Method to Finalized the Issuance Process
    /// @dev Only the Borrower can Finalize the Issuance Process
    function finalizedIssuance() external;

    /// @dev Method for the Borrower to Redeem the DTO Token Buyed or Refund USDC Offer in the Issuance Process
    function getTokens() external;

    /// @dev Method to Offer a Ticket to the Issuance Process
    /// @param _tokenERC20 ERC20 Token to be used to buy the Tickets
    /// @param _amount Amount of Tickets to Offer in USDC expressed in Ethers (1e18)
    function buyToken(address _tokenERC20, uint256 _amount) external;

    /// @dev Method to partially withdraw `amount` of `paymentToken`
    /// @dev this can be done only by the borrower and only if the soft cap has been reached
    /// @dev the withdrawn amount will be reflected once the offering is finalized
    /// @dev Only the borrower or the owner can finalize it
    function partialWithdraw(uint256 amount) external;

    /// Helpers for the Issuance Process

    /// @dev Method for Validate if the Token ERC20 is Whitelisted in the Issuance Process
    /// @param _tokenERC20 is the ERC20 Smart Contract to be Validated
    function isWhitelisted(address _tokenERC20) external view returns (bool);

    /// @dev Method To Validate if the Issuance Process is Finalized
    /// @param _issuanceIndex Index of the Issuance Process
    /// @return True if the Issuance Process is Finalized
    function isFinalized(uint256 _issuanceIndex) external view returns (bool);

    /// @dev Method to get the Index of the Issuance Process
    /// @return Index of the Issuance Process
    function issuanceIndex() external view returns (uint256);

    /// @dev Method to get the Issaunce data
    /// @return Issuance of the Issuance
    function issuances(uint index) external view returns (Issuance memory);

    /// @dev Method To Validate if the Issuance Process is Started
    /// @param _issuanceIndex Index of the Issuance Process
    /// @return True if the Issuance Process is Started
    function isStarted(uint256 _issuanceIndex) external view returns (bool);

    /// @dev Method To Validate if the Issuance Process is Ended
    /// @param _issuanceIndex Index of the Issuance Process
    /// @return True if the Issuance Process is Ended
    function isEnded(uint256 _issuanceIndex) external view returns (bool);

    /// @dev Method To Validate if the Issuance Process is Active
    /// @param _issuanceIndex Index of the Issuance Process
    /// @return True if the Issuance Process is Active
    function isActive(uint256 _issuanceIndex) external view returns (bool);

    /// @dev Method to validate if the Issuance Process was Successful
    /// @param _issuanceIndex Index of the Issuance Process
    /// @return True if the Issuance Process was Successful
    function isSuccess(uint256 _issuanceIndex) external view returns (bool);

    /// @dev Method To Validate if the Issuance Process was Successfully Withdrawn
    /// @param _issuanceIndex Index of the Issuance Process
    /// @return True if the Issuance Process  was Successfully Withdrawn
    function isWithdrawn(uint256 _issuanceIndex) external view returns (bool);

    /// @dev Method To Validate if the User redeem or refund your DTO Token or USDC Equivalent
    /// @param _issuanceIndex Index of the Issuance Process
    /// @param _user Address of the User/Borrower
    /// @return True if the User redeem or refund your DTO Token or USDC Equivalent Successfully
    function isRedeemed(
        uint256 _issuanceIndex,
        address _user
    ) external view returns (bool);

    /// @dev Method To Validate if the User is a Borrower in the Issuance Process
    /// @param _issuanceIndex Index of the Issuance Process
    /// @param _user Address of the User/Borrower
    /// @return True if the User have invested in the Issuance Process
    function isBorrower(
        uint256 _issuanceIndex,
        address _user
    ) external view returns (bool);

    /// @dev Method To Validate if the Avaliable Amount per Borrower in the Issuance Process
    /// @dev is equal or less to the Max Ticket permit per Borrower in the Issuance Process
    function amountAvailable(
        uint256 _issuanceIndex
    ) external view returns (uint256);

    /// @dev Method to getting the token Whitelisted
    /// @return result Array of whitelisted ERC20 tokens
    function getAllTokenERC20Whitelist()
        external
        view
        returns (address[] memory result);

    /// @dev Method to estimate how many DTO tokens are received based on amountOfTokens of tokenUsed
    /// @param tokenUsed Address of the ERC20 token used
    /// @param amountOfTokens Amount of tokenUsed tokens
    /// @return expectedAmount Amount of DTO tokens expected to be received
    function getEstimationDTOToken(
        address tokenUsed,
        uint256 amountOfTokens
    ) external view returns (uint256 expectedAmount);

    // @dev Method to get the price of 1 token of tokenAddress if swapped for paymentToken
    /// @param tokenAddress ERC20 token address of a whitelisted ERC20 token
    /// @return price Price in payment Token equivalent with its decimals
    function getPriceInPaymentToken(
        address tokenAddress
    ) external view returns (uint256 price);

    /// @dev Method to get the price of 1 token of paymentToken in USD price
    /// @return price Price in USD of 1 paymentToken unit, scaled to 18 decimals
    function getUSDPriceOfPaymentToken() external view returns (uint256);
}
