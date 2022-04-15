pragma ton-solidity ^0.57.1;


import "./GaugeUpgradable.sol";


abstract contract GaugeRewards is GaugeUpgradable {
    function _initRewardData(
        RewardRound[] _extraRewardRounds,
        address[] _reward_token_root,
        uint32[] _vesting_period,
        uint32[] _vesting_ratio
    ) internal {
        for (uint i = 0; i < _reward_token_root.length; i++) {
            ExtraRewardData _reward;
            _reward.tokenData.tokenRoot = _reward_token_root[i];
            _reward.rewardRounds.push(_extraRewardRounds[i]);
            extraRewards.push(_reward);
            extraAccRewardPerShare.push(0);
            extraFarmEndTimes.push(0);
            extraVestingPeriods.push(_vesting_period[i]);
            extraVestingRatios.push(_vesting_ratio[i]);
        }
    }

    function addRewardRounds(uint256[] ids, RewardRound[] new_rounds, address send_gas_to) external onlyOwner {
        require (ids.length == new_rounds.length, Errors.BAD_REWARD_ROUNDS_INPUT);

        for (uint i = 0; i < ids.length; i++) {
            require (new_rounds[i].startTime >= now, Errors.BAD_REWARD_ROUNDS_INPUT);
            RewardRound[] _cur_rounds = extraRewards[ids[i]].rewardRounds;
            require (new_rounds[i].startTime >= _cur_rounds[_cur_rounds.length - 1].startTime, Errors.BAD_REWARD_ROUNDS_INPUT);
            require (extraFarmEndTimes[ids[i]] == 0, Errors.BAD_REWARD_ROUNDS_INPUT);

            extraRewards[ids[i]].rewardRounds.push(new_rounds[i]);
        }

        tvm.rawReserve(_reserve(), 0);

        emit RewardRoundAdded(ids, new_rounds);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setExtraFarmEndTime(uint256[] ids, uint32[] farm_end_times, address send_gas_to) external onlyOwner {
        require (ids.length == farm_end_times.length, Errors.BAD_FARM_END_TIME);
        for (uint i = 0; i < ids.length; i++) {
            require (farm_end_times[i] >= now, Errors.BAD_FARM_END_TIME);
            RewardRound[] _cur_rounds = extraRewards[ids[i]].rewardRounds;
            require (farm_end_times[i] >=  _cur_rounds[_cur_rounds.length - 1].startTime, Errors.BAD_FARM_END_TIME);
            require (extraFarmEndTimes[ids[i]] == 0, Errors.BAD_REWARD_ROUNDS_INPUT);

            extraFarmEndTimes[ids[i]] = farm_end_times[i];
        }

        tvm.rawReserve(_reserve(), 0);

        emit ExtraFarmEndSet(ids, farm_end_times);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function _getMultiplier(uint32 _minFarmTime, uint32 _maxFarmTime, uint32 from, uint32 to) internal view returns(uint32) {
        // restrict by farm start and end time
        to = math.min(to, _maxFarmTime);
        from = math.max(from, _minFarmTime);
        // 'from' cant be bigger then 'to'
        from = math.min(from, to);
        return to - from;
    }


    function _updateRewardRounds(RewardRound[] rewardRounds) internal view returns (RewardRound[]) {
        uint32 _lastRewardTime = lastRewardTime;
        uint32 first_round_start = rewardRounds[0].startTime;

        // reward rounds still not started/update already occurred this block/no deposit balance => nothing to calculate
        if (now < first_round_start || now == _lastRewardTime || depositTokenBalance == 0) {
            return (_accRewardPerShare);
        }

        // special case - last update occurred before start of 1st round
        if (_lastRewardTime < first_round_start) {
            _lastRewardTime = math.min(first_round_start, now);
        }

        // no need to worry about int overflow, we always break reaching i == 0
        for (uint i = rewardRounds.length - 1; i >= 0; i--) {
            // find reward round when last update occurred
            if (_lastRewardTime >= rewardRounds[i].startTime) {
                // we found reward round when last update occurred, start updating reward from this point
                for (uint j = i; j < rewardRounds.length; j++) {
                    RewardRound round = rewardRounds[j];
                    uint32 _roundEndTime = round.endTime > 0 ? round.endTime : MAX_UINT32;
                    // get multiplier bounded by this reward round
                    uint32 multiplier = _getMultiplier(round.startTime, _roundEndTime, _lastRewardTime, now);
                    uint128 new_reward = round.rewardPerSecond * multiplier;
                    round.accRewardPerShare += math.muldiv(new_reward, SCALING_FACTOR, depositTokenBalance);
                    rewardRounds[j] = round;
                    // no need for further steps
                    if (now <= _roundEndTime) {
                        break;
                    }
                    // set _lastRewardTime to end of current round,
                    // we will continue calculation from this moment on next round iteration
                    _lastRewardTime = _roundEndTime;
                }
                break;
            }
        }
        return rewardRounds;
    }

    function _calculateExtraRewardData() internal view returns (ExtraRewardData[] _extraRewards) {
        _extraRewards = extraRewards;
        for (uint i = 0; i < _extraRewards.length; i++) {
            _extraRewards[i].rewardRounds = _updateRewardRounds(_extraRewards[i].rewardRounds);
        }
    }

    function _calculateQubeRewardData() internal view returns (uint256 _accRewardPerShare) {
        _accRewardPerShare = qubeReward.accRewardPerShare;
        uint32 _lastRewardTime = lastRewardTime;
        // copy to local memory to avoid redundant deserialization of big struct
        uint32 nextEpochTime = qubeReward.nextEpochTime;
        uint32 nextEpochEndTime = qubeReward.nextEpochEndTime;
        // qube rewards are disabled/we already updated on this block/no deposit balance/we reached next epoch end => nothing to calculate
        if (qubeReward.enabled == false || _lastRewardTime == now || depositTokenBalance == 0 || lastRewardTime >= nextEpochEndTime) {
            return _accRewardPerShare;
        }
        if (_lastRewardTime < nextEpochTime) {
            // calculate only rewards up to current epoch end
            uint32 to = math.min(now, nextEpochTime);
            uint128 new_reward = qubeReward.rewardPerSecond * (to - _lastRewardTime);
            _accRewardPerShare += math.muldiv(new_reward, SCALING_FACTOR, depositTokenBalance);
            if (now <= nextEpochTime) {
                return _accRewardPerShare;
            }
            _lastRewardTime = nextEpochTime;
        }

        uint32 to = math.min(now, nextEpochEndTime);
        uint128 new_reward = qubeReward.nextEpochRewardPerSecond * (to - _lastRewardTime);
        _accRewardPerShare += math.muldiv(new_reward, SCALING_FACTOR, depositTokenBalance);
    }

    function calculateRewardData() public view returns (uint32 _lastRewardTime, uint256[] _extraAccRewardPerShare, uint256 _qubeAccRewardPerShare) {

        _extraAccRewardPerShare = _calculateExtraRewardData();
        _qubeAccRewardPerShare = _calculateQubeRewardData();
        _lastRewardTime = now;
    }

    function updateRewardData() internal {
        (uint32 _lastRewardTime, uint256[] _extraAccRewardPerShare, uint256 _qubeAccRewardPerShare) = calculateRewardData();
        extraAccRewardPerShare = _extraAccRewardPerShare;
        qubeReward.accRewardPerShare = _qubeAccRewardPerShare;
        lastRewardTime = _lastRewardTime;
    }
}
