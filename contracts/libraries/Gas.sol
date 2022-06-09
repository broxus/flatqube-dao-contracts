pragma ever-solidity ^0.60.0;


library Gas {
    // common
    uint128 constant TOKEN_TRANSFER_VALUE = 0.5 ton;
    uint128 constant TOKEN_WALLET_DEPLOY_VALUE = 0.5 ton;
    uint128 constant MIN_MSG_VALUE = 1.5 ton;

    // VOTE ESCROW
    uint128 constant FACTORY_DEPLOY_CALLBACK_VALUE = 0.1 ton;
    uint128 constant VE_ACCOUNT_DEPLOY_VALUE = 0.5 ton;
    uint128 constant PER_GAUGE_VOTE_GAS = 0.02 ton;
    uint128 constant VOTING_TOKEN_TRANSFER_VALUE = 0.7 ton; // additional mechanics on token receive
    uint128 constant VE_ACC_UPGRADE_VALUE = 1.5 ton;
    uint128 constant GAS_FOR_MAX_ITERATIONS = 1.6 ton;

    // VOTE ESCROW ACC
    uint128 constant GAS_PER_DEPOSIT = 0.01 ton;

    // GAUGE
    uint128 constant REQUEST_UPGRADE_VALUE = 2 ton;
    uint128 constant GAUGE_ACCOUNT_UPGRADE_VALUE = 1.5 ton;
    uint128 constant GAUGE_ACCOUNT_DEPLOY_VALUE = 0.5 ton;
    uint128 constant INCREASE_DEBT_VALUE = 0.2 ton;

    // FACTORY
    uint128 constant GAUGE_DEPLOY_VALUE = 5 ton;
    uint128 constant GAUGE_UPGRADE_VALUE = 1.5 ton;
}
