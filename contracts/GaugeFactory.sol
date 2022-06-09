pragma ever-solidity ^0.60.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import './interfaces/IGauge.sol';
import "./base/gauge_factory/GaugeFactoryBase.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


contract GaugeFactory is GaugeFactoryBase {
    constructor(address _owner, address _qube, uint32 _qube_vesting_ratio, uint32 _qube_vesting_period) public {
        require (tvm.pubkey() != 0, Errors.WRONG_PUBKEY);
        require (tvm.pubkey() == msg.pubkey(), Errors.WRONG_PUBKEY);
        tvm.accept();

        owner = _owner;
        qube = _qube;

        default_qube_vesting_period = _qube_vesting_period;
        default_qube_vesting_ratio = _qube_vesting_ratio;
    }

    function upgrade(TvmCell new_code, address send_gas_to) public onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);

        TvmCell data = abi.encode(
            send_gas_to,
            factory_version,
            gauge_version,
            gauge_account_version,
            gauges_count,
            owner,
            pending_owner,
            default_qube_vesting_period,
            default_qube_vesting_ratio,
            qube,
            GaugeAccountCode,
            GaugeCode,
            PlatformCode,
            nonce
        );

        tvm.setcode(new_code);
        tvm.setCurrentCode(new_code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell data) internal {}
}