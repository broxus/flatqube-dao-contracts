pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./GaugeStorage.sol";
import "../../libraries/Errors.sol";
import "../../libraries/Gas.sol";
import "../../interfaces/IGaugeAccount.sol";
import "../../libraries/PlatformTypes.sol";
import "../../GaugeAccount.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";
import "../../interfaces/ICallbackReceiver.sol";



abstract contract GaugeHelpers is GaugeStorage {
    function _sendCallbackOrGas(address callback_receiver, uint32 nonce, bool success, address send_gas_to) internal pure {
        if (nonce > 0) {
            if (success) {
                ICallbackReceiver(
                    callback_receiver
                ).acceptSuccessCallback{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
            } else {
                ICallbackReceiver(
                    callback_receiver
                ).acceptFailCallback{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
            }
        } else {
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
        }
    }

    modifier onlyGaugeAccount(address user) {
        address expectedAddr = getGaugeAccountAddress(user);
        require (expectedAddr == msg.sender, Errors.NOT_GAUGE_ACCOUNT);
        _;
    }

    function getGaugeAccountAddress(address user) public virtual view responsible returns (address) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } address(tvm.hash(_buildInitData(_buildGaugeAccountParams(user))));
    }

    function _buildGaugeAccountParams(address user) internal virtual view returns (TvmCell) {
        TvmBuilder builder;
        builder.store(user);
        return builder.toCell();
    }

    function _buildInitData(TvmCell _initialData) internal virtual view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Platform,
            varInit: {
                root: address(this),
                platformType: PlatformTypes.GaugeAccount,
                initialData: _initialData,
                platformCode: platformCode
            },
            pubkey: 0,
            code: platformCode
        });
    }

    modifier onlyOwner() {
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    function _reserve() internal virtual pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }
}
