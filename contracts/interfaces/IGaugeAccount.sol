pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./IGauge.sol";


interface IGaugeAccount {
    function processDeposit(
        uint32 deposit_nonce,
        uint128 amount,
        uint128 boosted_amount,
        uint32 lock_time,
        bool claim,
        uint128 lockBoostedSupply,
        uint128 lockBoostedSupplyAverage,
        uint32 lockBoostedSupplyAveragePeriod,
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 poolLastRewardTime
    ) external;

    function processWithdraw(
        uint128 amount,
        bool claim,
        uint128 lockBoostedSupply,
        uint128 lockBoostedSupplyAverage,
        uint32 lockBoostedSupplyAveragePeriod,
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 poolLastRewardTime,
        uint32 call_id,
        uint32 callback_nonce,
        address send_gas_to
    ) external;

    function processClaim(
        uint128 lockBoostedSupply,
        uint128 lockBoostedSupplyAverage,
        uint32 lockBoostedSupplyAveragePeriod,
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 poolLastRewardTime,
        uint32 call_id,
        uint32 callback_nonce,
        address send_gas_to
    ) external;

    function increasePoolDebt(uint128 qube_debt, uint128[] extra_debt, address send_gas_to) external;
    function receiveVeAccAverage(
        uint32 nonce,
        uint128 veAccQube,
        uint128 veAccQubeAverage,
        uint32 veAccQubeAveragePeriod,
        uint32 lastUpdateTime
    ) external;
    function receiveVeAverage(
        uint32 nonce,
        uint128 veQubeSupply,
        uint128 veQubeAverage,
        uint32 veQubeAveragePeriod
    ) external;
    function syncDepositsRecursive(uint32 nonce, uint32 sync_time, bool reserve) external;
    function updateQubeReward(uint32 nonce, uint128 interval_ve_balance, uint128 interval_lock_balance) external;
    function updateExtraReward(uint32 nonce, uint128 interval_ve_balance, uint128 interval_lock_balance, uint256 idx) external;
    function processDeposit_final(uint32 nonce) external;
    function processWithdraw_final(uint32 nonce) external;
    function processClaim_final(uint32 nonce) external;
    function upgrade(TvmCell new_code, uint32 new_version, uint32 call_id, uint32 nonce, address send_gas_to) external;
}
