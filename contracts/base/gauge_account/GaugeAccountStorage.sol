pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


abstract contract GaugeAccountStorage {
    uint32 current_version;
    TvmCell platform_code;

    uint128 balance;
    uint128 lockBoostedBalance;
    uint128 veBoostedBalance;

    uint32 lastRewardTime;
    address gauge;
    address user;
    address voteEscrow;
    address veAccount;

    struct DepositData {
        uint128 amount;
        uint32 lockTime;
        uint32 createdAt;
        uint32 lastRewardTime;

        uint32 qubeVestingTime;
        uint128 qubeLocked;
        uint128 qubeRewardDebt;

        uint32[] extraVestingTimes;
        uint128[] extraLocked;
        uint128[] extraRewardDebts;
    }

    DepositData deposit;
    DepositData[] locked_deposits;

    // common data for all deposits
    uint32 qubeVestingPeriod;
    uint32 qubeVestingRatio;
    uint128 qubeGaugeDebt;
    uint128 unlockedReward;

    uint32[] extraVestingPeriods;
    uint32[] extraVestingRatios;
    uint128[] extraGaugeDebts;
    uint128[] extraUnlockedRewards;

    uint128 constant CONTRACT_MIN_BALANCE = 0.3 ton;
    uint32 constant MAX_VESTING_RATIO = 1000;
    uint256 constant SCALING_FACTOR = 1e18;
}
