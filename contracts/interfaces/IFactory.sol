pragma ton-solidity ^0.58.2;
pragma AbiHeader expire;


import "./IGauge.sol";


interface IFactory {
    function onGaugeDeploy(
        uint64 pool_deploy_nonce,
        address pool_owner,
        address tokenRoot,
        IGauge.RewardRound[] extraRewardRounds,
        address[] rewardTokenRoot,
        uint32 qubeVestingPeriod,
        uint32 qubeVestingRatio,
        uint32[] vestingPeriod,
        uint32[] vestingRatio,
        uint32 withdrawAllLockPeriod
    ) external;
    function processUpgradeGaugeRequest(address send_gas_to) external;
    function processUpdateGaugeAccountCodeRequest(address send_gas_to) external;
}
