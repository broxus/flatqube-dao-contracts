pragma ton-solidity ^0.60.0;


import "./GaugeUpgradable.sol";


abstract contract GaugeRewards is GaugeUpgradable {
    // @dev Create new qube reward round with given parameters. Reward per second is set according to len and amount
    // @param qubes_amount - amount of qubes that should be distributed along new round
    // @param round_len - length of new round in seconds
    function _addQubeRewardRound(uint128 qubes_amount, uint32 round_len) internal {
        RewardRound new_qube_round;
        RewardRound[] cur_rounds = qubeRewardRounds;
        RewardRound last_qube_round = cur_rounds[cur_rounds.length - 1];
        uint32 start_time = now > last_qube_round.endTime ? now : last_qube_round.endTime;

        new_qube_round.startTime = start_time;
        new_qube_round.endTime = start_time + round_len;
        new_qube_round.rewardPerSecond = qubes_amount / round_len;

        if (cur_rounds.length == MAX_STORED_ROUNDS) {
            for (uint i = 0; i < cur_rounds.length - 1; i++) {
                cur_rounds[i] = cur_rounds[i + 1];
            }
            cur_rounds[cur_rounds.length - 1] = new_qube_round;
            if (lastQubeRewardRoundIdx > 0) {
                lastQubeRewardRoundIdx -= 1;
            }
        } else {
            cur_rounds.push(new_qube_round);
        }

        qubeRewardRounds = cur_rounds;
        emit QubeRewardRoundAdded(new_qube_round, cur_rounds);
    }

    // @dev accRewardPerShare and endTime params in new_rounds are ignored
    function addRewardRounds(uint256[] ids, RewardRound[] new_rounds, uint32 call_id, address send_gas_to) external onlyOwner {
        require (ids.length == new_rounds.length, Errors.BAD_REWARD_ROUNDS_INPUT);

        for (uint i = 0; i < ids.length; i++) {
            RewardRound[] _cur_rounds = extraRewardRounds[ids[i]];

            require (new_rounds[i].startTime >= now, Errors.BAD_REWARD_ROUNDS_INPUT);
            require (new_rounds[i].startTime > _cur_rounds[_cur_rounds.length - 1].startTime, Errors.BAD_REWARD_ROUNDS_INPUT);
            require (extraRewardEnded[ids[i]] == false, Errors.BAD_REWARD_ROUNDS_INPUT);

            new_rounds[i].endTime = 0;
            new_rounds[i].accRewardPerShare = 0;
            _cur_rounds[_cur_rounds.length - 1].endTime = new_rounds[i].startTime;
            _cur_rounds.push(new_rounds[i]);

            extraRewardRounds[ids[i]] = _cur_rounds;
            emit RewardRoundAdded(call_id, ids[i], new_rounds[i], _cur_rounds);
        }

        tvm.rawReserve(_reserve(), 0);

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setExtraFarmEndTime(uint256[] ids, uint32[] farm_end_times, uint32 call_id, address send_gas_to) external onlyOwner {
        require (ids.length == farm_end_times.length, Errors.BAD_FARM_END_TIME);

        for (uint i = 0; i < ids.length; i++) {
            RewardRound[] _cur_rounds = extraRewardRounds[ids[i]];

            // cant end reward without rounds
            require (_cur_rounds.length > 0, Errors.BAD_REWARD_ROUNDS_INPUT);

            require (farm_end_times[i] >= now, Errors.BAD_FARM_END_TIME);
            require (farm_end_times[i] > _cur_rounds[_cur_rounds.length - 1].startTime, Errors.BAD_FARM_END_TIME);
            require (extraRewardEnded[ids[i]] == false, Errors.BAD_REWARD_ROUNDS_INPUT);

            _cur_rounds[_cur_rounds.length - 1].endTime = farm_end_times[i];

            extraRewardEnded[ids[i]] = true;
            extraRewardRounds[ids[i]] = _cur_rounds;
        }

        tvm.rawReserve(_reserve(), 0);

        emit ExtraFarmEndSet(call_id, ids, farm_end_times);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function _getUpdatedRewardRounds(
        RewardRound[] rewardRounds, uint256 start_sync_idx, uint128 working_supply
    ) internal view returns (RewardRound[], uint256) {
        if (rewardRounds.length == 0) {
            return (rewardRounds, start_sync_idx);
        }
        uint32 _lastRewardTime = lastRewardTime;
        uint32 first_round_start = rewardRounds[0].startTime;

        // reward rounds still not started/update already occurred this block/no deposit balance => nothing to calculate
        if (now <= first_round_start || now == _lastRewardTime || working_supply == 0) {
            return (rewardRounds, start_sync_idx);
        }

        // for case when last update was before 1st round start
        _lastRewardTime = math.max(_lastRewardTime, first_round_start);

        uint256 _new_sync_idx;
        for (uint j = start_sync_idx; j < rewardRounds.length; j++) {
            RewardRound round = rewardRounds[j];
            uint32 _roundEndTime = round.endTime > 0 ? round.endTime : now;
            _roundEndTime = math.min(_roundEndTime, now);
            _lastRewardTime = math.min(_lastRewardTime, _roundEndTime);

            // get multiplier bounded by this reward round
            uint32 multiplier = _roundEndTime - _lastRewardTime;
            uint128 new_reward = round.rewardPerSecond * multiplier;
            // if we sync this round 1st time, copy accRewardPerShare
            if (round.accRewardPerShare == 0 && j > 0) {
                round.accRewardPerShare = rewardRounds[j - 1].accRewardPerShare;
            }
            round.accRewardPerShare += math.muldiv(new_reward, SCALING_FACTOR, working_supply);
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

    function _getUpdatedExtraRewardRounds() internal view returns (RewardRound[][] _extraRewardRounds, uint256[] _sync_idx) {
        _sync_idx = lastExtraRewardRoundIdx;
        _extraRewardRounds = extraRewardRounds;

        for (uint i = 0; i < extraTokenData.length; i++) {
            (_extraRewardRounds[i], _sync_idx[i]) = _getUpdatedRewardRounds(extraRewardRounds[i], lastExtraRewardRoundIdx[i], lockBoostedSupply);
        }
    }

    function calculateRewardData() public view returns (
        uint32 _lastRewardTime,
        RewardRound[][] _extraRewardRounds,
        uint256[] _extra_sync_idx,
        RewardRound[] _qubeRewardRounds,
        uint256 _qube_sync_idx
    ) {
        (_extraRewardRounds, _extra_sync_idx) = _getUpdatedExtraRewardRounds();
        (_qubeRewardRounds, _qube_sync_idx) = _getUpdatedRewardRounds(qubeRewardRounds, lastQubeRewardRoundIdx, veBoostedSupply);
        _lastRewardTime = now;
    }

    function updateSupplyAverage() internal {
        if (now <= lastAverageUpdateTime || lastAverageUpdateTime == 0) {
            // already updated on this block or this is our first update
            lastAverageUpdateTime = now;
            return;
        }

        uint32 last_period = now - lastAverageUpdateTime;
        lockBoostedSupplyAverage = (lockBoostedSupplyAverage * lockBoostedSupplyAveragePeriod + lockBoostedSupply * last_period) / (lockBoostedSupplyAveragePeriod + last_period);
        lockBoostedSupplyAveragePeriod += last_period;
    }

    function updateRewardData() internal {
        (
            lastRewardTime,
            extraRewardRounds,
            lastExtraRewardRoundIdx,
            qubeRewardRounds,
            lastQubeRewardRoundIdx
        ) = calculateRewardData();

        updateSupplyAverage();

    }
}
