pragma ever-solidity ^0.62.0;


library Errors {
    // ERRORS
    // COMMON
    uint16 constant NOT_OWNER = 1000;
    uint16 constant NOT_ACTIVE = 1001;
    uint16 constant NOT_EMERGENCY = 1002;
    uint16 constant WRONG_PUBKEY = 1003;
    uint16 constant LOW_MSG_VALUE = 1004;
    uint16 constant BAD_INPUT = 1005;
    uint16 constant NOT_TOKEN_WALLET = 1006;
    uint16 constant BAD_SENDER = 1007;
    uint16 constant EMERGENCY = 1008;

    // VOTE ESCROW
    uint16 constant NOT_VOTE_ESCROW_ACCOUNT = 2000;
    uint16 constant CANT_BE_INITIALIZED = 2001;
    uint16 constant ALREADY_INITIALIZED = 2002;
    uint16 constant NOT_INITIALIZED = 2003;
    uint16 constant LAST_EPOCH = 2004;
    uint16 constant TOO_EARLY_FOR_VOTING = 2005;
    uint16 constant VOTING_ALREADY_STARTED = 2006;
    uint16 constant VOTING_NOT_STARTED = 2007;
    uint16 constant VOTING_ENDED = 2008;
    uint16 constant GAUGE_NOT_WHITELISTED = 2009;
    uint16 constant MAX_GAUGES_PER_VOTE = 2010;
    uint16 constant VOTING_NOT_ENDED = 2011;
    uint16 constant LOW_DISTRIBUTION_BALANCE = 2012;

    // VE ACCOUNT
    uint16 constant NOT_VOTE_ESCROW = 3000;
    uint16 constant ALREADY_VOTED = 3001;
    uint16 constant NOT_PROPOSAL = 3002;
    uint16 constant NOT_DAO_ROOT = 3003;
    uint16 constant OLD_VERSION = 3004;

    // GAUGE
    uint16 constant NOT_GAUGE_ACCOUNT = 4000;
    uint16 constant NOT_FACTORY = 4001;
    uint16 constant BAD_REWARD_ROUNDS_INPUT = 4002;
    uint16 constant BAD_FARM_END_TIME = 4003;
    uint16 constant CANT_WITHDRAW_UNCLAIMED_ALL = 4004;
    uint16 constant BAD_VESTING_SETUP = 4005;
    uint16 constant BAD_DEPOSIT_TOKEN = 4006;
    uint16 constant BAD_REWARD_TOKENS_INPUT = 4007;
    uint16 constant REASON_IS_TOO_LONG = 4008;
    uint16 constant PROPOSAL_IS_NOT_ACTIVE = 4009;
    uint16 constant WRONG_PROPOSAL_ID = 4010;
    uint16 constant WRONG_PROPOSAL_STATE = 4011;

    // GAUGE ACCOUNT
    uint16 constant NOT_GAUGE = 5000;
    uint16 constant NOT_VOTE_ESCROW_2 = 5001;
    uint16 constant NOT_VOTE_ESCROW_ACCOUNT_2 = 5002;

    // FACTORY
    uint16 constant BAD_GAUGE_CONFIG = 6000;
}
