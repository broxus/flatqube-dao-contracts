pragma ever-solidity ^0.62.0;


import "./base/gauge/GaugeBase.sol";
import "../libraries/Errors.sol";
import "../libraries/Callback.sol";


contract Gauge is GaugeBase {
    constructor(address _owner, address _voteEscrow) public onlyFactory {
        owner = _owner;
        voteEscrow = _voteEscrow;
    }

    function upgrade(TvmCell new_code, uint32 new_version, Callback.CallMeta meta) external override {
        require (msg.sender == factory, Errors.NOT_FACTORY);

        if (new_version == gauge_version) {
            tvm.rawReserve(_reserve(), 0);
            meta.send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
            return;
        }

        // TODO: sync
        // should be unpacked in the same order!
        //        TvmCell data = abi.encode(
        //            new_version, // 32
        //            send_gas_to, // 267
        //            withdrawAllLockPeriod, // 32
        //            lastRewardTime, // 32
        //            farmEndTime, // 32
        //            vestingPeriod, // 32
        //            vestingRatio,// 32
        //            tokenRoot, // 267
        //            tokenWallet, // 267
        //            tokenBalance, // 128
        //            rewardRounds, // 33 + ref
        //            accRewardPerShare, // 33 + ref
        //            rewardTokenRoot, // 33 + ref
        //            rewardTokenWallet, // 33 + ref
        //            rewardTokenBalance, // 33 + ref
        //            rewardTokenBalanceCumulative, // 33 + ref
        //            unclaimedReward, // 33 + ref
        //            owner, // 267
        //            deposit_nonce, // 64
        //            deposits, // 33 + ref
        //            platformCode, // 33 + ref
        //            userDataCode, // 33 + ref
        //            factory, // 267
        //            deploy_nonce, // 64
        //            user_data_version, // 32
        //            gauge_version // 32
        //        );
        TvmCell data;

        // set code after complete this method
        tvm.setcode(new_code);
        // run onCodeUpgrade from new code
        tvm.setCurrentCode(new_code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell upgrade_data) private {}
}
