//pragma ton-solidity ^0.57.1;
//pragma AbiHeader expire;
//
//
//import "./GaugeStorage.sol";
//import "../../libraries/Errors.sol";
//import "../../interfaces/IGaugeAccount.sol";
//import "../../libraries/PlatformTypes.sol";
//import "../../libraries/Errors.sol";
//import "../../GaugeAccount.sol";
//import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
//import "@broxus/contracts/contracts/platform/Platform.sol";
//
//
//abstract contract GaugeUpgradable is GaugeStorage {
//    modifier onlyOwner() {
//        require(msg.sender == owner, Errors.NOT_OWNER);
//        _;
//    }
//
//    function _reserve() internal virtual pure returns (uint128) {
//        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
//    }
//
//    function requestUpdateGaugeAccountCode(address send_gas_to) external virtual onlyOwner {
//        require (msg.value >= REQUEST_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
//        tvm.rawReserve(_reserve(), 0);
//
//        IFactory(factory).processUpdateGaugeAccountCodeRequest{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(send_gas_to);
//    }
//
//    function requestUpgradePool(address send_gas_to) external virtual onlyOwner {
//        require (msg.value >= REQUEST_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
//        tvm.rawReserve(_reserve(), 0);
//
//        IFactory(factory).processUpgradeGaugeRequest{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(send_gas_to);
//    }
//
//    function updateGaugeAccountCode(TvmCell new_code, uint32 new_version, address send_gas_to) external virtual override {
//        require (msg.sender == factory, Errors.NOT_FACTORY);
//        tvm.rawReserve(_reserve(), 0);
//
//        if (new_version == gauge_account_version) {
//            send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
//            return;
//        }
//
//        gaugeAccountCode = new_code;
//        emit GaugeAccountCodeUpdated(gauge_account_version, new_version);
//        gauge_account_version = new_version;
//
//        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
//    }
//
//    function forceUpgradeGaugeAccount(address user, address send_gas_to) external virtual override {
//        require (msg.sender == factory, Errors.NOT_FACTORY);
//        tvm.rawReserve(_reserve(), 0);
//
//        address gauge_account = getGaugeAccountAddress(user);
//        IGaugeAccount(gauge_account).upgrade{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(gaugeAccountCode, gauge_account_version, send_gas_to);
//    }
//
//    function upgradeGaugeAccount(address send_gas_to) external virtual {
//        require (msg.value >= GAUGE_ACCOUNT_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);
//        tvm.rawReserve(_reserve(), 0);
//
//        address gauge_account = getGaugeAccountAddress(msg.sender);
//        IGaugeAccount(gauge_account).upgrade{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(gaugeAccountCode, gauge_account_version, send_gas_to);
//    }
//
//    function getGaugeAccountAddress(address user) public virtual view responsible returns (address) {
//        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } address(tvm.hash(_buildInitData(_buildGaugeAccountParams(user))));
//    }
//
//    function _buildGaugeAccountParams(address user) internal virtual view returns (TvmCell) {
//        TvmBuilder builder;
//        builder.store(user);
//        return builder.toCell();
//    }
//
//    function _buildInitData(TvmCell _initialData) internal virtual view returns (TvmCell) {
//        return tvm.buildStateInit({
//            contr: Platform,
//            varInit: {
//                root: address(this),
//                platformType: PlatformTypes.GaugeAccount,
//                initialData: _initialData,
//                platformCode: platformCode
//            },
//            pubkey: 0,
//            code: platformCode
//        });
//    }
//}