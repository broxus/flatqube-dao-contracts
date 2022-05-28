pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;

import "./interfaces/IGauge.sol";
import "./interfaces/IGaugeAccount.sol";
import "./interfaces/IVoteEscrow.sol";
import "./base/gauge_account/GaugeAccountBase.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


contract GaugeAccount is GaugeAccountBase {
    // Cant be deployed directly
    constructor() public { revert(); }

//     TODO: UP
    function upgrade(TvmCell new_code, uint32 new_version, uint32 call_id, uint32 nonce, address send_gas_to) external override onlyGauge {
        if (new_version == current_version) {
            tvm.rawReserve(_reserve(), 0);
            send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
            return;
        }

        TvmBuilder builder;

        // set code after complete this method
        tvm.setcode(new_code);

        // run onCodeUpgrade from new code
        tvm.setCurrentCode(new_code);
        onCodeUpgrade(builder.toCell());
    }

    function onCodeUpgrade(TvmCell upgrade_data) private {
        tvm.resetStorage();
        tvm.rawReserve(_reserve(), 0);

        TvmSlice s = upgrade_data.toSlice();
        (address root_, , address send_gas_to) = s.decode(address, uint8, address);
        gauge = root_;

        platform_code = s.loadRef();

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
