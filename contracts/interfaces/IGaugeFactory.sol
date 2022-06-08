pragma ton-solidity ^0.60.0;
pragma AbiHeader expire;


interface IGaugeFactory {
    event QubeVestingParamsUpdate(uint32 call_id, uint32 new_vesting_period, uint32 new_vesting_ratio);
    event GaugeCodeUpdate(uint32 prev_version, uint32 new_version);
    event GaugeAccountCodeUpdate(uint32 prev_version, uint32 new_version);
    event FactoryUpdate(uint32 prev_version, uint32 new_version);
    event NewOwner(address prev_owner, address new_owner);
    event NewPendingOwner(address pending_owner);
    event NewGauge(
        uint32 call_id,
        address gauge,
        address gauge_owner,
        address depositTokenRoot,
        address qubeTokenRoot,
        uint32 qubeVestingPeriod,
        uint32 qubeVestingRatio,
        address[] extraRewardTokenRoot,
        uint32[] extraVestingPeriods,
        uint32[] extraVestingRatios,
        uint32 withdrawAllLockPeriod
    );

    function onGaugeDeploy(
        uint32 deploy_nonce,
        address owner,
        address depositTokenRoot,
        address qubeTokenRoot,
        uint32 qubeVestingPeriod,
        uint32 qubeVestingRatio,
        address[] extraRewardTokenRoot,
        uint32[] extraVestingPeriods,
        uint32[] extraVestingRatios,
        uint32 withdrawAllLockPeriod,
        uint32 call_id
    ) external;
    function processUpgradeGaugeRequest(uint32 call_id, address send_gas_to) external view;
    function processUpdateGaugeAccountCodeRequest(uint32 call_id, address send_gas_to) external view;
}
