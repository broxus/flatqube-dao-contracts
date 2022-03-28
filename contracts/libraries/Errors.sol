pragma ton-solidity ^0.58.2;


library Errors {
    // ERRORS
    uint16 constant NOT_OWNER = 1001;
    uint16 constant NOT_ROOT = 1002;
    uint16 constant NOT_TOKEN_WALLET = 1003;
    uint16 constant LOW_DEPOSIT_MSG_VALUE = 1004;
    uint16 constant NOT_GAUGE_ACCOUNT = 1005;
    uint16 constant EXTERNAL_CALL = 1006;
    uint16 constant ZERO_AMOUNT_INPUT = 1007;
    uint16 constant LOW_WITHDRAW_MSG_VALUE = 1008;
    uint16 constant FARMING_NOT_ENDED = 1009;
    uint16 constant WRONG_INTERVAL = 1010;
    uint16 constant BAD_REWARD_TOKENS_INPUT = 1011;
    uint16 constant NOT_FACTORY = 1012;
    uint16 constant LOW_CLAIM_REWARD_MSG_VALUE = 1013;
    uint16 constant BAD_REWARD_ROUNDS_INPUT = 1014;
    uint16 constant BAD_FARM_END_TIME = 1015;
    uint16 constant BAD_VESTING_SETUP = 1016;
    uint16 constant CANT_WITHDRAW_UNCLAIMED_ALL = 1017;
    uint16 constant LOW_MSG_VALUE = 1018;
    uint16 constant BAD_DEPOSIT_TOKEN = 1019;
    uint16 constant BAD_INPUT = 1020;
}
