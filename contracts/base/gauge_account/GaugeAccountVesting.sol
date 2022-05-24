pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./GaugeAccountStorage.sol";


abstract contract GaugeAccountVesting is GaugeAccountStorage {
//    function _isEven(uint64 num) internal pure returns (bool) {
//        return (num / 2) == 0 ? true : false;
//    }
//
//    function _rangeSum(uint64 range) internal pure returns (uint64) {
//        if (_isEven(range)) {
//            return (range / 2) * range + (range / 2);
//        }
//        return ((range / 2) + 1) * range;
//    }
//
//    // interval should be less than max
//    function _rangeIntervalAverage(uint32 interval, uint32 max) internal pure returns (uint256) {
//        return (_rangeSum(uint64(interval)) * SCALING_FACTOR) / max;
//    }
//
//    // only applied if _interval is bigger than vestingPeriod, will throw integer overflow otherwise
//    function _computeVestedForInterval(uint128 _entitled, uint32 _interval) internal view returns (uint128, uint128) {
//        uint32 periods_passed = ((_interval / vestingPeriod) - 1);
//        uint32 full_vested_part = periods_passed * vestingPeriod + _interval % vestingPeriod;
//        uint32 partly_vested_part = _interval - full_vested_part;
//
//        // get part of entitled reward that already vested, because their vesting period is passed
//        uint128 clear_part_1 = uint128((((full_vested_part * SCALING_FACTOR) / _interval) * _entitled) / SCALING_FACTOR);
//        uint128 vested_part = _entitled - clear_part_1;
//
//        // now calculate vested share of remaining part
//        uint256 clear_part_2_share = _rangeIntervalAverage(partly_vested_part, vestingPeriod) / partly_vested_part;
//        uint128 clear_part_2 = uint128(vested_part * clear_part_2_share / SCALING_FACTOR);
//        uint128 remaining_entitled = vested_part - clear_part_2;
//
//        return (clear_part_1 + clear_part_2, remaining_entitled);
//    }
//
//    // this is used only when lastRewardTime < farmEndTime, because newly entitled reward not emitted otherwise
//    // will throw with integer overflow otherwise
//    function _computeVestedForNewlyEntitled(uint128 _entitled, uint32 _poolLastRewardTime, uint32 _farmEndTime) internal view returns (uint128 _vested) {
//        if (_entitled == 0) {
//            return 0;
//        }
//        if (_farmEndTime == 0 || _poolLastRewardTime < _farmEndTime) {
//            uint32 age = _poolLastRewardTime - lastRewardTime;
//
//            if (age > vestingPeriod) {
//                (uint128 _vested_part, uint128 _) = _computeVestedForInterval(_entitled, age);
//                return _vested_part;
//            } else {
//                uint256 clear_part_share = _rangeIntervalAverage(age, vestingPeriod) / age;
//                return uint128(_entitled * clear_part_share / SCALING_FACTOR);
//            }
//        } else {
//            uint32 age_before = _farmEndTime - lastRewardTime;
//            uint32 age_after = math.min(_poolLastRewardTime - _farmEndTime, vestingPeriod);
//
//            uint128 _vested_before;
//            uint128 _entitled_before;
//            if (age_before > vestingPeriod) {
//                (_vested_before, _entitled_before) = _computeVestedForInterval(_entitled, age_before);
//            } else {
//                uint256 clear_part_share = _rangeIntervalAverage(age_before, vestingPeriod) / age_before;
//                _vested_before = uint128(_entitled * clear_part_share / SCALING_FACTOR);
//                _entitled_before = _entitled - _vested_before;
//            }
//
//            uint128 _vested_after = _entitled_before * age_after / vestingPeriod;
//            return (_vested_before + _vested_after);
//        }
//    }
//
//    function _computeVesting(
//        uint128 _amount,
//        uint128[] _rewardDebt,
//        uint256[] _accRewardPerShare,
//        uint32 _poolLastRewardTime,
//        uint32 _farmEndTime
//    ) internal view returns (uint128[], uint128[], uint32[]) {
//        uint32[] new_vesting_time = new uint32[](vestingTime.length);
//        uint128[] newly_vested = new uint128[](_rewardDebt.length);
//        uint128[] updated_entitled = new uint128[](_rewardDebt.length);
//        uint128[] new_entitled = new uint128[](_rewardDebt.length);
//
//        for (uint i = 0; i < _rewardDebt.length; i++) {
//            uint256 _reward = uint256(_amount) * _accRewardPerShare[i];
//            new_entitled[i] = uint128(_reward / SCALING_FACTOR) - _rewardDebt[i];
//            if (vestingRatio > 0) {
//                // calc which part should be payed immediately and with vesting from new reward
//                uint128 vesting_part = (new_entitled[i] * vestingRatio) / MAX_VESTING_RATIO;
//                uint128 clear_part = new_entitled[i] - vesting_part;
//
//                if (lastRewardTime < _farmEndTime || _farmEndTime == 0) {
//                    newly_vested[i] = _computeVestedForNewlyEntitled(vesting_part, _poolLastRewardTime, _farmEndTime);
//                } else {
//                    // no new entitled rewards after farm end, nothing to compute
//                    newly_vested[i] = 0;
//                }
//
//                // now calculate newly vested part of old entitled reward
//                uint32 age2 = _poolLastRewardTime >= vestingTime[i] ? vestingPeriod : _poolLastRewardTime - lastRewardTime;
//                uint256 _vested = uint256(entitled[i]) * age2;
//                uint128 to_vest = age2 >= vestingPeriod
//                ? entitled[i]
//                : uint128(_vested / (vestingTime[i] - lastRewardTime));
//
//                // amount of reward vested from now
//                uint128 remainingEntitled = entitled[i] == 0 ? 0 : entitled[i] - to_vest;
//                uint128 unreleasedNewly = vesting_part - newly_vested[i];
//                uint128 pending = remainingEntitled + unreleasedNewly;
//
//                // Compute the vesting time (i.e. when the entitled reward to be all vested)
//                if (pending == 0) {
//                    new_vesting_time[i] = _poolLastRewardTime;
//                } else if (remainingEntitled == 0) {
//                    // only new reward, set vesting time to vesting period
//                    new_vesting_time[i] = _poolLastRewardTime + vestingPeriod;
//                } else if (unreleasedNewly == 0) {
//                    // only unlocking old reward, dont change vesting time
//                    new_vesting_time[i] = vestingTime[i];
//                } else {
//                    // "old" reward and, perhaps, "new" reward are pending - the weighted average applied
//                    uint32 age3 = vestingTime[i] - _poolLastRewardTime;
//                    uint32 period = uint32(((remainingEntitled * age3) + (unreleasedNewly * vestingPeriod)) / pending);
//                    new_vesting_time[i] = _poolLastRewardTime + math.min(period, vestingPeriod);
//                }
//
//                new_vesting_time[i] = _farmEndTime > 0 ? math.min(_farmEndTime + vestingPeriod, new_vesting_time[i]) : new_vesting_time[i];
//                updated_entitled[i] = entitled[i] + vesting_part - to_vest - newly_vested[i];
//                newly_vested[i] += to_vest + clear_part;
//            } else {
//                newly_vested[i] = new_entitled[i];
//            }
//        }
//
//        return (updated_entitled, newly_vested, new_vesting_time);
//    }

}
