pragma ever-solidity ^0.62.0;

import "../../libraries/Callback.sol";


interface IGaugeFactory {
    event QubeVestingParamsUpdate(uint32 call_id, uint32 new_vesting_period, uint32 new_vesting_ratio);
    event GaugeCodeUpdate(uint32 call_id, uint32 prev_version, uint32 new_version);
    event GaugeAccountCodeUpdate(uint32 call_id, uint32 prev_version, uint32 new_version);
    event FactoryUpdate(uint32 call_id, uint32 prev_version, uint32 new_version);
    event NewOwner(uint32 call_id, address prev_owner, address new_owner);
    event NewPendingOwner(uint32 call_id, address pending_owner);
    event NewGauge(uint32 call_id, address gauge);

    function onGaugeDeploy(uint32 deploy_nonce, uint32 call_id) external;
    function processUpgradeGaugeRequest(Callback.CallMeta meta) external view;
    function processUpdateGaugeAccountCodeRequest(Callback.CallMeta meta) external view;
}
