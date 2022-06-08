pragma ton-solidity ^0.60.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "../../interfaces/IGaugeFactory.sol";
import '../../interfaces/IGauge.sol';


abstract contract GaugeFactoryStorage is IGaugeFactory {
    uint32 factory_version;
    uint32 gauge_version;
    uint32 gauge_account_version;

    uint32 gauges_count = 0;
    address owner;
    address pending_owner;

    uint32 default_qube_vesting_period;
    uint32 default_qube_vesting_ratio;

    address qube;

    TvmCell static GaugeAccountCode;
    TvmCell static GaugeCode;
    TvmCell static PlatformCode;

    // factory deployment seed
    uint128 static nonce;
    uint128 constant CONTRACT_MIN_BALANCE = 1 ton;
}