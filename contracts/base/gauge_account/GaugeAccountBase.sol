pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./GaugeAccountVesting.sol";
import "../../interfaces/IGauge.sol";
import "../../interfaces/IVoteEscrow.sol";
import "../../interfaces/IVoteEscrowAccount.sol";
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
    function pendingReward(
        uint256[] _accRewardPerShare,
        uint32 poolLastRewardTime,
        uint32 farmEndTime
    ) external view returns (uint128[] _entitled, uint128[] _vested, uint128[] _pool_debt, uint32[] _vesting_time) {
        (
        _entitled,
        _vested,
        _vesting_time
        ) = _computeVesting(amount, rewardDebt, _accRewardPerShare, poolLastRewardTime, farmEndTime);

        return (_entitled, _vested, pool_debt, _vesting_time);
    }

    function increasePoolDebt(uint128[] _pool_debt, address send_gas_to, uint32 code_version) external override {
        require(msg.sender == farmPool, NOT_FARM_POOL);
        tvm.rawReserve(_reserve(), 0);

        for (uint i = 0; i < _pool_debt.length; i++) {
            pool_debt[i] += _pool_debt[i];
        }

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function processDeposit(
        uint32 deposit_nonce,
        uint128 amount,
        uint128 boosted_amount,
        uint32 lock_time,
        uint128 lockBoostedSupply,
        uint128 lockBoostedSupplyAverage,
        uint32 lockBoostedSupplyAveragePeriod,
        IGauge.ExtraRewardData[] extra_rewards,
        IGauge.RewardRound[] qube_reward_rounds,
        uint32 poolLastRewardTime
    ) override onlyGauge {
        // TODO: min gas?
        _nonce += 1;
        _deposits[_nonce] = PendingDeposit(
            deposit_nonce, amount, boosted_amount, lock_time, extraRewards, qubeRewardRounds
        );
        _sync_data[_nonce] = SyncData(poolLastRewardTime, lockBoostedSupply, 0, 0);
        _actions[_nonce] = ActionType.Deposit;

        curAverageState.gaugeLockBoostedSupplyAverage = lockBoostedSupplyAverage;
        curAverageState.gaugeLockBoostedSupplyAveragePeriod = lockBoostedSupplyAveragePeriod;

        tvm.rawReserve(_reserve(), 0);
        IVoteEscrow(voteEscrow).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(_nonce);
    }

    function receiveVeAverage(
        uint32 nonce, uint128 veQubeSupply, uint128 veQubeAverage, uint32 veQubeAveragePeriod
    ) external onlyVoteEscrow {
        tvm.rawReserve(_reserve(), 0);

        _sync_data[nonce].veSupply = veQubeSupply;
        curAverageState.veQubeAverage = veQubeAverage;
        curAverageState.veQubeAveragePeriod = veQubeAveragePeriod;

        IVoteEscrowAccount(veAccount).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            address(this), nonce, _deposit.poolLastRewardTime
        );
    }

    function receiveVeAccAverage(
        uint32 nonce, uint128 veAccQube, uint128 veAccQubeAverage, uint32 veAccQubeAveragePeriod, uint32 lastUpdateTime
    ) external onlyVoteEscrowAccountOrSelf {
        tvm.rawReserve(_reserve(), 0);

        _sync_data[nonce].veAccBalance = veAccQube;
        curAverageState.veAccQubeAverage = veAccQubeAverage;
        curAverageState.veAccQubeAveragePeriod = veAccQubeAveragePeriod;

        syncDepositsRecursive(nonce, _action_poolLastRewardTime[_nonce], false);
    }

    function syncDepositsRecursive(uint32 nonce, uint32 sync_time, bool reserve) public onlyVoteEscrowAccountOrSelf {
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

        if (_actions[nonce] == ActionType.Deposit) {
            IGaugeAccount(address(this)).processDeposit_step1{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
            return;
        }


    }

    function processDeposit_step1(uint32 nonce) external onlySelf {
        tvm.rawReserve(_reserve(), 0);

        PendingDeposit _deposit = _deposits[nonce];
        // calculate new veBoostedBalance
        // 1. Calculate average lockBoostedBalance from the moment of last action
        uint128 cur_avg = curAverageState.lockBoostedBalanceAverage * curAverageState.lockBoostedBalanceAveragePeriod;
        uint128 last_avg = lastRewardAverageState.lockBoostedBalanceAverage * lastRewardAverageState.lockBoostedBalanceAveragePeriod;
        uint128 time_delta = curAverageState.lockBoostedBalanceAveragePeriod - lastRewardAverageState.lockBoostedBalanceAveragePeriod;
        uint128 boosted_bal_avg = (cur_avg - last_avg) / time_delta;
        // 2. Calculate average veAcc balances
        cur_avg = curAverageState.veAccQubeAverage * curAverageState.veAccQubeAveragePeriod;
        last_avg = lastRewardAverageState.veAccQubeAverage * lastRewardAverageState.veAccQubeAveragePeriod;
        uint128 ve_acc_avg = (cur_avg - last_avg) / time_delta;
        // 3. Calculate average ve balances
        cur_avg = curAverageState.veQubeAverage * curAverageState.veQubeAveragePeriod;
        last_avg = lastRewardAverageState.veQubeAverage * lastRewardAverageState.veQubeAveragePeriod;
        uint128 ve_avg = (cur_avg - last_avg) / time_delta;
        // 4. Calculate average total supply
        cur_avg = curAverageState.gaugeLockBoostedSupplyAverage * curAverageState.gaugeLockBoostedSupplyAveragePeriod;
        last_avg = lastRewardAverageState.gaugeLockBoostedSupplyAverage * lastRewardAverageState.gaugeLockBoostedSupplyAveragePeriod;
        uint128 total_supply_avg = (cur_avg - last_avg) / time_delta;
        // min(0.4 * Ud + 0.6 * Td * (Ve/Tve), Ud)
        uint128 avg_ve_boosted_bal = ((boosted_bal_avg * 4) / 10) + uint128(math.muldiv((((total_supply_avg * 6) / 10) * ve_acc_avg), ve_avg));
        avg_ve_boosted_bal = math.min(avg_ve_boosted_bal, boosted_bal_avg);

    }

    // @dev Store deposits in mapping using unlock time as a key so we can iterate through deposits ordered by unlock time
    function _saveDeposit(uint128 amount, uint128 boosted_amount, uint32 lock_time) internal {
        // we multiply by 100 to create 'window' for collisions,
        // so user can have up to 100 deposits with equal unlock time and they will be stored sequentially
        // without breaking sort order of keys
        // In worst case user (user has 101 deposits with unlock time N and M deposits with unlock time N + 1 and etc.)
        // user will have excess boost for 101th deposit for several seconds
        uint64 save_key = uint64(now + lock_time) * 100;
        // infinite loop is bad, but in reality it is practically impossible to make many deposits with equal unlock time
        while (locked_deposits[save_key].amount != 0) {
            save_key++;
        }
        locked_deposits[save_key] = DepositData(amount, boosted_amount, lock_time, now);
        balance += amount;
        lockedBalance += amount;
        lockBoostedBalance += boosted_amount;
        lockedDepositsNum += 1;
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
        uint128 weighted_sum = lockBoostedBalanceAverage * lockBoostedBalanceAveragePeriod + lockBoostedBalance * last_period;
        lockBoostedBalanceAverage = weighted_sum / (lockBoostedBalanceAveragePeriod + last_period);
        lockBoostedBalanceAveragePeriod += last_period;
        lastUpdateTime = up_to_moment;
    }

    function _syncDeposits(uint32 sync_time) internal returns (bool finished) {
        finished = false;

        uint32 counter;
        // TODO: check how many deposits can be processed in 1 txn
        // get deposit with lowest unlock time
        optional(uint64, DepositData) pointer = locked_deposits.next(-1);
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
            pointer = deposits.next(cur_key);
        }
        if (finished) {
            _updateBalanceAverage(sync_time);
            if (expiredLockBoostedBalance > 0) {
                IVoteEscrow(voteEscrow).burnBoostedBalance{value: 0.1 ton}(user, expiredLockBoostedBalance);
                expiredLockBoostedBalance = 0;
            }
        }
        return finished;
    }

    function processDeposit2(
        uint64 nonce,
        uint128 _amount,
        uint256 _qubRewardPerShare,
        uint256[] _accRewardPerShare,
        uint32 poolLastRewardTime,
        uint32[] farmEndTime,
        uint32 code_version
    ) external override {
        require(msg.sender == farmPool, NOT_FARM_POOL);
        tvm.rawReserve(_reserve(), 0);

        uint128 prevAmount = amount;
        uint128[] prevRewardDebt = rewardDebt;

        amount += _amount;
        for (uint i = 0; i < rewardDebt.length; i++) {
            uint256 _reward = amount * _accRewardPerShare[i];
            rewardDebt[i] = uint128(_reward / SCALING_FACTOR);
        }

        (
        uint128[] _entitled,
        uint128[] _vested,
        uint32[] _vestingTime
        ) = _computeVesting(prevAmount, prevRewardDebt, _accRewardPerShare, poolLastRewardTime, farmEndTime);
        entitled = _entitled;
        vestingTime = _vestingTime;
        lastRewardTime = poolLastRewardTime;

        for (uint i = 0; i < _vested.length; i++) {
            _vested[i] += pool_debt[i];
            pool_debt[i] = 0;
        }

        IGauge(msg.sender).finishDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce, _vested);
    }

    function _withdraw(uint128 _amount, uint256[] _accRewardPerShare, uint32 poolLastRewardTime, uint32 farmEndTime, address send_gas_to, uint32 nonce) internal {
        // bad input. User does not have enough staked balance. At least we can return some gas
        if (_amount > amount) {
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

        uint128 prevAmount = amount;
        uint128[] prevRewardDebt = rewardDebt;

        amount -= _amount;
        for (uint i = 0; i < _accRewardPerShare.length; i++) {
            uint256 _reward = amount * _accRewardPerShare[i];
            rewardDebt[i] = uint128(_reward / SCALING_FACTOR);
        }

        (
        uint128[] _entitled,
        uint128[] _vested,
        uint32[] _vestingTime
        ) = _computeVesting(prevAmount, prevRewardDebt, _accRewardPerShare, poolLastRewardTime, farmEndTime);
        entitled = _entitled;
        vestingTime = _vestingTime;
        lastRewardTime = poolLastRewardTime;

        for (uint i = 0; i < _vested.length; i++) {
            _vested[i] += pool_debt[i];
            pool_debt[i] = 0;
        }

        IGauge(msg.sender).finishWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, _amount, _vested, send_gas_to, nonce);
    }

    function processWithdraw(
        uint128 _amount,
        uint256[] _accRewardPerShare,
        uint32 poolLastRewardTime,
        uint32 farmEndTime,
        address send_gas_to,
        uint32 nonce,
        uint32 code_version
    ) public override {
        require (msg.sender == farmPool, NOT_FARM_POOL);
        tvm.rawReserve(_reserve(), 0);

        _withdraw(_amount, _accRewardPerShare, poolLastRewardTime, farmEndTime, send_gas_to, nonce);
    }

    function processClaimReward(uint256[] _accRewardPerShare, uint32 poolLastRewardTime, uint32 farmEndTime, address send_gas_to, uint32 nonce, uint32 code_version) external override {
        require (msg.sender == farmPool, NOT_FARM_POOL);
        tvm.rawReserve(_reserve(), 0);

        _withdraw(0, _accRewardPerShare, poolLastRewardTime, farmEndTime, send_gas_to, nonce);
    }
}
