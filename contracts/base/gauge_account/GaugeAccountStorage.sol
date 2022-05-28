pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "../../interfaces/IGauge.sol";
import "../../interfaces/IGaugeAccount.sol";


abstract contract GaugeAccountStorage is IGaugeAccount {
    uint32 current_version;
    TvmCell platform_code;

    struct Averages {
        uint128 veQubeAverage;
        uint32 veQubeAveragePeriod;
        uint128 veAccQubeAverage;
        uint32 veAccQubeAveragePeriod;
        uint128 lockBoostedBalanceAverage;
        uint32 lockBoostedBalanceAveragePeriod;
        uint128 gaugeLockBoostedSupplyAverage;
        uint32 gaugeLockBoostedSupplyAveragePeriod;
    }

    // amount of all deposited tokens
    uint128 balance;
    // balance + bonus for locking deposit
    uint128 lockBoostedBalance;
    // balance + bonus for locking deposit + ve boost
    uint128 veBoostedBalance;

    // aggregated amount of locked deposited tokens
    uint128 lockedBalance;
    // this used for storing expired lock boosted balance during sync
    uint128 expiredLockBoostedBalance;

    // full state of user stats from all contracts (ve/veAcc/gauge) on moment of last action
    Averages lastRewardAverageState;
    // same as above, but is used during sync
    Averages curAverageState;

    // timestamp of last update e.g updating average while syncing
    uint32 lastUpdateTime;
    // number of locked deposits. We need it for gas calculations
    uint32 lockedDepositsNum;

    address gauge;
    address user;
    address voteEscrow;
    address veAccount;

    struct DepositData {
        uint128 amount;
        uint128 boostedAmount;
        uint32 lockTime;
        uint32 createdAt;
    }

    // locked deposits are stored independently
    mapping (uint64 => DepositData) lockedDeposits;

    struct RewardData {
        uint256 accRewardPerShare;
        uint128 lockedReward;
        uint128 unlockedReward;
        uint32 lastRewardTime;
    }

    struct VestingData {
        uint32 vestingTime;
        uint32 vestingPeriod;
        uint32 vestingRatio;
    }

    RewardData qubeReward;
    RewardData[] extraReward;

    VestingData qubeVesting;
    VestingData[] extraVesting;

    // this is stored while we gathering data from all contracts to sync contract state
    struct PendingDeposit {
        uint32 deposit_nonce;
        uint128 amount;
        uint128 boostedAmount;
        uint32 lockTime;
        bool claim;
    }

    struct PendingWithdraw {
        uint128 amount;
        bool claim;
        uint32 call_id;
        uint32 nonce;
        address send_gas_to;
    }

    struct PendingClaim {
        uint32 call_id;
        uint32 nonce;
        address send_gas_to;
    }

    // common sync data for all actions
    struct SyncData {
        uint32 poolLastRewardTime;
        uint128 lockBoostedSupply;
        uint128 veSupply;
        uint128 veAccBalance;
        IGauge.ExtraRewardData[] extraReward;
        IGauge.RewardRound[] qubeRewardRounds;
    }

    enum ActionType { Deposit, Withdraw, Claim }

    uint32 _nonce;
    mapping (uint32 => PendingWithdraw) _withdraws;
    mapping (uint32 => PendingDeposit) _deposits;
    mapping (uint32 => PendingClaim) _claims;
    mapping (uint32 => ActionType) _actions;
    mapping (uint32 => SyncData) _sync_data;


    uint128 constant CONTRACT_MIN_BALANCE = 0.3 ton;
    uint32 constant MAX_VESTING_RATIO = 1000;
    uint256 constant SCALING_FACTOR = 1e18;
    uint128 constant MAX_ITERATIONS_PER_MSG = 50;
}
