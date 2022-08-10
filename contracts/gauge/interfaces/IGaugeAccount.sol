pragma ever-solidity ^0.62.0;


import "./IGauge.sol";


interface IGaugeAccount {
    struct Averages {
        uint128 veQubeAverage;
        uint32 veQubeAveragePeriod;
        uint128 veAccQubeAverage;
        uint32 veAccQubeAveragePeriod;
        uint128 lockBoostedBalanceAverage;
        uint32 lockBoostedBalanceAveragePeriod;
        uint128 gaugeSupplyAverage;
        uint32 gaugeSupplyAveragePeriod;
    }

    struct DepositData {
        uint128 amount;
        uint128 boostedAmount;
        uint32 lockTime;
        uint32 createdAt;
    }

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

    // common gauge sync data for all actions
    struct AccountSyncData {
        uint32 poolLastRewardTime;
        uint128 gaugeDepositSupply;
        uint128 veSupply;
        uint128 veAccBalance;
        IGauge.RewardRound[][] extraRewardRounds;
        IGauge.RewardRound[] qubeRewardRounds;
    }

    enum ActionType { Deposit, Withdraw, Claim }

    function processDeposit(
        uint32 deposit_nonce,
        uint128 amount,
        uint128 boosted_amount,
        uint32 lock_time,
        bool claim,
        IGauge.GaugeSyncData gauge_sync_data
    ) external;

    function processWithdraw(
        uint128 amount,
        bool claim,
        IGauge.GaugeSyncData gauge_sync_data,
        uint32 call_id,
        uint32 callback_nonce,
        address send_gas_to
    ) external;

    function processClaim(
        IGauge.GaugeSyncData gauge_sync_data,
        uint32 call_id,
        uint32 callback_nonce,
        address send_gas_to
    ) external;

    function increasePoolDebt(uint128 qube_debt, uint128[] extra_debt, address send_gas_to) external;
    function receiveVeAccAverage(
        uint32 nonce,
        uint128 veAccQube,
        uint128 veAccQubeAverage,
        uint32 veAccQubeAveragePeriod
    ) external;
    function receiveVeAverage(
        uint32 nonce,
        uint128 veQubeSupply,
        uint128 veQubeAverage,
        uint32 veQubeAveragePeriod
    ) external;
    function receiveVeAccAddress(address ve_acc_addr) external;
    function syncDepositsRecursive(uint32 nonce, uint32 sync_time, bool reserve) external;
    function updateQubeReward(uint32 nonce, uint128 interval_ve_balance, uint128 interval_lock_balance) external;
    function updateExtraReward(uint32 nonce, uint128 interval_ve_balance, uint128 interval_lock_balance, uint256 idx) external;
    function processDeposit_final(uint32 nonce) external;
    function processWithdraw_final(uint32 nonce) external;
    function processClaim_final(uint32 nonce) external;
    function upgrade(TvmCell new_code, uint32 new_version, uint32 call_id, uint32 nonce, address send_gas_to) external;
}
