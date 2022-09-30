pragma ever-solidity ^0.62.0;


import "./GaugeAccountVesting.sol";
import "../../interfaces/IGauge.sol";
import "../../../vote_escrow/interfaces/IVoteEscrow.sol";
import "../../../vote_escrow/interfaces/IVoteEscrowAccount.sol";
import "../../../libraries/Errors.sol";
import "../../../libraries/Gas.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "locklift/src/console.sol";


abstract contract GaugeAccountHelpers is GaugeAccountVesting {
    modifier onlyGauge() {
        require(msg.sender == gauge, Errors.NOT_GAUGE);
        _;
    }

    modifier onlyVoteEscrow() {
        require(msg.sender == voteEscrow, Errors.NOT_VOTE_ESCROW_2);
        _;
    }

    modifier onlyVoteEscrowAccountOrSelf() {
        require(msg.sender == veAccount || msg.sender == address(this), Errors.NOT_VOTE_ESCROW_ACCOUNT_2);
        _;
    }

    modifier onlySelf() {
        require (msg.sender == address(this), Errors.BAD_SENDER);
        _;
    }

    function _reserve() internal pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }


    function getDetails() external view responsible returns (
        address _gauge,
        address _user,
        address _voteEscrow,
        address _veAccount,
        uint32 _current_version,
        uint128 _balance,
        uint128 _lockBoostedBalance,
        uint128 _veBoostedBalance,
        uint128 _totalBoostedBalance,
        uint128 _lockedBalance,
        uint32 _lastUpdateTime,
        uint32 _lockedDepositsNum
    ) {
        return { value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS }(
            gauge,
            user,
            voteEscrow,
            veAccount,
            current_version,
            balance,
            lockBoostedBalance,
            veBoostedBalance,
            totalBoostedBalance,
            lockedBalance,
            lastUpdateTime,
            lockedDepositsNum
        );
    }

    // @dev min gas required to finalize processing of action, includes:
    // 1. min gas amount required to update this account based on number of stored deposits
    // 2. min gas amount required to send all tokens rewards
    function calculateMinGas() public view responsible returns (uint128 min_gas) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false }
            Gas.MIN_MSG_VALUE + lockedDepositsNum * Gas.GAS_PER_DEPOSIT + uint128(extraReward.length) * Gas.TOKEN_TRANSFER_VALUE;
    }

    function getAverages() external view responsible returns (Averages _lastAverageState, Averages _curAverageState) {
        return { value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS }(lastAverageState, curAverageState);
    }

    function getRewardDetails() external view responsible returns (
        RewardData _qubeReward,
        RewardData[] _extraReward,
        VestingData _qubeVesting,
        VestingData[] _extraVesting
    ) {
        return { value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS }(qubeReward, extraReward, qubeVesting, extraVesting);
    }

    function pendingReward(
        uint128 _veQubeAverage,
        uint32 _veQubeAveragePeriod,
        uint128 _veAccQubeAverage,
        uint32 _veAccQubeAveragePeriod,
        IGauge.GaugeSyncData gauge_sync_data
    ) external view returns (
        RewardData _qubeReward,
        VestingData _qubeVesting,
        RewardData[] _extraReward,
        VestingData[] _extraVesting
    ) {
        (,,, uint128 _lockBoostedBalanceAverage, uint32 _lockBoostedBalanceAveragePeriod) = calculateLockBalanceAverage();
        Averages cur_average = Averages(
            _veQubeAverage,
            _veQubeAveragePeriod,
            _veAccQubeAverage,
            _veAccQubeAveragePeriod,
            _lockBoostedBalanceAverage,
            _lockBoostedBalanceAveragePeriod,
            gauge_sync_data.depositSupplyAverage,
            gauge_sync_data.depositSupplyAveragePeriod
        );
        (uint128 intervalTBoostedBalance, uint128 intervalLockBalance) = calculateIntervalBalances(cur_average);
        (
            _qubeReward,
            _qubeVesting
        ) = calculateRewards(
            gauge_sync_data.qubeRewardRounds,
            qubeReward,
            qubeVesting,
            intervalTBoostedBalance,
            gauge_sync_data.poolLastRewardTime
        );

        _extraReward = extraReward;
        _extraVesting = extraVesting;
        for (uint i = 0; i < _extraVesting.length; i++) {
            (
                _extraReward[i],
                _extraVesting[i]
            ) = calculateRewards(
                gauge_sync_data.extraRewardRounds[i],
                _extraReward[i],
                _extraVesting[i],
                intervalLockBalance,
                gauge_sync_data.poolLastRewardTime
            );
        }
    }

    function _veBoost(uint128 ud, uint128 td, uint128 ve, uint128 tve) internal pure returns (uint128) {
        if (ve == 0 || tve == 0) {
            return (ud * 4) / 10;
        }
        // min(0.4 * Ud + 0.6 * Td * (Ve/Tve), Ud)
        return math.min(((ud * 4) / 10) + uint128(math.muldiv(((td * 6) / 10), ve, tve)), ud);
    }

    function calculateTotalBoostedBalance(
        uint128 _lockBoostedBalance,
        uint128 _gaugeDepositSupply,
        uint128 _veAccBalance,
        uint128 _veSupply
    ) public view returns (
        uint128 _veBoostedBalance,
        uint128 _totalBoostedBalance,
        uint256 _veBoostMultiplier,
        uint256 _lockBoostMultiplier,
        uint256 _totalBoostMultiplier
    ) {
        if (balance == 0) {
            return (0, 0, 0, 0, 0);
        }

        _lockBoostMultiplier = math.muldiv(_lockBoostedBalance, SCALING_FACTOR, balance);
        _veBoostedBalance = _veBoost(balance, _gaugeDepositSupply, _veAccBalance, _veSupply);
        // ve takes 0.4 of balance as base and boost it to 1.0
        _veBoostMultiplier = math.muldiv(_veBoostedBalance, SCALING_FACTOR, (balance * 4) / 10);
        _totalBoostMultiplier = _lockBoostMultiplier + _veBoostMultiplier - SCALING_FACTOR;
        _totalBoostedBalance = uint128(math.muldiv(balance, _totalBoostMultiplier, SCALING_FACTOR));
    }

    function _seriesAvg(uint128 _series_from, uint128 _series_to, uint32 time_delta) internal pure returns (uint128) {
        // when avg is ~0, we can receive small negative number because of number rounding and async vm
        return _series_to < _series_from ? 0 : ((_series_to - _series_from) / time_delta);
    }

    function calculateIntervalBalances(Averages _curAverageState) public view returns (uint128 intervalTBoostedBalance, uint128 intervalLockBalance) {
        // 0 balance during last interval, interval balance == 0 too
        if (balance == 0) {
            return (intervalTBoostedBalance, intervalLockBalance);
        }
        // calculate new veBoostedBalance
        uint32 time_delta = _curAverageState.lockBoostedBalanceAveragePeriod - lastAverageState.lockBoostedBalanceAveragePeriod;
        // no time delta, calculate using current averages
        // we check only 1 delta, because they all gathered together at the same time
        if (time_delta == 0) {
            intervalLockBalance = lockBoostedBalance;
            intervalTBoostedBalance = totalBoostedBalance;
        } else {
            // 1. Calculate average lockBoostedBalance from the moment of last action
            uint128 cur_series_sum = _curAverageState.lockBoostedBalanceAverage * _curAverageState.lockBoostedBalanceAveragePeriod;
            uint128 last_series_sum = lastAverageState.lockBoostedBalanceAverage * lastAverageState.lockBoostedBalanceAveragePeriod;
            uint128 lock_boosted_bal_avg = _seriesAvg(last_series_sum, cur_series_sum, time_delta);
            // 2. Calculate average veAcc balances
            cur_series_sum = _curAverageState.veAccQubeAverage * _curAverageState.veAccQubeAveragePeriod;
            last_series_sum = lastAverageState.veAccQubeAverage * lastAverageState.veAccQubeAveragePeriod;
            uint128 ve_acc_avg = _seriesAvg(last_series_sum, cur_series_sum, time_delta);
            // 3. Calculate average ve balances
            cur_series_sum = _curAverageState.veQubeAverage * _curAverageState.veQubeAveragePeriod;
            last_series_sum = lastAverageState.veQubeAverage * lastAverageState.veQubeAveragePeriod;
            uint128 ve_avg = _seriesAvg(last_series_sum, cur_series_sum, time_delta);
            // 4. Calculate gauge total supply average
            cur_series_sum = _curAverageState.gaugeSupplyAverage * _curAverageState.gaugeSupplyAveragePeriod;
            last_series_sum = lastAverageState.gaugeSupplyAverage * lastAverageState.gaugeSupplyAveragePeriod;
            uint128 supply_avg = _seriesAvg(last_series_sum, cur_series_sum, time_delta);
            // our average boosted balance for last interval
            uint128 ve_boosted_bal_avg = _veBoost(balance, supply_avg, ve_acc_avg, ve_avg);
            // if veBoostedBalance is bigger, it means some locked deposits/ve qubes expired and our boost decreased
            // if average boosted balance is bigger, it means we added some ve qubes, but didnt sync it
            ve_boosted_bal_avg = math.min(ve_boosted_bal_avg, veBoostedBalance);

            uint256 lock_bonus = math.muldiv(lock_boosted_bal_avg, SCALING_FACTOR, balance);
            // ve takes 0.4 of balance as base and boost it to 1.0
            uint256 ve_bonus = math.muldiv(ve_boosted_bal_avg, SCALING_FACTOR, (balance * 4) / 10);

            uint128 avg_tboosted_bal = uint128(math.muldiv(balance, lock_bonus + ve_bonus - SCALING_FACTOR, SCALING_FACTOR));
            // make sure average balance is lower than balance that we used for reward reserving in gauge
            intervalTBoostedBalance = math.min(avg_tboosted_bal, totalBoostedBalance);
            intervalLockBalance = lock_boosted_bal_avg;
        }
    }

    function calculateRewards(
        IGauge.RewardRound[] reward_rounds,
        RewardData reward_data,
        VestingData vesting_data,
        uint128 interval_balance,
        uint32 pool_last_reward_time
    ) public pure returns (RewardData, VestingData) {
        if (reward_rounds.length == 0) {
            return (reward_data, vesting_data);
        }
        uint32 first_round_start = reward_rounds[0].startTime;

        // nothing to calculate
        if (pool_last_reward_time <= first_round_start) {
            reward_data.lastRewardTime = pool_last_reward_time;
            return (reward_data, vesting_data);
        }

        // if we didnt update on this block
        if (reward_data.lastRewardTime < pool_last_reward_time) {
            if (reward_data.lastRewardTime < first_round_start) {
                reward_data.lastRewardTime = math.min(first_round_start, pool_last_reward_time);
            }

            uint32 farm_end_time = reward_rounds[reward_rounds.length - 1].endTime;
            for (uint i = reward_rounds.length - 1; i >= 0; i--) {
                if (reward_data.lastRewardTime >= reward_rounds[i].startTime) {
                    for (uint j = i; j < reward_rounds.length; j++) {
                        IGauge.RewardRound round = reward_rounds[j];
                        if (pool_last_reward_time <= round.startTime) {
                            break;
                        }

                        uint32 up_to = round.endTime == 0 ? pool_last_reward_time : round.endTime;
                        up_to = math.min(pool_last_reward_time, round.endTime);

                        // if this round is last, dont bound by round end
                        if (up_to == farm_end_time) {
                            up_to = pool_last_reward_time;
                        }

                        (
                            uint128 updated_locked,
                            uint128 new_unlocked,
                            uint32 updated_vesting_time
                        ) = _computeVesting(
                            interval_balance,
                            reward_data.lockedReward,
                            reward_data.accRewardPerShare,
                            round.accRewardPerShare,
                            up_to,
                            reward_data.lastRewardTime,
                            farm_end_time,
                            vesting_data.vestingPeriod,
                            vesting_data.vestingRatio,
                            vesting_data.vestingTime
                        );

                        reward_data.lockedReward = updated_locked;
                        reward_data.unlockedReward += new_unlocked;
                        reward_data.accRewardPerShare = round.accRewardPerShare;
                        reward_data.lastRewardTime = up_to;
                        vesting_data.vestingTime = updated_vesting_time;
                    }
                    break;
                }
            }
        }

        return (reward_data, vesting_data);
    }

    function calculateLockBalanceAverage() public view returns (
        uint128 _balance,
        uint128 _lockedBalance,
        uint128 _lockBoostedBalance,
        uint128 _lockBoostedBalanceAverage,
        uint32 _lockBoostedBalanceAveragePeriod
    ) {
        _balance = balance;
        _lockedBalance = lockedBalance;
        _lockBoostedBalance = lockBoostedBalance;
        _lockBoostedBalanceAverage = curAverageState.lockBoostedBalanceAverage;
        _lockBoostedBalanceAveragePeriod = curAverageState.lockBoostedBalanceAveragePeriod;
        uint32 _lastUpdateTime = lastUpdateTime;

        optional(uint64, DepositData) pointer = lockedDeposits.next(-1);
        uint64 cur_key;
        DepositData cur_deposit;
        while (true) {
            // if we reached iteration limit -> stop, we dont need gas overflow
            // if we checked all deposits -> stop
            if (!pointer.hasValue()) {
                break;
            }
            (cur_key, cur_deposit) = pointer.get();
            uint32 deposit_lock_end = cur_deposit.createdAt + cur_deposit.lockTime;
            // no need to check further, deposits are sorted by lock time
            if (now < deposit_lock_end) {
                break;
            }

            uint32 last_period = deposit_lock_end - _lastUpdateTime;
            // boosted balance average
            uint128 weighted_sum = _lockBoostedBalanceAverage * _lockBoostedBalanceAveragePeriod + _lockBoostedBalance * last_period;
            _lockBoostedBalanceAverage = weighted_sum / (_lockBoostedBalanceAveragePeriod + last_period);
            _lockBoostedBalanceAveragePeriod += last_period;
            _lastUpdateTime = deposit_lock_end;

            _lockBoostedBalance -= cur_deposit.boostedAmount - cur_deposit.amount;
            _lockedBalance -= cur_deposit.amount;

            pointer = lockedDeposits.next(cur_key);
        }
        if (now > _lastUpdateTime && _lastUpdateTime > 0) {
            uint32 last_period = now - _lastUpdateTime;
            uint128 weighted_sum = _lockBoostedBalanceAverage * _lockBoostedBalanceAveragePeriod + _lockBoostedBalance * last_period;
            _lockBoostedBalanceAverage = weighted_sum / (_lockBoostedBalanceAveragePeriod + last_period);
            _lockBoostedBalanceAveragePeriod += last_period;
        }
    }

    function _claimRewards() internal returns (uint128 qube_reward, uint128[] extra_rewards) {
        qube_reward = qubeReward.unlockedReward;
        qubeReward.unlockedReward = 0;

        extra_rewards = new uint128[](extraReward.length);

        for (uint i = 0; i < extraReward.length; i++) {
            extra_rewards[i] = extraReward[i].unlockedReward;
            extraReward[i].unlockedReward = 0;
        }
    }

    // @dev Store deposits in mapping using unlock time as a key so we can iterate through deposits ordered by unlock time
    function _saveDeposit(uint128 amount, uint128 boosted_amount, uint32 lock_time) internal {
        balance += amount;
        lockBoostedBalance += boosted_amount;

        if (lock_time > 0) {
            // we multiply by 100 to create 'window' for collisions,
            // so user can have up to 100 deposits with equal unlock time and they will be stored sequentially
            // without breaking sort order of keys
            // In worst case user (user has 101 deposits with unlock time N and M deposits with unlock time N + 1 and etc.)
            // user will have excess boost for 101th deposit for several seconds
            uint64 save_key = uint64(now + lock_time) * 100;
            // infinite loop is bad, but in reality it is practically impossible to make many deposits with equal unlock time
            while (lockedDeposits[save_key].amount != 0) {
                save_key++;
            }
            lockedDeposits[save_key] = DepositData(amount, boosted_amount, lock_time, now);
            lockedBalance += amount;
            lockedDepositsNum += 1;
        }
    }

    // @dev On first update just set lastUpdateTime to `up_to_moment`
    // If `up_to_moment` <= lastUpdateTime, nothing will be updated
    function _updateBalanceAverage(uint32 up_to_moment) internal {
        if (up_to_moment <= lastUpdateTime || lastUpdateTime == 0) {
            // already updated on this block or this is our first update
            lastUpdateTime = lastUpdateTime == 0 ? up_to_moment: lastUpdateTime;
            return;
        }

        uint32 last_period = up_to_moment - lastUpdateTime;
        // boosted balance average
        uint128 weighted_sum = curAverageState.lockBoostedBalanceAverage * curAverageState.lockBoostedBalanceAveragePeriod + lockBoostedBalance * last_period;
        curAverageState.lockBoostedBalanceAverage = weighted_sum / (curAverageState.lockBoostedBalanceAveragePeriod + last_period);
        curAverageState.lockBoostedBalanceAveragePeriod += last_period;
        lastUpdateTime = up_to_moment;
    }

    function _syncDeposits(uint32 sync_time) internal returns (bool finished) {
        finished = false;
        uint128 expiredLockBoostedBalance = 0;

        uint32 counter;
        // get deposit with lowest unlock time
        optional(uint64, DepositData) pointer = lockedDeposits.next(-1);
        uint64 cur_key;
        DepositData cur_deposit;
        while (true) {
            // if we reached iteration limit -> stop, we dont need gas overflow
            // if we checked all deposits -> stop
            if (counter >= MAX_ITERATIONS_PER_MSG || !pointer.hasValue()) {
                finished = !pointer.hasValue();
                break;
            }
            (cur_key, cur_deposit) = pointer.get();

            uint32 deposit_lock_end = cur_deposit.createdAt + cur_deposit.lockTime;
            // no need to check further, deposits are sorted by lock time
            if (sync_time < deposit_lock_end) {
                finished = true;
                break;
            }

            _updateBalanceAverage(deposit_lock_end);

            lockBoostedBalance -= cur_deposit.boostedAmount - cur_deposit.amount;
            lockedBalance -= cur_deposit.amount;
            expiredLockBoostedBalance += cur_deposit.boostedAmount - cur_deposit.amount;
            lockedDepositsNum -= 1;
            delete lockedDeposits[cur_key];

            counter += 1;
            pointer = lockedDeposits.next(cur_key);
        }
        if (finished) {
            _updateBalanceAverage(sync_time);
            if (expiredLockBoostedBalance > 0) {
                IGauge(gauge).burnLockBoostedBalance{value: 0.1 ever}(user, expiredLockBoostedBalance);
            }
        }
        return finished;
    }
}
