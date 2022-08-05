pragma ever-solidity ^0.62.0;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/IGaugeAccount.sol";
import "../vote_escrow/interfaces/IVoteEscrow.sol";
import "./base/gauge_account/GaugeAccountBase.sol";


contract GaugeAccount is GaugeAccountBase {
    // Cant be deployed directly
    constructor() public { revert(); }

    function upgrade(TvmCell new_code, uint32 new_version, uint32 call_id, uint32 nonce, address send_gas_to) external override onlyGauge {
        if (new_version == current_version) {
            tvm.rawReserve(_reserve(), 0);
            send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
            return;
        }

        uint8 _tmp;
        TvmBuilder main_builder;
        main_builder.store(gauge); // address 267
        main_builder.store(_tmp); // 8
        main_builder.store(send_gas_to); // address 267

        TvmCell empty;
        main_builder.storeRef(empty); // ref

        TvmBuilder initial;
        initial.store(user);

        main_builder.storeRef(initial); // ref 2

        TvmBuilder params;
        params.store(new_version);
        params.store(current_version);

        main_builder.storeRef(params); // ref3

        TvmCell data = abi.encode(
            call_id,
            nonce,
            balance,
            lockBoostedBalance,
            veBoostedBalance,
            lockedBalance,
            lastAverageState,
            curAverageState,
            lastUpdateTime,
            lockedDepositsNum,
            voteEscrow,
            veAccount,
            lockedDeposits,
            qubeReward,
            extraReward,
            qubeVesting,
            extraVesting,
            _nonce,
            _withdraws,
            _deposits,
            _claims,
            _actions,
            _sync_data
        );

        main_builder.storeRef(data); // ref 4
        // set code after complete this method
        tvm.setcode(new_code);

        // run onCodeUpgrade from new code
        tvm.setCurrentCode(new_code);
        onCodeUpgrade(main_builder.toCell());
    }

    function onCodeUpgrade(TvmCell upgrade_data) private {
        tvm.resetStorage();
        tvm.rawReserve(_reserve(), 0);

        TvmSlice s = upgrade_data.toSlice();
        (address root_, , address send_gas_to) = s.decode(address, uint8, address);
        gauge = root_;

        // skip 0 bits and 1 ref (platform code), we dont need it
        s.skip(0, 1);

        TvmSlice initialData = s.loadRefAsSlice();
        user = initialData.decode(address);

        TvmSlice params = s.loadRefAsSlice();
        uint32 prev_version;
        (current_version, prev_version) = params.decode(uint32, uint32);
        (voteEscrow) = params.decode(address);
        // initialization from platform
        (qubeVesting.vestingPeriod, qubeVesting.vestingRatio) = params.decode(uint32, uint32);
        (uint32[] extraVestingPeriods, uint32[] extraVestingRatios) = params.decode(uint32[], uint32[]);

        extraReward = new RewardData[](extraVestingPeriods.length);
        extraVesting = new VestingData[](extraVestingPeriods.length);

        for (uint i = 0; i < extraVesting.length; i++) {
            extraVesting[i].vestingPeriod = extraVestingPeriods[i];
            extraVesting[i].vestingRatio = extraVestingRatios[i];
        }

        IVoteEscrow(voteEscrow).getVoteEscrowAccountAddress{value: 0.1 ton, callback: IGaugeAccount.receiveVeAccAddress}(user);
        IGauge(gauge).onGaugeAccountDeploy{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, send_gas_to);
    }
}
