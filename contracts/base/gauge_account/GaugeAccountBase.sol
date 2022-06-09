pragma ever-solidity ^0.60.0;
pragma AbiHeader expire;


import "./GaugeAccountHelpers.sol";
import "../../interfaces/IGauge.sol";
import "../../interfaces/IVoteEscrow.sol";
import "../../interfaces/IVoteEscrowAccount.sol";
import "../../libraries/Errors.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


abstract contract GaugeAccountBase is GaugeAccountHelpers {
    function onDeployRetry(TvmCell, TvmCell, address sendGasTo) external view onlyGauge functionID(0x23dc4360){
        tvm.rawReserve(_reserve(), 0);
        sendGasTo.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

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
        IGauge.RewardRound[][] extra_reward_rounds,
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
        _sync_data[_nonce] = SyncData(poolLastRewardTime, lockBoostedSupply, 0, 0, extra_reward_rounds, qube_reward_rounds);
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
        IGauge.RewardRound[][] extra_reward_rounds,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 poolLastRewardTime,
        uint32 call_id,
        uint32 callback_nonce,
        address send_gas_to
    ) external override onlyGauge {
        // TODO: min gas?
        _nonce += 1;
        _claims[_nonce] = PendingClaim(call_id, callback_nonce, send_gas_to);
        _sync_data[_nonce] = SyncData(poolLastRewardTime, lockBoostedSupply, 0, 0, extra_reward_rounds, qube_reward_rounds);
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
        IGauge.RewardRound[][] extra_reward_rounds,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 poolLastRewardTime
    ) external override onlyGauge {
        // TODO: min gas?
        _nonce += 1;
        _deposits[_nonce] = PendingDeposit(deposit_nonce, amount, boosted_amount, lock_time, claim);
        _sync_data[_nonce] = SyncData(poolLastRewardTime, lockBoostedSupply, 0, 0, extra_reward_rounds, qube_reward_rounds);
        _actions[_nonce] = ActionType.Deposit;

        curAverageState.gaugeLockBoostedSupplyAverage = lockBoostedSupplyAverage;
        curAverageState.gaugeLockBoostedSupplyAveragePeriod = lockBoostedSupplyAveragePeriod;

        tvm.rawReserve(_reserve(), 0);
        IVoteEscrow(voteEscrow).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(_nonce);
    }

    function receiveVeAverage(
        uint32 nonce, uint128 veQubeBalance, uint128 veQubeAverage, uint32 veQubeAveragePeriod
    ) external override onlyVoteEscrow {
        tvm.rawReserve(_reserve(), 0);

        _sync_data[nonce].veSupply = veQubeBalance;
        curAverageState.veQubeAverage = veQubeAverage;
        curAverageState.veQubeAveragePeriod = veQubeAveragePeriod;

        IVoteEscrowAccount(veAccount).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            address(this), nonce, _sync_data[nonce].poolLastRewardTime
        );
    }

    function receiveVeAccAverage(
        uint32 nonce, uint128 veAccQube, uint128 veAccQubeAverage, uint32 veAccQubeAveragePeriod
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
            _data.extraRewardRounds[idx], extraReward[idx], extraVesting[idx], interval_lock_balance, _data.poolLastRewardTime
        );

        if (extraReward.length - 1 > idx) {
            IGaugeAccount(address(this)).updateExtraReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                nonce, interval_ve_balance, interval_lock_balance, idx + 1
            );
            return;
        }

        _finalizeAction(nonce);
    }

    function _finalizeAction(uint32 nonce) internal view {
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
}
