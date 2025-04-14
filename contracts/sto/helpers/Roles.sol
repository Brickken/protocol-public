// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

library Roles {

    // DEFAULT_ADMIN_ROLE = grant/revoke roles (brickken)
    //
    // This role operated by brickken can grant/revoke any role in the system. Specifically it
    // can also perform some special actions. Brickken operates through Gnosis Safe multisig for every
    // operation.
    //
    // On the escrow:
    //
    // - change issuer, if issuer wallet gets compromised
    // - change payment token, if issuer desires to change the asset used in the offering
    // - change router, if unexpected circumstances forces us to change Uniswap v3 router
    // - change price and swap manager, if unexpected circumstances forces us to change the contract logic
    // - change treasury address, if brickken wants to change where success fees are sent
    //  
    // Other roles description:
    //
    // - DEFAULT_ADMIN_ROLE = grant/revoke roles (brickken)
    // - ESCROW_WITHDRAW_ROLE = who can withdraw / partially withdraw to issuer (issuer);
    // - ESCROW_NEW_OFFERING_ROLE = starts a new offering (issuer);
    // - ESCROW_OFFERING_FINALIZER_ROLE = finalize an offering (brickken, issuer);
    // - ESCROW_ERC20WHITELIST_ROLE = add/remove ERC20 from whitelist (brickken, issuer);
    // - ESCROW_OFFCHAIN_REPORTER_ROLE = report offchain USD tickets for current offering (issuer)
    //
    // On the token:
    //
    // - change issuer, if issuer wallet gets compromised
    // - change payment token, if issuer desires to change the asset used to distribute dividends 
    // - change max supply, if there are extensions in the STO equities amount, this will conflict if max supply has been already minted
    // 
    // Other roles description:
    //
    // - DEFAULT_ADMIN_ROLE = grant/revoke roles (brickken)
    // - TOKEN_URL_ROLE = change url (brickken,issuer);
    // - TOKEN_DIVIDEND_DISTRIBUTOR_ROLE = distribute dividends (issuer);
    // - TOKEN_MINTER_ROLE = mint new tokens (issuer, escrow contract);
    // - TOKEN_MINTER_ADMIN_ROLE = add/remove minters (issuer);
    // - TOKEN_WHITELIST_ADMIN_ROLE = change investors whitelist (issuer);
    // - TOKEN_WHITELIST_ROLE = whether the user is whitelisted or not (issuer);
    // - TOKEN_CONFISCATE_EXECUTOR_ROLE = execute confiscation (brickken);
    // - TOKEN_CONFISCATE_ADMIN_ROLE = pause / unpause or disable confiscation (brickken);
    // 
    // On the factory:
    //
    // Brickken is the owner and sole operator of the factory so it has full permissions on it
    //
    // Other roles description:
    //
    // - DEFAULT_ADMIN_ROLE = grant/revoke roles (brickken)
    // - FACTORY_WHITELISTER_ROLE = allow whitelisting (brickken);
    // - FACTORY_ISSUER_ROLE = whitelisted issuers (brickken by default);
    // - FACTORY_PAUSER_ROLE = pause / unpause factory (brickken);

    // 0x914095fa3ba2bffbd4003cbfb530f542f1b7f4f99ba858dc177f6f248873b68a
    bytes32 public constant FACTORY_PAUSER_ROLE = keccak256(abi.encode("FACTORY_PAUSER_ROLE")); // pause / unpause factory (brickken);
    // 0xb5d21eff2c2f647e4477e7d244cafd46ce3b64315da3959820bcde6fb735839e
    bytes32 public constant FACTORY_ISSUER_ROLE = keccak256(abi.encode("FACTORY_ISSUER_ROLE")); // whitelisted issuers (brickken by default);
    // 0x86f9504d4f12a701ad18b53caa9c998d6c94b96c565c67e086b4b64963391c15
    bytes32 public constant FACTORY_WHITELISTER_ROLE = keccak256(abi.encode("FACTORY_WHITELISTER_ROLE")); // can whitelist new issuers (brickken);

    // 0x7e634896b27e79a960e89ae00f5b87ef365e84b0543277e0eb9d018a47e752f1
    bytes32 public constant ESCROW_WITHDRAW_ROLE = keccak256(abi.encode("ESCROW_WITHDRAW_ROLE")); // who can partially withdraw to issuer (issuer);
    // 0x373a3fc4287a1339d038c211cc53ad6aed3b80e2257f4889df84173c57e41680
    bytes32 public constant ESCROW_NEW_OFFERING_ROLE = keccak256(abi.encode("ESCROW_NEW_OFFERING_ROLE")); // starts a new offering (issuer);
    // 0x2b797e16dca25f832ef5eecf31aa514d12de6a1d3acdb0e8adae46f707e2d689
    bytes32 public constant ESCROW_ERC20WHITELIST_ROLE = keccak256(abi.encode("ESCROW_ERC20WHITELIST_ROLE")); // add/remove ERC20 from whitelist (brickken, issuer);
    // 0xb33eb5fac4455e424b782c8f7380698677b4c84586b4d8f52049804c691485d4
    bytes32 public constant ESCROW_OFFCHAIN_REPORTER_ROLE = keccak256(abi.encode("ESCROW_OFFCHAIN_REPORTER_ROLE")); // report offchain tickets (issuer);
    // 0x5bff9b7fe86d1ecb8e388c7b1441e17acc34d11a5ea2f7d940ec3e3ce4886499
    bytes32 public constant ESCROW_OFFERING_FINALIZER_ROLE = keccak256(abi.encode("ESCROW_OFFERING_FINALIZER_ROLE")); // finalize an offering (brickken, issuer);

    // 0x4e2d8cfba5434336d245506de15fea51aa5dbefbf272b26dec4a6d6cf5be64bb
    bytes32 public constant TOKEN_MINTER_ADMIN_ROLE = keccak256(abi.encode("TOKEN_MINTER_ADMIN_ROLE")); // add/remove minters (issuer);
    // 0x8d47e3ef6c6edd6d0cd062221e938c7813759ba93d9dabe49168cbc8e44c0758
    bytes32 public constant TOKEN_WHITELIST_ADMIN_ROLE = keccak256(abi.encode("TOKEN_WHITELIST_ADMIN_ROLE")); // change investors whitelist (issuer);
    // 0xf740e572f2d7bd1702c994cd1a49022e4ee57025012d0f6b14521717383b58e2
    bytes32 public constant TOKEN_CONFISCATE_ADMIN_ROLE = keccak256(abi.encode("TOKEN_CONFISCATE_ADMIN_ROLE")); // pause / unpause or disable confiscation (brickken);
    
    // 0x1049b81d2f35f188cbe4711fe8f0ee41a5deefb51b0bfd57490d0252047edf69
    bytes32 public constant TOKEN_URL_ROLE = keccak256(abi.encode("TOKEN_URL_ROLE")); // change url (brickken,issuer);
    // 0xafece24e20488bd8efc86502ef37bf1d0863acdcafe60cff7122dc1ee40280c2
    bytes32 public constant TOKEN_MINTER_ROLE = keccak256(abi.encode("TOKEN_MINTER_ROLE")); // mint new tokens (issuer, escrow contract);
    // 0xe7fd28cbd94ed64bb8cca17950a38aed85f0745ec696947c8e31b86025ae980a
    bytes32 public constant TOKEN_WHITELIST_ROLE = keccak256(abi.encode("TOKEN_WHITELIST_ROLE")); // whether the user is whitelisted or not (issuer);
    // 0x715da9afc9135274cab1c53398817af927b44460ab45f4383352ea02e368b76e
    bytes32 public constant TOKEN_CONFISCATE_EXECUTOR_ROLE = keccak256(abi.encode("TOKEN_CONFISCATE_EXECUTOR_ROLE")); // execute confiscation (brickken);
    // 0x8908c8648724bfdf4166023b8e574b3a283c453f044b1b7f3937995d4cd084f3
    bytes32 public constant TOKEN_DIVIDEND_DISTRIBUTOR_ROLE = keccak256(abi.encode("TOKEN_DIVIDEND_DISTRIBUTOR_ROLE")); // distribute dividends (issuer);
}