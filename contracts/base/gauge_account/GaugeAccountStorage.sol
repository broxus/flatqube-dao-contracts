pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "../../interfaces/IGauge.sol";


abstract contract GaugeAccountStorage {
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

    uint128 balance;
    uint128 lockBoostedBalance;
    uint128 veBoostedBalance;

    uint128 lockedBalance;
    uint128 expiredLockBoostedBalance;

    Averages lastRewardAverageState;
    Averages curAverageState;

    uint32 lastRewardTime;
    uint32 lastUpdateTime;
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

    DepositData deposit; // unlocked part
    mapping (uint64 => DepositData) lockedDeposits;

    uint128 qubeLocked;
    uint128 qubeUnlocked;
    uint128 qubeRewardDebt;
    uint128 qubeGaugeDebt;

    uint128[] extraLocked;
    uint128[] extraUnlocked;
    uint128[] extraRewardDebts;
    uint128[] extraGaugeDebts;

    // vesting data
    uint32 qubeVestingTime;
    uint32 qubeVestingPeriod;
    uint32 qubeVestingRatio;
    uint32[] extraVestingTimes;
    uint32[] extraVestingPeriods;
    uint32[] extraVestingRatios;

    struct PendingDeposit {
        uint32 deposit_nonce;
        uint128 amount;
        uint128 boostedAmount;
        uint32 lockTime;
        IGauge.ExtraRewardData[] extraRewards;
        IGauge.RewardRound[] qubeRewardRounds;
    }

    struct SyncData {
        uint32 poolLastRewardTime;
        uint128 lockBoostedSupply;
        uint128 veSupply;
        uint128 veAccBalance;
    }

    enum ActionType { Deposit, Withdraw, Claim }

    uint32 _nonce;
    mapping (uint32 => PendingDeposit) _deposits;
    mapping (uint32 => ActionType) _actions;
    mapping (uint32 => SyncData) _sync_data;


    uint128 constant CONTRACT_MIN_BALANCE = 0.3 ton;
    uint32 constant MAX_VESTING_RATIO = 1000;
    uint256 constant SCALING_FACTOR = 1e18;
    uint128 constant MAX_ITERATIONS_PER_MSG = 50;
}
