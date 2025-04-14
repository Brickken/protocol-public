/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

/// @title DTO Factory Errors
/// @custom:security-contact tech@brickken.com
library DTOFactoryErrors {
    /// The premint Amount of STO Tokens in the Issuance Process exceeds the Max Amount of STO Tokens
    error PremintGreaterThanMaxSupply();

    ///  The deadline for the offchain price has expired
    error ExpiredSignature(uint256 deadline, uint256 currentTimestamp);

    /// The retrieved address from ECDSA signature doesn't match allowed signed
    error InvalidSigner(address retrievedAddress, address validAddress);

    /// The dto supplycap can't be zero
    error DebtSupplycapIsZero();

    // Not enough credits
    error NotEnoughCredits();
}

/// @title DTO Token Errors
/// @custom:security-contact tech@brickken.com
library DTOTokenErrors {
    /// The Debt Repayment Amount can't be zero
    error DebtRepaymentAmountIsZero();

    /// The User `user` has not enough balance `amount` in the ERC20 Token `token`
    error InsufficientBalance(address user, address token, uint256 amount);

    /// The Wallet `claimer` is not Available to Claim Debt Repay
    error NotAvailableToClaim(address claimer);

    ///The User `user` try to claim an amount `amountToClaim` more than the amount available `amountAvailable`
    error ExceedAmountAvailable(
        address claimer,
        uint256 amountAvailable,
        uint256 amountToClaim
    );

    /// The token is not the payment token
    error InvalidPaymentToken(address token);

    /// Confiscation Feature is Disabled
    error ConfiscationDisabled();

    /// Debt has been repaid
    error DebtRepaid();

    /// Debt repayment not Toggled
    error DebtRepaymentNotToggled();
}

/// @title DTO Escrow Errors
/// @custom:security-contact tech@brickken.com
library DTOEscrowErrors {
    /// Issuance start date has not been reached
    error IssuanceNotStarted(address borrower);

    /// The User `user` tried to buy STO Token in the Issuance Process was ended in `endDate`
    error IssuanceEnded(address user, uint256 endDate);

    /// Issuance soft cap has not been reached
    error IssuanceNotSuccess(address borrower);

    /// The Borrower `borrower` tried to Withdraw the Issuance Process was Withdrawn
    error IssuanceWasWithdrawn(uint256 index);

    /// Offchain amount exceeds available amount
    error OffchainAmountExceedsAvailableAmount(
        uint256 totalAmount,
        uint256 availableAmount
    );

    /// The User already redeemed the tokens bought in previous investments
    error TokensAlreadyReedemed(address user);

    /// Fired when fees are over 100%
    error FeeOverLimits(uint256 newFee);

    /// Borrower `borrower` can't start a new Issuance Process if the Previous one has not been Finalized and Withdrawn
    error IssuanceNotFinalized(address borrower);

    /// The Initialization of the Issuance Process sent by the Borrower `borrower` is not valid
    error InitialValueWrong(address borrower);

    /// The Patch of the Issuance value sent by the admin is not valid
    error PatchValueWrong(uint256 oldValue, uint256 newValue);

    /// This transaction exceed the Max Supply of STO Token
    error MaxSupplyExceeded();

    /// The Borrower `borrower` tried to Finalize the Issuance Process before to End Date `endDate`
    error IssuanceNotEnded(address borrower, uint256 endDate);

    /// The User `user` tried to buy with ERC20 `token` is not WhiteListed in the Issuance Process
    error TokenIsNotWhitelisted(address token, address user);

    /// The Max Amount of STO Token in the Issuance Process will be Raised
    error HardCapRaised();

    /// the User `user` tried to buy STO Token, and the Amount `amount` is under the Minimal Ticket `minTicket`
    error InsufficientAmount(address user, uint256 amount, uint256 minTicket);

    /// The User `user` tried to buy STO Token, and the Amount `amount` exceed the Maximal Ticket `maxTicket`
    error AmountExceeded(address user, uint256 amount, uint256 maxTicket);

    /// The User `user` tried to redeem the ERC20 Token Again! in the Issuance Process with Index `index`
    error RedeemedAlready(address user, uint256 index);

    /// The User `user` is not Lender in the Issuance Process with Index `index`
    error NotLender(address user, uint256 index);

    /// The User `user` tried to be refunded with payment tokend Again! in the Issuance Process with Index `index`
    error RefundedAlready(address user, uint256 index);

    /// The issuance process is not in rollback state
    error IssuanceNotInRollback(uint256 index);

    /// The Borrower `borrower` tried to Rollback the Issuance Process was Rollbacked
    error IssuanceWasRollbacked(uint256 index);

    /// The issuance collected funds are not withdrawn yet
    error IssuanceNotWithdrawn(uint256 index);

    /// Fired when fee amount to pay exceeds the available amount in paymentTokens
    error FeeExceedsBalance(uint256 feeAmount, uint256 feeCoverageShortfall);
}

/// @title DTO UniSwap Errors
/// @custom:security-contact tech@brickken.com
library DTOUniSwapErrors {
    /// Bad twap interval
    error BadTwapIntervalValue(uint256 value);

    /// When something is wrong with Uniswap config
    error WrongUniswapConfig();
}

/// @title DTO Commmon Errors
/// @custom:security-contact tech@brickken.com
library DTOCommonErrors {
    /// At least pair of arrays have a different length
    error LengthsMismatch();

    /// This transaction exceed the Supply Cap of STO Token
    error SupplyCapExceeded();

    /// The Address can't be zero address
    error NotZeroAddress();

    /// The Address is not a Contract
    error NotContractAddress();

    /// User `user`,don't have permission to reinitialize the contract
    error UserIsNotAdmin(address user);

    /// User is not Whitelisted, User `user`,don't have permission to transfer or call some functions
    error UserIsNotWhitelisted(address user);

    /// The value is negative
    error NotNegativeValue(int256 value);

    /// Null value not accepted
    error NotZeroValue();

    /// Fired when dent interest rate is over 100%
    error InterestRateOverLimits(uint256 newFee);
}
