pragma ever-solidity ^0.62.0;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../../../libraries/Errors.sol";
import "../../../libraries/Gas.sol";
import "../../../libraries/PlatformTypes.sol";
import "../../interfaces/IGaugeAccount.sol";
import "../../interfaces/IGaugeFactory.sol";
import "../../GaugeAccount.sol";
import "./GaugeHelpers.sol";
import {RPlatform as Platform} from "../../../Platform.sol";


abstract contract GaugeUpgradable is GaugeHelpers {
    function requestUpdateGaugeAccountCode(uint32 call_id, address send_gas_to) external view onlyOwner {
        require (msg.value >= Gas.REQUEST_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IGaugeFactory(factory).processUpdateGaugeAccountCodeRequest{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(call_id, send_gas_to);
    }

    function updateGaugeAccountCode(TvmCell new_code, uint32 new_version, uint32 call_id, address send_gas_to) external onlyFactory override {
        tvm.rawReserve(_reserve(), 0);

        if (new_version == gauge_account_version) {
            emit GaugeAccountCodeUpdateRejected(call_id);
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

        gaugeAccountCode = new_code;
        emit GaugeAccountCodeUpdated(call_id, gauge_account_version, new_version);
        gauge_account_version = new_version;

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function requestUpgradeGauge(uint32 call_id, address send_gas_to) external view onlyOwner {
        require (msg.value >= Gas.REQUEST_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IGaugeFactory(factory).processUpgradeGaugeRequest{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(call_id, send_gas_to);
    }

    function forceUpgradeGaugeAccount(address user, uint32 call_id, address send_gas_to) external view onlyFactory override {
        tvm.rawReserve(_reserve(), 0);

        address gauge_account = getGaugeAccountAddress(user);
        IGaugeAccount(gauge_account).upgrade{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            gaugeAccountCode, gauge_account_version, call_id, 0, send_gas_to
        );
    }

    function upgradeGaugeAccount(uint32 call_id, uint32 nonce, address send_gas_to) external view {
        require (msg.value >= Gas.GAUGE_ACCOUNT_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        address gauge_account = getGaugeAccountAddress(msg.sender);
        IGaugeAccount(gauge_account).upgrade{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            gaugeAccountCode, gauge_account_version, call_id, nonce, send_gas_to
        );
    }

    function onGaugeAccountUpgrade(
        address user,
        uint32 old_version,
        uint32 new_version,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external view onlyGaugeAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        emit GaugeAccountUpgrade(call_id, user, old_version, new_version);
        _sendCallbackOrGas(user, nonce, true, send_gas_to);
    }

    function onGaugeAccountDeploy(address user, address send_gas_to) external override onlyGaugeAccount(user) {
        emit GaugeAccountDeploy(user);

        tvm.rawReserve(_reserve(), 0);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }
}