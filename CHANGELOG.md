# v1.2.0

On `STOEscrowUpgradeable` and `DTOEscrowUpgradeable`:
- [FEATURE] Added the possibility to patch ongoing offerings by the default Admin. PR#[80](https://github.com/Brickken/brickken-protocol/pull/80)

On `STOFactoryManagedUpgradeable` and `DTOFactoryManagedUpgradeable`
- [FEATURE] Added possibility to skip BKN fees on newTokenization and usage of new tokenization credits (for API users). PR#[73](https://github.com/Brickken/brickken-protocol/pull/73)
- [FEATURE] Added possibility to use offchain signed permit operations for BKN fee charge. PR#[75](https://github.com/Brickken/brickken-protocol/pull/75)

On `STOEscrowUpgradeable` and `STOTokenUpgradeable`:
- [BUG] Previously, payment token withdrawals were not guaranteed to cover all applicable fees. To address this, we've implemented a proportional fee structure, where fees are paid based on the amount of payment tokens collected. Additionally, we've introduced checks to ensure that the escrow account maintains sufficient balance to cover these fees, providing a more robust and reliable withdrawal process. [PR#76](https://github.com/Brickken/brickken-protocol/pull/76)
- [FEATURE] Add batch operations for token minting (`mintBatch`) and `offchainReporting`. Fixed event emission for `TicketOffered` in order to add the exact amount of payment tokens used and the amount of STO Tokens offered to the user. Fixed `OffchainReport` event and function to add `proofOfPayment` to the transaction.[PR#63](https://github.com/Brickken/brickken-protocol/pull/63)
- [BUG] Previously, offchain reporting didn't validate the whiteslisting of the investor that would be receiving the STO tokens. Now it does. [PR#62](https://github.com/Brickken/brickken-protocol/pull/62)
- [FEATURE] Add `onBehalfOf` feature on `buyToken` / `getTokens` and `claimDividends`. [PR#59](https://github.com/Brickken/brickken-protocol/pull/59)
- [BUG] Previously, offchain reported amount was not taken into account when doing `buyToken`, allowing an investor to exceed `maxTicket`. This has been fixed. [PR#58](https://github.com/Brickken/brickken-protocol/pull/58)
- [BUG] Previously, offchain reporting feature didn't prohibit executing the operation when the offering was already ended. It now prohibits that. [PR#57](https://github.com/Brickken/brickken-protocol/pull/57)

# v1.1.0

On `STOEscrowUpgradeable`:

- Added automated swap with Uniswap v3, it uses a slippage defined by user input.
- Included possibility to set `paymentToken` as non stable. paymentToken price is retrieved and doesn't rely on 1$ anymore. This is enables avoiding de-peg of stables to affect us.
- Use of 15 mins (configurable) TWAP oracle for Chainlink prices and Uniswap v3 TWAP Oracles. This should help us not suffering from price manipulations.
- NEW PARAMETER: `initialize` function takes 2 parameters more, the `paymentTokenOracle` Chainlink's price feed and `paymentTokenOracleUnused` to signal whether the `paymentTokenOracle` is allowed to be zero. For utility -> equity conversion, the address 0 must be used.
- NEW PARAMETER: `buyToken` now needs an estimation of minimal accepted STO tokens.
- NEW PARAMETER: Added `withdrawTo` address to `finalizeIssuance` and `partialWithdraw` if withdrawing the issuer wants to send somewhere else
- NEW PARAMETER: `newOffering` that receives `Issuance` config parameter it has now two more parameters `partialWithdraw` and `paymentTokensCollected` which are 0 at the beginning and those are the last two parameters.
- It lets autocomplete the offer when invested amount < min Ticket, but amount available to be invested < min ticket.
- It lets partial withdraw if soft cap has been reached and issuance still didn't end
- It lets users get their tokens if softcap is reached, but it doesn't let re-invest in same issuance if that happens.
- Make the `getEstimationSTOToken` to not revert and return 0 on bad results.
- Add offchain reporting of offering
- Add access control for (default accounts):

    - DEFAULT_ADMIN_ROLE = grant/revoke roles (brickken)
    - ESCROW_WITHDRAW_ROLE = who can withdraw / partially withdraw to issuer (issuer);
    - ESCROW_NEW_OFFERING_ROLE = starts a new offering (issuer);
    - ESCROW_OFFERING_FINALIZER_ROLE = finalize an offering (brickken, issuer);
    - ESCROW_ERC20WHITELIST_ROLE = add/remove ERC20 from whitelist (brickken, issuer);
    - ESCROW_OFFCHAIN_REPORTER_ROLE = report offchain USD tickets for current offering (issuer)

On `STOTokenUpgradeable`:

- Make `holders` mapping public, to know whether an address is an holder or not without offchain indexing
- Change `maxSupply` to `supplyCap`
- In order to know whether an address is in the whitelist or not now the `hasRole` function should be called with the FACTORY_ISSUER_ROLE role.
- `getMaxAmountToClaim` now returns array of payment tokens, their amounts, and latest block
- `claimDividends` now acceepts an `upTo` parameter to signal up to which index ones want to claim, in case is too gas expensive to claim all at once. By default this can be set to 0 to claim everything.
- `changeConfiscation` now accepts one more parameter `confiscateOnBlacklist` which will be set to true or false whether one wants to automatically confiscate all tokens when blacklisting an already whitelisted user.
- Add access control for (default accounts):

    - DEFAULT_ADMIN_ROLE = grant/revoke roles (brickken)
    - TOKEN_URL_ROLE = change url (brickken,issuer);
    - TOKEN_DIVIDEND_DISTRIBUTOR_ROLE = distribute dividends (issuer);
    - TOKEN_MINTER_ROLE = mint new tokens (issuer, escrow contract);
    - TOKEN_MINTER_ADMIN_ROLE = add/remove minters (issuer);
    - TOKEN_WHITELIST_ADMIN_ROLE = change investors whitelist (issuer);
    - TOKEN_WHITELIST_ROLE = whether the user is whitelisted or not (issuer);
    - TOKEN_CONFISCATE_EXECUTOR_ROLE = execute confiscation (brickken);
    - TOKEN_CONFISCATE_ADMIN_ROLE = pause / unpause or disable confiscation (brickken);

On `BeaconProxy`:

- Make proxies not-upgradeable opt-in, and with admin changeable

On `STOFactory`:

- Add access control for (default accounts):

    - DEFAULT_ADMIN_ROLE = grant/revoke roles (brickken)
    - FACTORY_WHITELISTER_ROLE = allow whitelisting (brickken);
    - FACTORY_ISSUER_ROLE = whitelisted issuers (brickken by default);
    - FACTORY_PAUSER_ROLE = pause / unpause factory (brickken);

- In order to know whether an address is in the whitelist or not now the `hasRole` function should be called with the FACTORY_ISSUER_ROLE role.
- It now uses Uniswap v3 to get BKN price (On Ethereum) or offhchain reported price for other chains
