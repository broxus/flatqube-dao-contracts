pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./GaugeAccountStorage.sol";


abstract contract GaugeAccountVesting is GaugeAccountStorage {
    // row sum
    function _rangeSum(uint64 range) internal pure returns (uint64) {
        return (range % 2) == 0 ? ((range / 2) * range + (range / 2)) : (((range / 2) + 1) * range);
    }

    // interval should be less than max
    function _unlockedShareForInterval(uint32 interval, uint32 max) internal pure returns (uint256) {
        return ((_rangeSum(uint64(interval)) * SCALING_FACTOR) / max) / interval;
    }

    // calculate how much will be unlocked after given time passed for given locked amount with vesting period
    function _calcUnlockedForInterval(
        uint128 _locked, uint32 _passed, uint32 _vestingPeriod
    ) internal view returns (uint128 unlocked, uint128 remaining_locked) {
        remaining_locked = _locked;

        if (_passed > _vestingPeriod) {
            uint32 periods_passed = (_passed / _vestingPeriod) - 1;
            uint32 full_unlocked_part = periods_passed * _vestingPeriod + _passed % _vestingPeriod;

            remaining_locked -= uint128(math.muldiv(math.muldiv(full_unlocked_part, SCALING_FACTOR, _passed), remaining_locked, SCALING_FACTOR));
            _passed -= full_unlocked_part;
        }

        remaining_locked -= uint128(math.muldiv(remaining_locked, _unlockedShareForInterval(_passed, _vestingPeriod), SCALING_FACTOR));
        return (_locked - remaining_locked, remaining_locked);
    }

    function _calcUnlocked(
        uint128 _locked, uint32 _poolLastRewardTime, uint32 _lastRewardTime, uint32 _farmEndTime, uint32 _vestingPeriod
    ) internal view returns (uint128 _unlocked) {
        // some safety checks
        // no new entitled rewards after farm end, nothing to compute
        if (_locked == 0 || (_farmEndTime > 0 && _lastRewardTime >= _farmEndTime)) {
            return 0;
        }

        _farmEndTime = _farmEndTime == 0 ? _poolLastRewardTime : _farmEndTime;
        uint32 closestPoint = math.min(_farmEndTime, _poolLastRewardTime);

        (uint128 _unlocked_before, uint128 _locked_before) = _calcUnlockedForInterval(_locked, closestPoint - _lastRewardTime, _vestingPeriod);
        if (_poolLastRewardTime > _farmEndTime) {
            _unlocked += _locked_before * math.min(_poolLastRewardTime - _farmEndTime, _vestingPeriod) / _vestingPeriod;
        }
        _unlocked += _unlocked_before;
    }

    function _computeVesting(
        uint128 _balance,
        uint128 _locked,
        uint128 _rewardDebt,
        uint128 _accRewardPerShare,
        uint32 _poolLastRewardTime,
        uint32 _lastRewardTime,
        uint32 _farmEndTime,
        uint32 _vestingPeriod,
        uint32 _vestingRatio,
        uint32 _vestingTime
    ) internal view returns (uint128 updated_locked, uint128 new_unlocked, uint32 new_vesting_time) {
        uint128 new_reward = math.muldiv(_balance, _accRewardPerShare, SCALING_FACTOR) - _rewardDebt;

        if (_vestingRatio > 0) {
            // calc which part should be payed immediately and with vesting from new reward
            uint128 new_vesting = (new_reward * _vestingRatio) / MAX_VESTING_RATIO;
            uint128 clear_part = new_reward - new_vesting;

            new_unlocked = _calcUnlocked(new_vesting, _poolLastRewardTime, lastRewardTime, _farmEndTime, _vestingPeriod);

            // now calculate newly unlocked part of old locked reward
            uint32 passed = _poolLastRewardTime >= _vestingTime ? _vestingPeriod : _poolLastRewardTime - _lastRewardTime;
            uint128 unlocked_old = passed >= _vestingPeriod
            ? _locked
            : uint128(math.muldiv(_locked, passed, _vestingTime - lastRewardTime));

            // amount of reward locked from now
            uint128 remaining_locked = _locked == 0 ? 0 : _locked - unlocked_old;
            uint128 new_locked = new_vesting - new_unlocked;
            uint128 pending = remaining_locked + new_locked;

            // Compute the vesting time (i.e. when the locked reward to be all unlocked)
            if (pending == 0) {
                new_vesting_time = _poolLastRewardTime;
            } else if (remaining_locked == 0) {
                // only new reward, set vesting time to vesting period
                new_vesting_time = _poolLastRewardTime + _vestingPeriod;
            } else if (new_locked == 0) {
                // only unlocking old reward, dont change vesting time
                new_vesting_time = _vestingTime;
            } else {
                // "old" reward and, perhaps, "new" reward are pending - the weighted average applied
                uint32 passed_2 = _vestingTime - _poolLastRewardTime;
                uint32 period = uint32(((remaining_locked * passed_2) + (new_locked * _vestingPeriod)) / pending);
                new_vesting_time = _poolLastRewardTime + math.min(period, _vestingPeriod);
            }

            new_vesting_time = _farmEndTime > 0 ? math.min(_farmEndTime + _vestingPeriod, new_vesting_time) : new_vesting_time;
            updated_locked = _locked + new_vesting - unlocked_old - new_unlocked;
            new_unlocked += unlocked_old + clear_part;
        } else {
            new_unlocked = new_reward;
            updated_locked = _locked;
            new_vesting_time = _vestingTime;
        }
    }
}
