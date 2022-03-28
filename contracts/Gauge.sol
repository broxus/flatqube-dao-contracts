pragma ton-solidity ^0.58.2;
pragma AbiHeader expire;

import "./interfaces/IGauge.sol";
import "./interfaces/IFactory.sol";
import "./base/GaugeBase.sol";
import "./libraries/Errors.sol";


contract Gauge is GaugeBase {
    constructor(
        address _owner,
        address _qube,
        address _depositTokenRoot,
        // array of 1st rounds for every token
        RewardRound[] _extraRewardRounds,
        address[] _rewardTokenRoot,
        uint32 _qubeVestingPeriod,
        uint32 _qubeVestingRatio,
        uint32[] _vestingPeriod,
        uint32[] _vestingRatio,
        uint32 _withdrawAllLockPeriod
    ) public {
        // all arrays should have the same dimension
        require (
            _extraRewardRounds.length == _rewardTokenRoot.length &&
            _rewardTokenRoot.length == _vestingPeriod.length &&
            _vestingPeriod.length == _vestingRatio.length,
            Errors.BAD_INPUT
        );
        // vesting params check
        require (_qubeVestingRatio <= 1000, Errors.BAD_VESTING_SETUP);
        require ((_qubeVestingPeriod == 0 && _qubeVestingRatio == 0) || (_qubeVestingPeriod > 0 && _qubeVestingRatio > 0), Errors.BAD_VESTING_SETUP);
        for (uint i = 0; i < _vestingPeriod.length; i++) {
            require (_vestingRatio[i] <= 1000, Errors.BAD_VESTING_SETUP);
            require ((_vestingPeriod[i] == 0 && _vestingRatio[i] == 0) || (_vestingPeriod[i] > 0 && _vestingRatio[i] > 0), Errors.BAD_VESTING_SETUP);
        }

        require (msg.sender == factory, Errors.NOT_FACTORY);
        // qube is reserved as a main reward!
        require (_depositTokenRoot != _qube, Errors.BAD_DEPOSIT_TOKEN);
        for (uint i = 0; i < _rewardTokenRoot.length; i++) {
            require (_rewardTokenRoot[i] != _qube, Errors.BAD_REWARD_TOKENS_INPUT);
        }

        // check reward rounds
        for (uint i = 0; i < _extraRewardRounds.length; i++) {
            require (_extraRewardRounds[i].startTime > now, Errors.BAD_REWARD_ROUNDS_INPUT);
        }

        depositTokenRoot = _depositTokenRoot;
        owner = _owner;
        withdrawAllLockPeriod = _withdrawAllLockPeriod;

        qube_reward.mainData.tokenRoot = _qube;
        qube_reward.mainData.vestingPeriod = _qubeVestingPeriod;
        qube_reward.mainData.vestingRatio = _qubeVestingRatio;

        _initRewardData(_extraRewardRounds, _rewardTokenRoot, _vestingPeriod, _vestingRatio);
        setUpTokenWallets();

        IFactory(factory).onGaugeDeploy{value: FACTORY_DEPLOY_CALLBACK_VALUE}(
            deploy_nonce, _owner, depositTokenRoot, _extraRewardRounds,
            _rewardTokenRoot, qubeVestingPeriod, qubeVestingRatio,
            vestingPeriod, vestingRatio, withdrawAllLockPeriod
        );
    }

    function upgrade(TvmCell new_code, uint32 new_version, address send_gas_to) external override {
        require (msg.sender == factory, Errors.NOT_FACTORY);

        if (new_version == gauge_version) {
            tvm.rawReserve(_reserve(), 0);
            send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
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

    // upgrade from v1
    function onCodeUpgrade(TvmCell upgrade_data) private {}
}