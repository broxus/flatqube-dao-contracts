pragma ever-solidity ^0.62.0;


import "./GaugeAccountVesting.sol";
import "../../interfaces/IGauge.sol";
import "../../../vote_escrow/interfaces/IVoteEscrow.sol";
import "../../../vote_escrow/interfaces/IVoteEscrowAccount.sol";
import "../../../libraries/Errors.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


abstract contract GaugeAccountHelpers is GaugeAccountVesting {
    function receiveVeAccAddress(address ve_acc_addr) external override onlyVoteEscrow {
        veAccount = ve_acc_addr;
    }

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

    //        // TODO: up
    //    function getDetails() external responsible view override returns (GaugeAccountDetails) {
    //        return { value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS }GaugeAccountDetails(
    //            pool_debt, entitled, vestingTime, amount, rewardDebt, farmPool, user, current_version
    //        );
    //    }

    // user_amount and user_reward_debt should be fetched from GaugeAccount at first
    //    function pendingReward(
    //        uint256[] _accRewardPerShare,
    //        uint32 poolLastRewardTime,
    //        uint32 farmEndTime
    //    ) external view returns (uint128[] _entitled, uint128[] _vested, uint128[] _pool_debt, uint32[] _vesting_time) {
    //        (
    //        _entitled,
    //        _vested,
    //        _vesting_time
    //        ) = _computeVesting(amount, rewardDebt, _accRewardPerShare, poolLastRewardTime, farmEndTime);
    //
    //        return (_entitled, _vested, pool_debt, _vesting_time);
    //    }

    function _veBoost(uint128 ud, uint128 td, uint128 ve, uint128 tve) internal pure returns (uint128) {
        if (ve == 0 || tve == 0) {
            return (ud * 4) / 10;
        }
        // min(0.4 * Ud + 0.6 * Td * (Ve/Tve), Ud)
        return math.min(((ud * 4) / 10) + uint128(math.muldiv(((td * 6) / 10), ve, tve)), ud);
    }

    function calculateTotalBoostedBalance(
        uint128 balance,
        uint128 lockBoostedBalance,
        uint128 totalSupply,
        uint128 veAccBalance,
        uint128 veSupply
    ) public pure returns (uint128 _veBoostedBalance, uint128 _totalBoostedBalance) {
        _veBoostedBalance = _veBoost(balance, totalSupply, veAccBalance, veSupply);
        uint256 lock_bonus = math.muldiv(lockBoostedBalance, SCALING_FACTOR, balance);
        // ve takes 0.4 of balance as base and boost it to 1.0
        uint256 ve_bonus = math.muldiv(_veBoostedBalance, SCALING_FACTOR, (balance * 4) / 10);
        _totalBoostedBalance = uint128(math.muldiv(balance, lock_bonus + ve_bonus - SCALING_FACTOR, SCALING_FACTOR));
    }

    function calculateIntervalBalances(
        Averages _curAverageState
    ) public view returns (uint128 intervalTBoostedBalance, uint128 intervalLockBalance) {
        // calculate new veBoostedBalance
        uint128 time_delta = _curAverageState.lockBoostedBalanceAveragePeriod - lastAverageState.lockBoostedBalanceAveragePeriod;
        // not time delta, calculate using current averages
        // we check only 1 delta, because they all gathered together at the same time
        if (time_delta == 0) {
            intervalLockBalance = lockBoostedBalance;
            intervalTBoostedBalance = totalBoostedBalance;
        } else {
            // 1. Calculate average lockBoostedBalance from the moment of last action
            uint128 cur_avg = _curAverageState.lockBoostedBalanceAverage * _curAverageState.lockBoostedBalanceAveragePeriod;
            uint128 last_avg = lastAverageState.lockBoostedBalanceAverage * lastAverageState.lockBoostedBalanceAveragePeriod;
            uint128 lock_boosted_bal_avg = (cur_avg - last_avg) / time_delta;
            // 2. Calculate average veAcc balances
            cur_avg = _curAverageState.veAccQubeAverage * _curAverageState.veAccQubeAveragePeriod;
            last_avg = lastAverageState.veAccQubeAverage * lastAverageState.veAccQubeAveragePeriod;
            uint128 ve_acc_avg = (cur_avg - last_avg) / time_delta;
            // 3. Calculate average ve balances
            cur_avg = _curAverageState.veQubeAverage * _curAverageState.veQubeAveragePeriod;
            last_avg = lastAverageState.veQubeAverage * lastAverageState.veQubeAveragePeriod;
            uint128 ve_avg = (cur_avg - last_avg) / time_delta;
            // 4. Calculate gauge total supply average
            cur_avg = _curAverageState.gaugeSupplyAverage * _curAverageState.gaugeSupplyAveragePeriod;
            last_avg = lastAverageState.gaugeSupplyAverage * lastAverageState.gaugeSupplyAveragePeriod;
            uint128 supply_avg = (cur_avg - last_avg) / time_delta;
            // our average boosted balance for last interval
            uint128 ve_boosted_bal_avg = _veBoost(balance, supply_avg, ve_acc_avg, ve_avg);
            // if veBoostedBalance is bigger, it means some locked deposits/ve qubes expired and our boost decreased
            // if average boosted balance is bigger, it means we added some ve qubes, but didnt sync it
            ve_boosted_bal_avg = math.min(ve_boosted_bal_avg, veBoostedBalance);

            uint256 lock_bonus = math.muldiv(lock_boosted_bal_avg, SCALING_FACTOR, balance);
            // ve takes 0.4 of balance as base and boost it to 1.0
            uint256 ve_bonus = math.muldiv(ve_boosted_bal_avg, SCALING_FACTOR, (balance * 4) / 10);

            intervalTBoostedBalance = uint128(math.muldiv(balance, lock_bonus + ve_bonus - SCALING_FACTOR, SCALING_FACTOR));
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

                        // qube
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
        uint128 weighted_sum = lastAverageState.lockBoostedBalanceAverage * lastAverageState.lockBoostedBalanceAveragePeriod + lockBoostedBalance * last_period;
        lastAverageState.lockBoostedBalanceAverage = weighted_sum / (lastAverageState.lockBoostedBalanceAveragePeriod + last_period);
        lastAverageState.lockBoostedBalanceAveragePeriod += last_period;
        lastUpdateTime = up_to_moment;
    }

    function _syncDeposits(uint32 sync_time) internal returns (bool finished) {
        finished = false;
        uint128 expiredLockBoostedBalance = 0;

        uint32 counter;
        // TODO: check how many deposits can be processed in 1 txn
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
                IGauge(gauge).burnBoostedBalance{value: 0.1 ever}(user, expiredLockBoostedBalance);
                expiredLockBoostedBalance = 0;
            }
        }
        return finished;
    }
}
