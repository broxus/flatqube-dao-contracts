pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./GaugeAccountVesting.sol";
import "../../interfaces/IGauge.sol";
import "../../interfaces/IVoteEscrow.sol";
import "../../interfaces/IVoteEscrowAccount.sol";
import "../../libraries/Errors.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


contract GaugeAccountBase is GaugeAccountVesting {
    function receiveVeAccAddress(address ve_acc_addr) external onlyVoteEscrow {
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

    function increasePoolDebt(uint128 qube_debt, uint128[] extra_debt, address send_gas_to) external override onlyGauge {
        tvm.rawReserve(_reserve(), 0);

        qubeReward.unlockedReward += qube_debt;
        for (uint i = 0; i < extraReward.length; i++) {
            extraReward[i].unlockedReward += extra_debt[i];
        }

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function processWithdraw(
        uint128 amount,
        bool claim,
        uint128 lockBoostedSupply,
        uint128 lockBoostedSupplyAverage,
        uint32 lockBoostedSupplyAveragePeriod,
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 poolLastRewardTime,
        uint32 call_id,
        uint32 callback_nonce,
        address send_gas_to
    ) external override onlyGauge {
        if (amount > balance) {
            IGauge(gauge).revertWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, call_id, callback_nonce, send_gas_to);
            return;
        }
        // TODO: min gas?
        _nonce += 1;
        _withdraws[_nonce] = PendingWithdraw(amount, claim, call_id, callback_nonce, send_gas_to);
        _sync_data[_nonce] = SyncData(poolLastRewardTime, lockBoostedSupply, 0, 0, extra_rewards, qube_reward_rounds);
        _actions[_nonce] = ActionType.Withdraw;

        curAverageState.gaugeLockBoostedSupplyAverage = lockBoostedSupplyAverage;
        curAverageState.gaugeLockBoostedSupplyAveragePeriod = lockBoostedSupplyAveragePeriod;

        tvm.rawReserve(_reserve(), 0);
        IVoteEscrow(voteEscrow).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(_nonce);
    }

    function processClaim(
        uint128 lockBoostedSupply,
        uint128 lockBoostedSupplyAverage,
        uint32 lockBoostedSupplyAveragePeriod,
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 poolLastRewardTime,
        uint32 call_id,
        uint32 callback_nonce,
        address send_gas_to
    ) external override onlyGauge {
        // TODO: min gas?
        _nonce += 1;
        _claims[_nonce] = PendingClaim(call_id, callback_nonce, send_gas_to);
        _sync_data[_nonce] = SyncData(poolLastRewardTime, lockBoostedSupply, 0, 0, extra_rewards, qube_reward_rounds);
        _actions[_nonce] = ActionType.Claim;

        curAverageState.gaugeLockBoostedSupplyAverage = lockBoostedSupplyAverage;
        curAverageState.gaugeLockBoostedSupplyAveragePeriod = lockBoostedSupplyAveragePeriod;

        tvm.rawReserve(_reserve(), 0);
        IVoteEscrow(voteEscrow).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(_nonce);
    }

    function processDeposit(
        uint32 deposit_nonce,
        uint128 amount,
        uint128 boosted_amount,
        uint32 lock_time,
        bool claim,
        uint128 lockBoostedSupply,
        uint128 lockBoostedSupplyAverage,
        uint32 lockBoostedSupplyAveragePeriod,
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 poolLastRewardTime
    ) external override onlyGauge {
        // TODO: min gas?
        _nonce += 1;
        _deposits[_nonce] = PendingDeposit(deposit_nonce, amount, boosted_amount, lock_time, claim);
        _sync_data[_nonce] = SyncData(poolLastRewardTime, lockBoostedSupply, 0, 0, extra_rewards, qube_reward_rounds);
        _actions[_nonce] = ActionType.Deposit;

        curAverageState.gaugeLockBoostedSupplyAverage = lockBoostedSupplyAverage;
        curAverageState.gaugeLockBoostedSupplyAveragePeriod = lockBoostedSupplyAveragePeriod;

        tvm.rawReserve(_reserve(), 0);
        IVoteEscrow(voteEscrow).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(_nonce);
    }

    function receiveVeAverage(
        uint32 nonce, uint128 veQubeSupply, uint128 veQubeAverage, uint32 veQubeAveragePeriod
    ) external override onlyVoteEscrow {
        tvm.rawReserve(_reserve(), 0);

        _sync_data[nonce].veSupply = veQubeSupply;
        curAverageState.veQubeAverage = veQubeAverage;
        curAverageState.veQubeAveragePeriod = veQubeAveragePeriod;

        IVoteEscrowAccount(veAccount).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            address(this), nonce, _sync_data[nonce].poolLastRewardTime
        );
    }

    function receiveVeAccAverage(
        uint32 nonce, uint128 veAccQube, uint128 veAccQubeAverage, uint32 veAccQubeAveragePeriod, uint32 lastUpdateTime
    ) external override onlyVoteEscrowAccountOrSelf {
        tvm.rawReserve(_reserve(), 0);

        _sync_data[nonce].veAccBalance = veAccQube;
        curAverageState.veAccQubeAverage = veAccQubeAverage;
        curAverageState.veAccQubeAveragePeriod = veAccQubeAveragePeriod;

        syncDepositsRecursive(nonce, _sync_data[_nonce].poolLastRewardTime, false);
    }

    function syncDepositsRecursive(uint32 nonce, uint32 sync_time, bool reserve) public override onlyVoteEscrowAccountOrSelf {
        if (reserve) {
            tvm.rawReserve(_reserve(), 0);
        }
        // TODO: check gas here?

        bool update_finished = _syncDeposits(sync_time);
        // continue update in next message with same parameters
        if (!update_finished) {
            IGaugeAccount(address(this)).syncDepositsRecursive{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce, sync_time, true);
            return;
        }

        (uint128 interval_ve_balance, uint128 interval_lock_balance) = calculateIntervalBalances(lastRewardAverageState);
        curAverageState = lastRewardAverageState;

        IGaugeAccount(address(this)).updateQubeReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            nonce, interval_ve_balance, interval_lock_balance
        );
    }

    function _veBoost(uint128 ud, uint128 td, uint128 ve, uint128 tve) internal pure returns (uint128) {
        // min(0.4 * Ud + 0.6 * Td * (Ve/Tve), Ud)
        return math.min(((ud * 4) / 10) + uint128(math.muldiv(((td * 6) / 10), ve, tve)), ud);
    }

    function calculateIntervalBalances(
        Averages last_avg_state
    ) public view returns (uint128 interval_ve_balance, uint128 interval_lock_balance) {
        // calculate new veBoostedBalance
        uint128 time_delta = curAverageState.lockBoostedBalanceAveragePeriod - last_avg_state.lockBoostedBalanceAveragePeriod;
        uint128 avg_ve_boosted_bal;
        // not time delta, calculate using current averages
        // we check only 1 delta, because they all gathered together at the same time
        if (time_delta == 0) {
            interval_lock_balance = lockBoostedBalance;
            interval_ve_balance = veBoostedBalance;
        } else {
            // 1. Calculate average lockBoostedBalance from the moment of last action
            uint128 cur_avg = curAverageState.lockBoostedBalanceAverage * curAverageState.lockBoostedBalanceAveragePeriod;
            uint128 last_avg = last_avg_state.lockBoostedBalanceAverage * last_avg_state.lockBoostedBalanceAveragePeriod;
            uint128 boosted_bal_avg = (cur_avg - last_avg) / time_delta;
            // 2. Calculate average veAcc balances
            cur_avg = curAverageState.veAccQubeAverage * curAverageState.veAccQubeAveragePeriod;
            last_avg = last_avg_state.veAccQubeAverage * last_avg_state.veAccQubeAveragePeriod;
            uint128 ve_acc_avg = (cur_avg - last_avg) / time_delta;
            // 3. Calculate average ve balances
            cur_avg = curAverageState.veQubeAverage * curAverageState.veQubeAveragePeriod;
            last_avg = last_avg_state.veQubeAverage * last_avg_state.veQubeAveragePeriod;
            uint128 ve_avg = (cur_avg - last_avg) / time_delta;
            // 4. Calculate average total supply
            cur_avg = curAverageState.gaugeLockBoostedSupplyAverage * curAverageState.gaugeLockBoostedSupplyAveragePeriod;
            last_avg = last_avg_state.gaugeLockBoostedSupplyAverage * last_avg_state.gaugeLockBoostedSupplyAveragePeriod;
            uint128 total_supply_avg = (cur_avg - last_avg) / time_delta;
            // our average boosted balance for last interval
            avg_ve_boosted_bal = _veBoost(boosted_bal_avg, total_supply_avg, ve_acc_avg, ve_avg);

            // if veBoostedBalance is bigger, it means some locked deposits/ve qubes expired and our boost decreased
            // if average boosted balance is bigger, it means we added some ve qubes, but didnt sync it
            interval_ve_balance = math.min(veBoostedBalance, avg_ve_boosted_bal);
            interval_lock_balance = boosted_bal_avg;
        }
    }

    function calculateRewards(
        IGauge.RewardRound[] reward_rounds,
        RewardData reward_data,
        VestingData vesting_data,
        uint128 interval_balance,
        uint32 pool_last_reward_time
    ) public view returns (RewardData, VestingData) {
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
                }
                break;
            }
        }

        return (reward_data, vesting_data);
    }

    function updateQubeReward(
        uint32 nonce, uint128 interval_ve_balance, uint128 interval_lock_balance
    ) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        SyncData _data = _sync_data[nonce];

        (
            qubeReward,
            qubeVesting
        ) = calculateRewards(_data.qubeRewardRounds, qubeReward, qubeVesting, interval_ve_balance, _data.poolLastRewardTime);

        if (extraReward.length > 0) {
            IGaugeAccount(address(this)).updateExtraReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                nonce, interval_ve_balance, interval_lock_balance, uint256(0)
            );
            return;
        }

        _finalizeAction(nonce);
    }

    function updateExtraReward(
        uint32 nonce, uint128 interval_ve_balance, uint128 interval_lock_balance, uint256 idx
    ) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        SyncData _data = _sync_data[nonce];

        (
            extraReward[idx],
            extraVesting[idx]
        ) = calculateRewards(
            _data.extraReward[idx].rewardRounds, extraReward[idx], extraVesting[idx], interval_lock_balance, _data.poolLastRewardTime
        );

        if (extraReward.length - 1 > idx) {
            IGaugeAccount(address(this)).updateExtraReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                nonce, interval_ve_balance, interval_lock_balance, idx + 1
            );
            return;
        }

        _finalizeAction(nonce);
    }

    function _finalizeAction(uint32 nonce) internal {
        if (_actions[nonce] == ActionType.Deposit) {
            IGaugeAccount(address(this)).processDeposit_final{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
        } else if (_actions[nonce] == ActionType.Withdraw) {
            IGaugeAccount(address(this)).processWithdraw_final{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
        } else if (_actions[nonce] == ActionType.Claim) {
            IGaugeAccount(address(this)).processClaim_final{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
        }
    }

    function processDeposit_final(uint32 nonce) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        SyncData _data = _sync_data[nonce];
        PendingDeposit _deposit = _deposits[nonce];

        _saveDeposit(_deposit.amount, _deposit.boostedAmount, _deposit.lockTime);
        uint128 ve_boosted_old = veBoostedBalance;
        veBoostedBalance = _veBoost(lockBoostedBalance, _data.lockBoostedSupply, _data.veAccBalance, _data.veSupply);

        delete _actions[nonce];
        delete _deposits[nonce];
        delete _sync_data[nonce];

        uint128 qube_reward;
        uint128[] extra_rewards;
        if (_deposit.claim) {
            (qube_reward, extra_rewards) = _claimRewards();
        }

        IGauge(gauge).finishDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            user, qube_reward, extra_rewards, _deposit.claim, ve_boosted_old, veBoostedBalance, _deposit.deposit_nonce
        );
    }

    function processWithdraw_final(uint32 nonce) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        SyncData _data = _sync_data[nonce];
        PendingWithdraw _withdraw = _withdraws[nonce];

        uint128 unlocked_balance = balance - lockedBalance;
        if (_withdraw.amount > balance || _withdraw.amount > unlocked_balance) {
            IGauge(gauge).revertWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                user, _withdraw.call_id, _withdraw.nonce, _withdraw.send_gas_to
            );
            return;
        }

        balance -= _withdraw.amount;
        lockBoostedBalance -= _withdraw.amount;

        uint128 ve_boosted_old = veBoostedBalance;
        veBoostedBalance = _veBoost(lockBoostedBalance, _data.lockBoostedSupply, _data.veAccBalance, _data.veSupply);

        delete _actions[nonce];
        delete _withdraws[nonce];
        delete _sync_data[nonce];

        uint128 qube_reward;
        uint128[] extra_rewards;
        if (_withdraw.claim) {
            (qube_reward, extra_rewards) = _claimRewards();
        }

        IGauge(gauge).finishWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            user, _withdraw.amount, qube_reward, extra_rewards, _withdraw.claim, ve_boosted_old,
            veBoostedBalance, _withdraw.call_id, _withdraw.nonce, _withdraw.send_gas_to
        );
    }

    function processClaim_final(uint32 nonce) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        SyncData _data = _sync_data[nonce];
        PendingClaim _claim = _claims[nonce];

        uint128 ve_boosted_old = veBoostedBalance;
        veBoostedBalance = _veBoost(lockBoostedBalance, _data.lockBoostedSupply, _data.veAccBalance, _data.veSupply);

        delete _actions[nonce];
        delete _claims[nonce];
        delete _sync_data[nonce];

        (uint128 qube_reward, uint128[] extra_rewards) = _claimRewards();

        IGauge(gauge).finishClaim{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            user, qube_reward, extra_rewards, ve_boosted_old,
            veBoostedBalance, _claim.call_id, _claim.nonce, _claim.send_gas_to
        );
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
        uint128 weighted_sum = lastRewardAverageState.lockBoostedBalanceAverage * lastRewardAverageState.lockBoostedBalanceAveragePeriod + lockBoostedBalance * last_period;
        lastRewardAverageState.lockBoostedBalanceAverage = weighted_sum / (lastRewardAverageState.lockBoostedBalanceAveragePeriod + last_period);
        lastRewardAverageState.lockBoostedBalanceAveragePeriod += last_period;
        lastUpdateTime = up_to_moment;
    }

    function _syncDeposits(uint32 sync_time) internal returns (bool finished) {
        finished = false;

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
                IGauge(gauge).burnBoostedBalance{value: 0.1 ton}(user, expiredLockBoostedBalance);
                expiredLockBoostedBalance = 0;
            }
        }
        return finished;
    }
}
