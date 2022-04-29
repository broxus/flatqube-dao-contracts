pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


abstract contract VoteEscrowAccountStorage {
    uint32 current_version;
    TvmCell platform_code;

    address voteEscrow;
    address user;

    uint128 qubeBalance; // total amount of deposited qubes
    uint128 veQubeBalance; // current ve balance
    uint128 expiredVeQubes; // expired ve qubes that should be withdrawn from vote escrow contract
    uint128 unlockedQubes; // qubes with expired lock, that can be withdraw

    // this is updated every time user deposit qubes/ve expire
    uint128 veQubeAverage;
    uint32 veQubeAveragePeriod;
    uint32 lastUpdateTime;

    uint32 lastEpochVoted; // number of last epoch when user voted

//    struct Checkpoint {
//        uint128 lastVeQubeAverage;
//        uint32 lastVeQubeAveragePeriod;
//    }
//
//    // gauge address as a key, stats from VE contract as a value
//    // this is updated for gauge every time he syncs with VE on gauge deposit/withdraw/claim
//    mapping (address => Checkpoint) gaugeTVECheckpoints;
//
//    // gauge address as a key, stats from VEAccount (this) contract as a value
//    // this is updated for gauge every time he syncs with VE on gauge deposit/withdraw/claim
//    mapping (address => Checkpoint) gaugeUVECheckpoints;

    uint32 activeDeposits; // number of currently locked deposits

    struct QubeDeposit {
        uint128 qube_amount;
        uint128 ve_qube_amount; // expire after deposit_time + lock_time
        uint32 deposit_time; // timestamp of deposit
        uint32 lock_time; // lock interval
    }

    mapping (uint64 => QubeDeposit) deposits;

    uint32 constant MAX_ITERATIONS_PER_MSG = 50;
    uint128 constant CONTRACT_MIN_BALANCE = 0.5 ton;
}
