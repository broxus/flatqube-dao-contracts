pragma ever-solidity ^0.62.0;


import "./GaugeFactoryUpgradable.sol";
import "../../Gauge.sol";


abstract contract GaugeFactoryBase is GaugeFactoryUpgradable {
    function transferOwnership(address new_owner, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        emit NewPendingOwner(new_owner);
        pending_owner = new_owner;
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function acceptOwnership(address send_gas_to) external {
        require (msg.sender == pending_owner, Errors.NOT_OWNER);
        tvm.rawReserve(_reserve(), 0);

        emit NewOwner(owner, pending_owner);
        owner = pending_owner;
        pending_owner = address.makeAddrNone();
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function setDefaultQubeVestingParams(uint32 _vesting_period, uint32 _vesting_ratio, uint32 call_id, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        default_qube_vesting_period = _vesting_period;
        default_qube_vesting_ratio = _vesting_ratio;

        emit QubeVestingParamsUpdate(call_id, default_qube_vesting_period, default_qube_vesting_ratio);
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function deployGauge(
        address gauge_owner,
        address depositTokenRoot,
        address[] rewardTokenRoots,
        uint32[] vestingPeriods,
        uint32[] vestingRatios,
        uint32 withdrawAllLockPeriod,
        uint32 call_id
    ) external {
        _deployGauge(
            gauge_owner,
            depositTokenRoot,
            default_qube_vesting_period,
            default_qube_vesting_ratio,
            rewardTokenRoots,
            vestingPeriods,
            vestingRatios,
            withdrawAllLockPeriod,
            call_id
        );
    }

    function deployGaugeByOwner(
        address gauge_owner,
        address depositTokenRoot,
        uint32 qubeVestingPeriod,
        uint32 qubeVestingRatio,
        address[] rewardTokenRoots,
        uint32[] vestingPeriods,
        uint32[] vestingRatios,
        uint32 withdrawAllLockPeriod,
        uint32 call_id
    ) external onlyOwner {
        _deployGauge(
            gauge_owner,
            depositTokenRoot,
            qubeVestingPeriod,
            qubeVestingRatio,
            rewardTokenRoots,
            vestingPeriods,
            vestingRatios,
            withdrawAllLockPeriod,
            call_id
        );
    }

    function _deployGauge(
        address owner,
        address depositTokenRoot,
        uint32 qubeVestingPeriod,
        uint32 qubeVestingRatio,
        address[] extraRewardTokenRoot,
        uint32[] extraVestingPeriods,
        uint32[] extraVestingRatios,
        uint32 withdrawAllLockPeriod,
        uint32 call_id
    ) internal {
        tvm.rawReserve(_reserve(), 0);
        require (msg.value >= Gas.GAUGE_DEPLOY_VALUE, Errors.LOW_MSG_VALUE);

        TvmCell stateInit = tvm.buildStateInit({
            contr: Gauge,
            varInit: {
                gaugeAccountCode: GaugeAccountCode,
                platformCode: PlatformCode,
                deploy_nonce: gauges_count,
                factory: address(this),
                gauge_account_version: gauge_account_version,
                gauge_version: gauge_version
            },
            pubkey: tvm.pubkey(),
            code: GaugeCode
        });
        gauges_count += 1;

        new Gauge{
            stateInit: stateInit,
            value: 0,
            wid: address(this).wid,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(
            owner, depositTokenRoot, qube, qubeVestingPeriod, qubeVestingRatio, extraRewardTokenRoot,
            extraVestingPeriods, extraVestingRatios, withdrawAllLockPeriod, call_id
        );
    }

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
    ) external override {
        TvmCell stateInit = tvm.buildStateInit({
            contr: Gauge,
            varInit: {
                gaugeAccountCode: GaugeAccountCode,
                platformCode: PlatformCode,
                deploy_nonce: deploy_nonce,
                factory: address(this),
                gauge_account_version: gauge_account_version,
                gauge_version: gauge_version
            },
            pubkey: tvm.pubkey(),
            code: GaugeCode
        });
        address gauge_address = address(tvm.hash(stateInit));
        require (msg.sender == gauge_address, Errors.NOT_GAUGE);

        emit NewGauge(
            call_id,gauge_address, owner, depositTokenRoot, qubeTokenRoot, qubeVestingPeriod, qubeVestingRatio,
            extraRewardTokenRoot, extraVestingPeriods, extraVestingRatios, withdrawAllLockPeriod
        );
    }
}
