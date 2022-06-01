pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./interfaces/IGauge.sol";
import "./interfaces/IGaugeFactory.sol";
import "./base/gauge/GaugeBase.sol";
import "./libraries/Errors.sol";


contract Gauge is GaugeBase {
    constructor(
        address _owner,
        address _depositTokenRoot,
        address _qubeTokenRoot,
        uint32 _qubeVestingPeriod,
        uint32 _qubeVestingRatio,
        address[] _extraRewardTokenRoot,
        uint32[] _extraVestingPeriods,
        uint32[] _extraVestingRatios,
        uint32 _withdrawAllLockPeriod,
        uint32 call_id
    ) public {
        require (msg.sender == factory, Errors.NOT_FACTORY);
        // all arrays should have the same dimension
        require (
            _extraRewardTokenRoot.length == _extraVestingPeriods.length &&
            _extraVestingPeriods.length == _extraVestingRatios.length,
            Errors.BAD_INPUT
        );
        // vesting params check
        require (_qubeVestingRatio <= 1000, Errors.BAD_VESTING_SETUP);
        require ((_qubeVestingPeriod == 0 && _qubeVestingRatio == 0) || (_qubeVestingPeriod > 0 && _qubeVestingRatio > 0), Errors.BAD_VESTING_SETUP);
        for (uint i = 0; i < _extraVestingPeriods.length; i++) {
            require (_extraVestingRatios[i] <= 1000, Errors.BAD_VESTING_SETUP);
            require (
                (_extraVestingPeriods[i] == 0 && _extraVestingRatios[i] == 0) ||
                (_extraVestingPeriods[i] > 0 && _extraVestingRatios[i] > 0),
                Errors.BAD_VESTING_SETUP
            );
        }

        // qube is reserved as a main reward!
        require (_depositTokenRoot != _qubeTokenRoot, Errors.BAD_DEPOSIT_TOKEN);
        for (uint i = 0; i < _extraRewardTokenRoot.length; i++) {
            require (_extraRewardTokenRoot[i] != _qubeTokenRoot, Errors.BAD_REWARD_TOKENS_INPUT);
        }

        owner = _owner;
        depositTokenRoot = _depositTokenRoot;
        withdrawAllLockPeriod = _withdrawAllLockPeriod;

        qubeTokenData.tokenRoot = _qubeTokenRoot;
        qubeVestingPeriod = _qubeVestingPeriod;
        qubeVestingRatio = _qubeVestingRatio;

        extraVestingPeriods = _extraVestingPeriods;
        extraVestingRatios = _extraVestingRatios;
        extraRewardEnded = new bool[](_extraRewardTokenRoot.length);
        extraRewardRounds = new RewardRound[][](_extraRewardTokenRoot.length);
        for (uint i = 0; i < _extraRewardTokenRoot.length; i++) {
            extraTokenData.push(TokenData(_extraRewardTokenRoot[i], address.makeAddrNone(), 0));
        }

        _setUpTokenWallets();

        IGaugeFactory(factory).onGaugeDeploy{value: Gas.FACTORY_DEPLOY_CALLBACK_VALUE}(
            deploy_nonce, _owner, _depositTokenRoot, _qubeTokenRoot, _qubeVestingPeriod, _qubeVestingRatio,
            _extraRewardTokenRoot, _extraVestingPeriods, _extraVestingRatios, _withdrawAllLockPeriod, call_id
        );
    }

    function upgrade(TvmCell new_code, uint32 new_version, uint32 call_id, address send_gas_to) external override {
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

    function onCodeUpgrade(TvmCell upgrade_data) private {}
}