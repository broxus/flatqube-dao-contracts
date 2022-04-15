pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;

import "./interfaces/IGauge.sol";
import "./interfaces/IGaugeAccount.sol";
import "./base/account/GaugeAccountBase.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


contract GaugeAccount is GaugeAccountBase {
    // Cant be deployed directly
    constructor() public { revert(); }

    // TODO: sync
//    function upgrade(TvmCell new_code, uint32 new_version, address send_gas_to) external virtual override {
//        require (msg.sender == farmPool, NOT_FARM_POOL);
//
//        if (new_version == current_version) {
//            tvm.rawReserve(_reserve(), 0);
//            send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
//            return;
//        }
//
//        TvmBuilder main_builder;
//        main_builder.store(farmPool);
//        main_builder.store(uint8(0));
//        main_builder.store(send_gas_to);
//
//        main_builder.store(platform_code);
//
//        TvmBuilder initial_data;
//        initial_data.store(user);
//
//        TvmBuilder params;
//        params.store(new_version);
//        params.store(current_version);
//
//        main_builder.storeRef(initial_data);
//        main_builder.storeRef(params);
//
//        TvmBuilder data_builder;
//        data_builder.store(lastRewardTime); // 32
//        data_builder.store(vestingPeriod); // 32
//        data_builder.store(vestingRatio); // 32
//        data_builder.store(vestingTime); // 33 + ref
//        data_builder.store(amount); // 128
//        data_builder.store(rewardDebt); // 33 + ref
//        data_builder.store(entitled); // 33 + ref
//        data_builder.store(pool_debt); // 33 + ref
//
//        main_builder.storeRef(data_builder);
//
//        // set code after complete this method
//        tvm.setcode(new_code);
//
//        // run onCodeUpgrade from new code
//        tvm.setCurrentCode(new_code);
//        onCodeUpgrade(main_builder.toCell());
//    }

    function onCodeUpgrade(TvmCell upgrade_data) private {
        tvm.resetStorage();
        tvm.rawReserve(_reserve(), 0);

        TvmSlice s = upgrade_data.toSlice();
        (address root_, , address send_gas_to) = s.decode(address, uint8, address);
        farmPool = root_;

        platform_code = s.loadRef();

        TvmSlice initialData = s.loadRefAsSlice();
        user = initialData.decode(address);

        TvmSlice params = s.loadRefAsSlice();
        uint32 prev_version;
        (current_version, prev_version) = params.decode(uint32, uint32);
        // initialization from platform
        (uint8 tokens_num, uint32 _vestingPeriod, uint32 _vestingRatio) = params.decode(uint8, uint32, uint32);
        _init(tokens_num, _vestingPeriod, _vestingRatio);
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

}
