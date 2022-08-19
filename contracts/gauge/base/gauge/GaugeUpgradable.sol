pragma ever-solidity ^0.62.0;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../../../libraries/Errors.sol";
import "../../../libraries/Gas.sol";
import "../../../libraries/PlatformTypes.sol";
import "../../../libraries/Callback.sol";
import "../../interfaces/IGaugeAccount.sol";
import "../../interfaces/IGaugeFactory.sol";
import "../../GaugeAccount.sol";
import "./GaugeHelpers.sol";
import {RPlatform as Platform} from "../../../Platform.sol";


abstract contract GaugeUpgradable is GaugeHelpers {
    function requestUpdateGaugeAccountCode(Callback.CallMeta meta) external view onlyOwner {
        require (msg.value >= Gas.REQUEST_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IGaugeFactory(factory).processUpdateGaugeAccountCodeRequest{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(meta);
    }

    function updateGaugeAccountCode(TvmCell new_code, uint32 new_version, Callback.CallMeta meta) external onlyFactory override {
        tvm.rawReserve(_reserve(), 0);

        if (new_version == gauge_account_version) {
            emit GaugeAccountCodeUpdateRejected(meta.call_id);
            meta.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

        gaugeAccountCode = new_code;
        emit GaugeAccountCodeUpdated(meta.call_id, gauge_account_version, new_version);
        gauge_account_version = new_version;

        meta.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function requestUpgradeGauge(Callback.CallMeta meta) external view onlyOwner {
        require (msg.value >= Gas.REQUEST_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IGaugeFactory(factory).processUpgradeGaugeRequest{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(meta);
    }

    function forceUpgradeGaugeAccount(address user, Callback.CallMeta meta) external view onlyFactory override {
        tvm.rawReserve(_reserve(), 0);

        address gauge_account = getGaugeAccountAddress(user);
        IGaugeAccount(gauge_account).upgrade{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            gaugeAccountCode, gauge_account_version, meta
        );
    }

    function upgradeGaugeAccount(Callback.CallMeta meta) external view {
        require (msg.value >= Gas.GAUGE_ACCOUNT_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        address gauge_account = getGaugeAccountAddress(msg.sender);
        IGaugeAccount(gauge_account).upgrade{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            gaugeAccountCode, gauge_account_version, meta
        );
    }

    function onGaugeAccountUpgrade(
        address user,
        uint32 old_version,
        uint32 new_version,
        Callback.CallMeta meta
    ) external view onlyGaugeAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        emit GaugeAccountUpgrade(meta.call_id, user, old_version, new_version);
        _sendCallbackOrGas(user, meta.nonce, true, meta.send_gas_to);
    }

    function onGaugeAccountDeploy(address user, address send_gas_to) external override onlyGaugeAccount(user) {
        emit GaugeAccountDeploy(user);

        tvm.rawReserve(_reserve(), 0);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }
}