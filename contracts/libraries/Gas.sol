pragma ton-solidity ^0.57.1;


library Gas {
    // common
    uint128 constant TOKEN_TRANSFER_VALUE = 0.5 ton;
    uint128 constant TOKEN_WALLET_DEPLOY_VALUE = 0.5 ton;
    uint128 constant MIN_MSG_VALUE = 1 ton;

    // VOTE ESCROW
    uint128 constant VE_ACCOUNT_DEPLOY_VALUE = 0.5 ton;
    uint128 constant PER_GAUGE_VOTE_GAS = 0.02 ton;
    uint128 constant VOTING_TOKEN_TRANSFER_VALUE = 0.7 ton; // additional mechanics on token receive
    uint128 constant VE_ACC_UPGRADE_VALUE = 1.5 ton;
    uint128 constant GAS_FOR_MAX_ITERATIONS = 1.6 ton;

    // VOTE ESCROW ACC
    uint128 constant GAS_PER_DEPOSIT = 0.01 ton;
}
