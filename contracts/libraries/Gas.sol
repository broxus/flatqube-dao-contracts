pragma ever-solidity ^0.62.0;


library Gas {
    // common
    uint128 constant TOKEN_TRANSFER_VALUE = 0.5 ever;
    uint128 constant TOKEN_WALLET_DEPLOY_VALUE = 0.5 ever;
    uint128 constant MIN_MSG_VALUE = 1.5 ever;

    // VOTE ESCROW
    uint128 constant FACTORY_DEPLOY_CALLBACK_VALUE = 0.1 ever;
    uint128 constant VE_ACCOUNT_DEPLOY_VALUE = 0.5 ever;
    uint128 constant PER_GAUGE_VOTE_GAS = 0.02 ever;
    uint128 constant VOTING_TOKEN_TRANSFER_VALUE = 0.7 ever; // additional mechanics on token receive
    uint128 constant VE_ACC_UPGRADE_VALUE = 1.5 ever;
    uint128 constant GAS_FOR_MAX_ITERATIONS = 1.6 ever;

    // VOTE ESCROW ACC
    uint128 constant GAS_PER_DEPOSIT = 0.01 ever;
    uint128 constant CAST_VOTE_VALUE = 1 ever;
    uint128 constant UNLOCK_LOCKED_VOTE_TOKENS_VALUE = 0.5 ever;
    uint128 constant UNLOCK_CASTED_VOTE_VALUE = 0.2 ever;

    // GAUGE
    uint128 constant REQUEST_UPGRADE_VALUE = 2 ever;
    uint128 constant GAUGE_ACCOUNT_UPGRADE_VALUE = 1.5 ever;
    uint128 constant GAUGE_ACCOUNT_DEPLOY_VALUE = 0.7 ever;
    uint128 constant INCREASE_DEBT_VALUE = 0.2 ever;

    // FACTORY
    uint128 constant GAUGE_DEPLOY_VALUE = 4 ever;
    uint128 constant GAUGE_UPGRADE_VALUE = 1.5 ever;
}
