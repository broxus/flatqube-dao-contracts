pragma ton-solidity ^0.57.1;


import "./GaugeUpgradable.sol";


abstract contract GaugeRewards is GaugeUpgradable {
    function _initRewardData(
        uint32[] _extraRewardsStartTime,
        uint32[] _extraRewardsRewardPerSecond,
        address[] _extra_reward_token_root,
        uint32[] _extra_vesting_period,
        uint32[] _extra_vesting_ratio
    ) internal {
        for (uint i = 0; i < _extra_reward_token_root.length; i++) {
            ExtraRewardData _reward;
            _reward.tokenData.tokenRoot = _extra_reward_token_root[i];

            RewardRound first_round;
            first_round.startTime = _extraRewardsStartTime[i];
            first_round.rewardPerSecond = _extraRewardsRewardPerSecond[i];

            _reward.rewardRounds.push(first_round);
            extraRewards.push(_reward);

            extraVestingPeriods.push(_extra_vesting_period[i]);
            extraVestingRatios.push(_extra_vesting_ratio[i]);
        }
    }

    function addRewardRounds(uint256[] ids, RewardRound[] new_rounds, address send_gas_to) external onlyOwner {
        require (ids.length == new_rounds.length, Errors.BAD_REWARD_ROUNDS_INPUT);

        for (uint i = 0; i < ids.length; i++) {
            ExtraRewardData _extraRewards = extraRewards[ids[i]];
            RewardRound[] _cur_rounds = _extraRewards.rewardRounds;

            require (new_rounds[i].startTime >= now, Errors.BAD_REWARD_ROUNDS_INPUT);
            require (new_rounds[i].startTime > _cur_rounds[_cur_rounds.length - 1].startTime, Errors.BAD_REWARD_ROUNDS_INPUT);
            require (_extraRewards.ended == false, Errors.BAD_REWARD_ROUNDS_INPUT);

            _cur_rounds[_cur_rounds.length - 1].endTime = new_rounds[i].startTime;
            _cur_rounds.push(new_rounds[i]);

            extraRewards[ids[i]].rewardRounds = _cur_rounds;
        }

        tvm.rawReserve(_reserve(), 0);

        emit RewardRoundAdded(ids, new_rounds);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setExtraFarmEndTime(uint256[] ids, uint32[] farm_end_times, address send_gas_to) external onlyOwner {
        require (ids.length == farm_end_times.length, Errors.BAD_FARM_END_TIME);

        for (uint i = 0; i < ids.length; i++) {
            ExtraRewardData _extraRewards = extraRewards[ids[i]];
            RewardRound[] _cur_rounds = _extraRewards.rewardRounds;

            require (farm_end_times[i] >= now, Errors.BAD_FARM_END_TIME);
            require (farm_end_times[i] > _cur_rounds[_cur_rounds.length - 1].startTime, Errors.BAD_FARM_END_TIME);
            require (_extraRewards.ended == false, Errors.BAD_REWARD_ROUNDS_INPUT);

            _cur_rounds[_cur_rounds.length - 1].endTime = farm_end_times[i];

            _extraRewards.ended = true;
            _extraRewards.rewardRounds = _cur_rounds;

            extraRewards[ids[i]] = _extraRewards;
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


    function _getUpdateRewardRounds(RewardRound[] rewardRounds, uint256 start_sync_idx) internal view returns (RewardRound[], uint256) {
        uint32 _lastRewardTime = lastRewardTime;
        uint32 first_round_start = rewardRounds[0].startTime;

        // reward rounds still not started/update already occurred this block/no deposit balance => nothing to calculate
        if (now < first_round_start || now == _lastRewardTime || depositTokenBalance == 0) {
            return (rewardRounds, start_sync_idx);
        }

        uint256 _new_sync_idx;
        for (uint j = start_sync_idx; j < rewardRounds.length; j++) {
            RewardRound round = rewardRounds[j];
            uint32 _roundEndTime = round.endTime > 0 ? round.endTime : MAX_UINT32;
            // get multiplier bounded by this reward round
            uint32 multiplier = _getMultiplier(round.startTime, _roundEndTime, _lastRewardTime, now);
            uint128 new_reward = round.rewardPerSecond * multiplier;
            round.accRewardPerShare += math.muldiv(new_reward, SCALING_FACTOR, depositTokenBalance);
            rewardRounds[j] = round;
            // no need for further steps
            _new_sync_idx = j;
            if (now <= _roundEndTime) {
                break;
            }
            // set _lastRewardTime to end of current round,
            // we will continue calculation from this moment on next round iteration
            _lastRewardTime = _roundEndTime;
        }

        return (rewardRounds, _new_sync_idx);
    }

    function _getUpdatedExtraRewardRounds() internal view returns (
        mapping (uint => RewardRound[]) _extraRewardRounds,
        uint256[] _sync_idx
    ) {
        _sync_idx = lastExtraRewardRoundIdx;
        for (uint i = 0; i < extraRewards.length; i++) {
            (_extraRewardRounds[i], _sync_idx[i]) = _getUpdateRewardRounds(extraRewards[i].rewardRounds, lastExtraRewardRoundIdx[i]);
        }
    }

    function calculateRewardData() public view returns (
        uint32 _lastRewardTime,
        mapping (uint => RewardRound[]) _extraRewardRounds,
        uint256[] _extra_sync_idx,
        RewardRound[] _qubeRewardRounds,
        uint256 _qube_sync_idx
    ) {
        (_extraRewardRounds, _extra_sync_idx) = _getUpdatedExtraRewardRounds();
        (_qubeRewardRounds, _qube_sync_idx) = _getUpdateRewardRounds(qubeReward.rewardRounds, lastQubeRewardRoundIdx);
        _lastRewardTime = now;
    }

    function updateRewardData() internal {
        (
            uint32 _lastRewardTime,
            mapping (uint => RewardRound[]) _extraRewardRounds,
            uint256[] _extra_sync_idx,
            RewardRound[] _qubeRewardRounds,
            uint256 _qube_sync_idx
        ) = calculateRewardData();
        for (uint i = 0; i < extraRewards.length; i++) {
            extraRewards[i].rewardRounds = _extraRewardRounds[i];
        }
        lastExtraRewardRoundIdx = _extra_sync_idx;
        qubeReward.rewardRounds = _qubeRewardRounds;
        lastQubeRewardRoundIdx = _qube_sync_idx;
        lastRewardTime = _lastRewardTime;
    }
}
