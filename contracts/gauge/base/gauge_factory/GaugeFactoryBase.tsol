pragma ever-solidity ^0.62.0;


import "./GaugeFactoryUpgradable.sol";
import "../../Gauge.sol";


abstract contract GaugeFactoryBase is GaugeFactoryUpgradable {
    function getDetails() external view returns (
        uint32 _gauges_count,
        address _owner,
        address _pending_owner,
        uint32 _default_qube_vesting_period,
        uint32 _default_qube_vesting_ratio,
        address _qube,
        address _voteEscrow
    ) {
        return (
            gauges_count,
            owner,
            pending_owner,
            default_qube_vesting_period,
            default_qube_vesting_ratio,
            qube,
            voteEscrow
        );
    }

    function getCodes() external view returns (
        uint32 _factory_version,
        uint32 _gauge_version,
        uint32 _gauge_account_version,
        TvmCell _GaugeAccountCode,
        TvmCell _GaugeCode,
        TvmCell _PlatformCode
    ) {
        return (
            factory_version,
            gauge_version,
            gauge_account_version,
            GaugeAccountCode,
            GaugeCode,
            PlatformCode
        );
    }

    function transferOwnership(address new_owner, Callback.CallMeta meta) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        emit NewPendingOwner(meta.call_id, new_owner);
        pending_owner = new_owner;
        meta.send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function acceptOwnership(Callback.CallMeta meta) external {
        require (msg.sender == pending_owner, Errors.NOT_OWNER);
        tvm.rawReserve(_reserve(), 0);

        emit NewOwner(meta.call_id, owner, pending_owner);
        owner = pending_owner;
        pending_owner = address.makeAddrNone();
        meta.send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function setDefaultQubeVestingParams(uint32 _vesting_period, uint32 _vesting_ratio, Callback.CallMeta meta) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        default_qube_vesting_period = _vesting_period;
        default_qube_vesting_ratio = _vesting_ratio;

        emit QubeVestingParamsUpdate(meta.call_id, default_qube_vesting_period, default_qube_vesting_ratio);
        meta.send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function deployGauge(
        address gauge_owner,
        address depositTokenRoot,
        uint32 maxBoost,
        uint32 maxLockTime,
        address[] rewardTokenRoots,
        uint32[] vestingPeriods,
        uint32[] vestingRatios,
        uint32 withdrawAllLockPeriod,
        uint32 call_id
    ) external {
        _deployGauge(
            gauge_owner,
            depositTokenRoot,
            maxBoost,
            maxLockTime,
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
        uint32 maxBoost,
        uint32 maxLockTime,
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
            maxBoost,
            maxLockTime,
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
        uint32 maxBoost,
        uint32 maxLockTime,
        uint32 qubeVestingPeriod,
        uint32 qubeVestingRatio,
        address[] extraRewardTokenRoot,
        uint32[] extraVestingPeriods,
        uint32[] extraVestingRatios,
        uint32 withdrawAllLockPeriod,
        uint32 call_id
    ) internal {
        tvm.rawReserve(_reserve(), 0);
        uint128 extra_tokens_value = uint128(extraRewardTokenRoot.length) * Gas.TOKEN_WALLET_DEPLOY_VALUE;
        require (msg.value >= Gas.GAUGE_DEPLOY_VALUE + extra_tokens_value, Errors.LOW_MSG_VALUE);

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

        address new_gauge = new Gauge{
            stateInit: stateInit,
            value: Gas.GAUGE_DEPLOY_VALUE + extra_tokens_value - 1 ever,
            wid: address(this).wid
        }(owner, voteEscrow);
        Gauge(new_gauge).setupTokens{value: 0.1 ever}(depositTokenRoot, qube, extraRewardTokenRoot);
        Gauge(new_gauge).setupVesting{value: 0.1 ever}(
            qubeVestingPeriod, qubeVestingRatio, extraVestingPeriods, extraVestingRatios, withdrawAllLockPeriod
        );
        Gauge(new_gauge).setupBoostLock{value: 0.1 ever}(maxBoost, maxLockTime);
        Gauge(new_gauge).initialize{value: 0.1 ever}(call_id);
        msg.sender.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function onGaugeDeploy(uint32 deploy_nonce, uint32 call_id) external override {
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

        emit NewGauge(call_id, gauge_address);
    }
}
