/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

/// @title Errors
/// @custom:security-contact tech@brickken.com
library Errors {
    /// If a contract has been alredy initialized
    error AlreadyInitialized();

    /// Issuer `issuer` can't start a new Issuance Process if the Previous one has not been Finalized and Withdrawn
    error IssuanceNotFinalized(address issuer);

    /// Issuance start date has not been reached
    error IssuanceNotStarted(address issuer);

    /// Issuance soft cap has not been reached
    error IssuanceNotSuccess(address issuer);

    /// The Initialization of the Issuance Process sent by the Issuer `issuer` is not valid
    error InitialValueWrong(address issuer);

    /// The Patch of the Issuance value sent by the Admin is not valid
    error PatchValueWrong(uint256 oldValue, uint256 newValue);

    /// This transaction exceed the Max Supply of STO Token
    error MaxSupplyExceeded();

    /// This transaction exceed the Supply Cap of STO Token
    error SupplyCapExceeded();

    /// The issuance collected funds are not withdrawn yet
    error IssuanceNotWithdrawn(address issuer);

    /// The issuance process is not in rollback state
    error IssuanceNotInRollback(uint256 index);

    /// Fired when fees are over 100%
    error FeeOverLimits(uint256 newFee);

    /// The Issuer `issuer` tried to Finalize the Issuance Process before to End Date `endDate`
    error IssuanceNotEnded(address issuer, uint256 endDate);

    /// The Issuer `issuer` tried to Withdraw the Issuance Process was Withdrawn
    error IssuanceWasWithdrawn(address issuer);

    /// The Issuer `issuer` tried to Rollback the Issuance Process was Rollbacked
    error IssuanceWasRollbacked(address issuer);

    /// The User `user` tried to buy STO Token in the Issuance Process was ended in `endDate`
    error IssuanceEnded(address user, uint256 endDate);

    /// The User `user` tried to buy with ERC20 `token` is not WhiteListed in the Issuance Process
    error TokenIsNotWhitelisted(address token, address user);

    /// The User `user` tried to buy STO Token, and the Amount `amount` exceed the Maximal Ticket `maxTicket`
    error AmountExceeded(address user, uint256 amount, uint256 maxTicket);

    /// the User `user` tried to buy STO Token, and the Amount `amount` is under the Minimal Ticket `minTicket`
    error InsufficientAmount(address user, uint256 amount, uint256 minTicket);

    /// The value is negative
    error NotNegativeValue(int256 value);

    /// When something is wrong with Uniswap config
    error WrongUniswapConfig();

    /// Slippage control
    error LessThanExpectedAmount(uint256 minExpected, uint256 amount);

    /// The User already redeemed the tokens bought in previous investments
    error TokensAlreadyReedemed(address user);

    /// The User `user` has not enough balance `amount` in the ERC20 Token `token`
    error InsufficientBalance(address user, address token, uint256 amount);

    /// The User `user` tried to redeem the ERC20 Token Again! in the Issuance Process with Index `index`
    error RedeemedAlready(address user, uint256 index);

    /// The User `user` tried to be refunded with payment tokend Again! in the Issuance Process with Index `index`
    error RefundedAlready(address user, uint256 index);

    /// The User `user` is not Investor in the Issuance Process with Index `index`
    error NotInvestor(address user, uint256 index);

    /// The Max Amount of STO Token in the Issuance Process will be Raised
    error HardCapRaised();

    /// User `user`,don't have permission to reinitialize the contract
    error UserIsNotAdmin(address user);

    /// User is not Whitelisted, User `user`,don't have permission to transfer or call some functions
    error UserIsNotWhitelisted(address user);

    /// At least pair of arrays have a different length
    error LengthsMismatch();

    /// The premint Amount of STO Tokens in the Issuance Process exceeds the Max Amount of STO Tokens
    error PremintGreaterThanMaxSupply();

    /// The Address can't be zero address
    error NotZeroAddress();

    /// The Address is not a Contract
    error NotContractAddress();

    /// The Dividend Amount can't be zero
    error DividendAmountIsZero();

    /// The Wallet `claimer` is not Available to Claim Dividend
    error NotAvailableToClaim(address claimer);

    /// The User `claimer` can't claim
    error NotAmountToClaim(address claimer);

    ///The User `user` try to claim an amount `amountToClaim` more than the amount available `amountAvailable`
    error ExceedAmountAvailable(
        address claimer,
        uint256 amountAvailable,
        uint256 amountToClaim
    );

    /// Confiscation Feature is Disabled
    error ConfiscationDisabled();

    // The token is not the payment token
    error InvalidPaymentToken(address token);

    // The deadline for the offchain price has expired
    error ExpiredSignature(uint256 deadline, uint256 currentTimestamp);

    // The retrieved address from ECDSA signature doesn't match allowed signed
    error InvalidSigner(address retrievedAddress, address validAddress);

    // Bad twap interval
    error BadTwapIntervalValue(uint256 value);

    // Null value not accepted
    error NotZeroValue();

    // Offchain amount exceeds available amount
    error OffchainAmountExceedsAvailableAmount(
        uint256 totalAmount,
        uint256 availableAmount
    );

    // Not enough credits
    error NotEnoughCredits();

    /// Fired when fee amount to pay exceeds the available amount in paymentTokens
    error FeeExceedsBalance(uint256 feeAmount, uint256 feeCoverageShortfall);
}
