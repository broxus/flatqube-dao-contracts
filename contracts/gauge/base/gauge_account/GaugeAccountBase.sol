pragma ever-solidity ^0.62.0;


import "./GaugeAccountHelpers.sol";
import "../../interfaces/IGauge.sol";
import "../../../vote_escrow/interfaces/IVoteEscrow.sol";
import "../../../vote_escrow/interfaces/IVoteEscrowAccount.sol";
import "../../../libraries/Errors.sol";
import "../../../libraries/Callback.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "locklift/src/console.sol";


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
        IGauge.GaugeSyncData gauge_sync_data,
        Callback.CallMeta meta
    ) external override onlyGauge {
        if (amount > balance) {
            IGauge(gauge).revertWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, meta);
            return;
        }
        // TODO: min gas?
        _nonce += 1;
        _withdraws[_nonce] = PendingWithdraw(amount, claim, meta);
        _sync_data[_nonce] = AccountSyncData(
            gauge_sync_data.poolLastRewardTime,
            gauge_sync_data.depositSupply,
            0,
            0,
            gauge_sync_data.extraRewardRounds,
            gauge_sync_data.qubeRewardRounds
        );
        _actions[_nonce] = ActionType.Withdraw;

        curAverageState.gaugeSupplyAverage = gauge_sync_data.depositSupplyAverage;
        curAverageState.gaugeSupplyAveragePeriod = gauge_sync_data.depositSupplyAveragePeriod;

        tvm.rawReserve(_reserve(), 0);
        IVoteEscrow(voteEscrow).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(_nonce);
    }

    function processClaim(IGauge.GaugeSyncData gauge_sync_data, Callback.CallMeta meta) external override onlyGauge {
        // TODO: min gas?
        _nonce += 1;
        _claims[_nonce] = PendingClaim(meta);
        _sync_data[_nonce] = AccountSyncData(
            gauge_sync_data.poolLastRewardTime,
            gauge_sync_data.depositSupply,
            0,
            0,
            gauge_sync_data.extraRewardRounds,
            gauge_sync_data.qubeRewardRounds
        );
        _actions[_nonce] = ActionType.Claim;

        curAverageState.gaugeSupplyAverage = gauge_sync_data.depositSupplyAverage;
        curAverageState.gaugeSupplyAveragePeriod = gauge_sync_data.depositSupplyAveragePeriod;

        tvm.rawReserve(_reserve(), 0);
        IVoteEscrow(voteEscrow).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(_nonce);
    }

    function processDeposit(
        uint32 deposit_nonce,
        uint128 amount,
        uint128 boostedAmount,
        uint32 lockTime,
        bool claim,
        IGauge.GaugeSyncData gauge_sync_data,
        Callback.CallMeta meta
    ) external override onlyGauge {
        // TODO: min gas?
        _nonce += 1;
        _deposits[_nonce] = PendingDeposit(deposit_nonce, amount, boostedAmount, lockTime, claim, meta);
        _sync_data[_nonce] = AccountSyncData(
            gauge_sync_data.poolLastRewardTime,
            gauge_sync_data.depositSupply,
            0,
            0,
            gauge_sync_data.extraRewardRounds,
            gauge_sync_data.qubeRewardRounds
        );
        _actions[_nonce] = ActionType.Deposit;

        curAverageState.gaugeSupplyAverage = gauge_sync_data.depositSupplyAverage;
        curAverageState.gaugeSupplyAveragePeriod = gauge_sync_data.depositSupplyAveragePeriod;

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

    function syncDepositsRecursive(uint32 nonce, uint32 syncTime, bool reserve) public override onlyVoteEscrowAccountOrSelf {
        if (reserve) {
            tvm.rawReserve(_reserve(), 0);
        }
        // TODO: check gas here?

        bool update_finished = _syncDeposits(syncTime);
        // continue update in next message with same parameters
        if (!update_finished) {
            IGaugeAccount(address(this)).syncDepositsRecursive{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce, syncTime, true);
            return;
        }

        (uint128 intervalTBoostedBalance, uint128 intervalLockBalance) = calculateIntervalBalances(curAverageState);
        lastAverageState = curAverageState;

        IGaugeAccount(address(this)).updateQubeReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            nonce, intervalTBoostedBalance, intervalLockBalance
        );
    }

    function updateQubeReward(
        uint32 nonce, uint128 intervalTBoostedBalance, uint128 intervalLockBalance
    ) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        AccountSyncData _data = _sync_data[nonce];

        (
            qubeReward,
            qubeVesting
        ) = calculateRewards(_data.qubeRewardRounds, qubeReward, qubeVesting, intervalTBoostedBalance, _data.poolLastRewardTime);

        if (extraReward.length > 0) {
            IGaugeAccount(address(this)).updateExtraReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                nonce, intervalTBoostedBalance, intervalLockBalance, uint256(0)
            );
            return;
        }

        _finalizeAction(nonce);
    }

    function updateExtraReward(
        uint32 nonce, uint128 intervalTBoostedBalance, uint128 intervalLockBalance, uint256 idx
    ) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        AccountSyncData _data = _sync_data[nonce];

        (
            extraReward[idx],
            extraVesting[idx]
        ) = calculateRewards(
            _data.extraRewardRounds[idx], extraReward[idx], extraVesting[idx], intervalLockBalance, _data.poolLastRewardTime
        );

        if (extraReward.length - 1 > idx) {
            IGaugeAccount(address(this)).updateExtraReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                nonce, intervalTBoostedBalance, intervalLockBalance, idx + 1
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

        AccountSyncData _data = _sync_data[nonce];
        PendingDeposit _deposit = _deposits[nonce];

        _saveDeposit(_deposit.amount, _deposit.boostedAmount, _deposit.lockTime);

        uint128 totalBoostedOld = totalBoostedBalance;
        (veBoostedBalance, totalBoostedBalance,,,) = calculateTotalBoostedBalance(
            lockBoostedBalance, _data.gaugeDepositSupply, _data.veAccBalance, _data.veSupply
        );

        delete _actions[nonce];
        delete _deposits[nonce];
        delete _sync_data[nonce];

        uint128 qube_reward;
        uint128[] extra_rewards;
        if (_deposit.claim) {
            (qube_reward, extra_rewards) = _claimRewards();
        }

        IGauge(gauge).finishDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            user, qube_reward, extra_rewards, _deposit.claim, totalBoostedOld, totalBoostedBalance, _deposit.deposit_nonce
        );
    }

    function processWithdraw_final(uint32 nonce) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        AccountSyncData _data = _sync_data[nonce];
        PendingWithdraw _withdraw = _withdraws[nonce];

        uint128 unlocked_balance = balance - lockedBalance;
        if (_withdraw.amount > balance || _withdraw.amount > unlocked_balance) {
            IGauge(gauge).revertWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, _withdraw.meta);
            return;
        }

        balance -= _withdraw.amount;
        lockBoostedBalance -= _withdraw.amount;

        uint128 totalBoostedOld = totalBoostedBalance;
        (veBoostedBalance, totalBoostedBalance,,,) = calculateTotalBoostedBalance(
            lockBoostedBalance, _data.gaugeDepositSupply, _data.veAccBalance, _data.veSupply
        );

        delete _actions[nonce];
        delete _withdraws[nonce];
        delete _sync_data[nonce];

        uint128 qube_reward;
        uint128[] extra_rewards;
        if (_withdraw.claim) {
            (qube_reward, extra_rewards) = _claimRewards();
        }

        IGauge(gauge).finishWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            user, _withdraw.amount, qube_reward, extra_rewards, _withdraw.claim,
            totalBoostedOld, totalBoostedBalance, _withdraw.meta
        );
    }

    function processClaim_final(uint32 nonce) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        AccountSyncData _data = _sync_data[nonce];
        PendingClaim _claim = _claims[nonce];

        uint128 totalBoostedOld = totalBoostedBalance;
        (veBoostedBalance, totalBoostedBalance,,,) = calculateTotalBoostedBalance(
            lockBoostedBalance, _data.gaugeDepositSupply, _data.veAccBalance, _data.veSupply
        );

        delete _actions[nonce];
        delete _claims[nonce];
        delete _sync_data[nonce];

        (uint128 qube_reward, uint128[] extra_rewards) = _claimRewards();

        IGauge(gauge).finishClaim{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            user, qube_reward, extra_rewards, totalBoostedOld, totalBoostedBalance, _claim.meta
        );
    }
}
