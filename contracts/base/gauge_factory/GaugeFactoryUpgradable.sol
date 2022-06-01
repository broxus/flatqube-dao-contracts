pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "./GaugeFactoryStorage.sol";
import "../../libraries/Errors.sol";
import "../../libraries/Gas.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


abstract contract GaugeFactoryUpgradable is GaugeFactoryStorage {
    modifier onlyOwner() {
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    function _reserve() internal pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }

    function installNewGaugeCode(TvmCell gauge_code, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        GaugeCode = gauge_code;
        gauge_version++;
        emit GaugeCodeUpdate(gauge_version - 1, gauge_version);
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function installNewGaugeAccountCode(TvmCell gauge_account_code, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        GaugeAccountCode = gauge_account_code;
        gauge_account_version++;
        emit GaugeAccountCodeUpdate(gauge_account_version - 1, gauge_account_version);
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function upgradeGauges(address[] gauges, uint32 call_id, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE + Gas.GAUGE_UPGRADE_VALUE * gauges.length, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        for (uint i = 0; i < gauges.length; i++) {
            IGauge(gauges[i]).upgrade{value: Gas.GAUGE_UPGRADE_VALUE, flag: MsgFlag.SENDER_PAYS_FEES}(
                GaugeCode, gauge_version, call_id, send_gas_to
            );
        }
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function updateGaugeAccountsCode(address[] gauges, uint32 call_id, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE + Gas.GAUGE_UPGRADE_VALUE * gauges.length, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        for (uint i = 0; i < gauges.length; i++) {
            IGauge(gauges[i]).updateGaugeAccountCode{value: Gas.GAUGE_UPGRADE_VALUE, flag: MsgFlag.SENDER_PAYS_FEES}(
                GaugeAccountCode, gauge_account_version, call_id, send_gas_to
            );
        }
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function forceUpgradeGaugeAccounts(address gauge, address[] users, uint32 call_id, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE + Gas.GAUGE_UPGRADE_VALUE * users.length, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        for (uint i = 0; i < users.length; i++) {
            IGauge(gauge).forceUpgradeGaugeAccount{value: 0, flag: MsgFlag.SENDER_PAYS_FEES}(users[i], call_id, send_gas_to);
        }

        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function processUpgradeGaugeRequest(uint32 call_id, address send_gas_to) external override {
        require (msg.value >= Gas.GAUGE_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IGauge(msg.sender).upgrade{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            GaugeCode, gauge_version, call_id, send_gas_to
        );
    }

    function processUpdateGaugeAccountCodeRequest(uint32 call_id, address send_gas_to) external override {
        require (msg.value >= Gas.GAUGE_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IGauge(msg.sender).updateGaugeAccountCode{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            GaugeAccountCode, gauge_account_version, call_id, send_gas_to
        );
    }
}