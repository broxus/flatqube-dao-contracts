pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./IGauge.sol";


interface IGaugeAccount {
    event GaugeAccountUpdated(uint32 prev_version, uint32 new_version);

    struct GaugeAccountDetails {
        uint128[] pool_debt;
        uint128[] entitled;
        uint32[] vestingTime;
        uint128 amount;
        uint128[] rewardDebt;
        address farmPool;
        address user;
        uint32 current_version;
    }


    function getDetails() external responsible view returns (GaugeAccountDetails);
    function processDeposit(
        uint32 deposit_nonce,
        uint128 amount,
        uint128 boosted_amount,
        uint32 lock_time,
        uint128 lockBoostedSupply,
        uint128 lockBoostedSupplyAverage,
        uint32 lockBoostedSupplyAveragePeriod,
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 lastRewardTime
    ) external;
    function processWithdraw(
        uint128 amount,
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 lastRewardTime,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external;
    function processClaimReward(
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 lastRewardTime,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external;
    function increasePoolDebt(uint128 qube_debt, uint128[] extra_debt, address send_gas_to) external;
    function receiveVeAverage(uint32 nonce, uint128 veQubeAverage, uint32 veQubeAveragePeriod) external;
    function receiveVeAccAverage(uint32 callback_nonce, uint128 veQubeAverage, uint32 veQubeAveragePeriod, uint32 lastUpdateTime) external;
    function upgrade(TvmCell new_code, uint32 new_version, uint32 call_id, uint32 nonce, address send_gas_to) external;
}
