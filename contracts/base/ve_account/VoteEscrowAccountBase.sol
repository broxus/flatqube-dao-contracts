pragma ton-solidity ^0.57.1;


import "./VoteEscrowAccountStorage.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


abstract contract VoteEscrowAccountBase is VoteEscrowAccountStorage {
    function _reserve() internal pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }

    modifier onlyVoteEscrowOrSelf() {
        require(msg.sender == voteEscrow || msg.sender == address(this), NOT_VOTE_ESCROW);
        _;
    }

    // min gas amount required to update this account based on number of stored deposits
    function calculateMinGas() public view responsible returns (uint128 min_gas) {
        // TODO: sync?
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } activeDeposits * GAS_PER_DEPOSIT;
    }

    function _updateVeAverage(uint32 up_to_moment) internal {
        if (up_to_moment <= lastUpdateTime || lastUpdateTime == 0) {
            // already updated on this block or this is our first update
            lastUpdateTime = lastUpdateTime == 0 ? up_to_moment: lastUpdateTime;
            return;
        }

        uint32 last_period = up_to_moment - lastUpdateTime;
        veQubeAverage = (veQubeAverage * veQubeAveragePeriod + veQubeBalance * last_period) / (veQubeAveragePeriod + last_period);
        veQubeAveragePeriod += last_period;
        lastUpdateTime = up_to_moment;
    }


    // @dev Iterate through all qube deposits and check if any of them is expired
    // Deposits are ordered by unlock time, so we can stop iteration when reached deposit that is still locked
    // Iterations are limited by constant to avoid gas overflow
    // @param sync_time - timestamp. Update deposits up to this moment
    // @return finished - indicate if we checked all required deposits up to this moment
    function _syncDeposits(uint32 sync_time) internal returns (bool finished) {
        finished = false;

        uint32 counter;
        // TODO: check how many deposits can be processed in 1 txn
        // get deposit with lowest unlock time
        optional(uint64, QubeDeposit) pointer = deposits.next(-1);
        uint64 cur_key;
        QubeDeposit cur_deposit;
        while (true) {
            // if we reached iteration limit -> stop, we dont need gas overflow
            // if we checked all deposits -> stop
            if (counter >= MAX_ITERATIONS_PER_MSG || !pointer.hasValue()) {
                finished = !pointer.hasValue();
                break;
            }
            (cur_key, cur_deposit) = pointer.get();

            uint32 deposit_lock_end = cur_deposit.deposit_time + cur_deposit.lock_time;
            // no need to check further, deposits are sorted by lock time
            if (sync_time <= deposit_lock_end) {
                finished = true;
                break;
            }

            _updateVeAverage(deposit_lock_end);
            // now stats are updated up to deposit_lock_end moment
            // TODO: emit event?
            veQubeBalance -= cur_deposit.ve_qube_amount;
            expiredVeQubes += cur_deposit.ve_qube_amount;
            unlockedQubes += cur_deposit.qube_amount;
            activeDeposits -= 1;
            delete deposits[cur_key];

            counter += 1;
            pointer = deposits.next(cur_key);
        }
        if (finished || activeDeposits == 0) {
            _updateVeAverage(sync_time);
            if (expiredVeQubes > 0) {
                IVoteEscrow(voteEscrow).burnVeQubes{value: 0.1 ton}(user, expiredVeQubes);
                expiredVeQubes = 0;
            }
        }
        return finished;
    }

    // @dev Store deposits in mapping using unlock time as a key so we can iterate through deposits ordered by unlock time
    function _saveDeposit(uint128 qube_amount, uint128 ve_amount, uint32 lock_time) internal {
        // we multiply by 100 to create 'window' for collisions,
        // so user can have up to 100 deposits with equal unlock time and they will be stored sequentially
        // without breaking sort order of keys
        // In worst case user (user has 101 deposits with unlock time N and M deposits with unlock time N + 1)
        // user will have excess boost for 101th deposit for M seconds
        uint64 save_key = uint64(now + lock_time) * 100;
        // infinite loop is bad, but in reality it is practically impossible to make many deposits with equal unlock time
        while (deposits[save_key].qube_amount != 0) {
            save_key++;
        }
        deposits[save_key] = QubeDeposit(qube_amount, ve_amount, lock_time);
        veQubeBalance += ve_amount;
        qubeBalance += qube_amount;
        activeDeposits += 1;
    }

    function processDeposit(
        uint32 deposit_nonce,
        uint128 qube_amount,
        uint128 ve_amount,
        uint32 lock_time,
        uint32 nonce,
        address send_gas_to
    ) external onlyVoteEscrowOrSelf {
        tvm.rawReserve(_reserve(), 0);

        // check gas only at beginning
        if (msg.sender == voteEscrow && msg.value < calculateMinGas()) {
            IVoteEscrow(msg.sender).revertDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, deposit_nonce);
            return;
        }

        bool update_finished = _syncDeposits(now);
        // continue update in next message with same parameters
        if (!update_finished) {
            IVoteEscrowAccount(address(this)).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                deposit_nonce, qube_amount, ve_amount, lock_time, nonce, send_gas_to
            );
            return;
        }

        _saveDeposit(qube_amount, ve_amount, lock_time);
        IVoteEscrow(voteEscrow).finishDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, deposit_nonce);
    }

    // Update averages up to current moment taking into account expired deposits
    // @dev attach gas >= calculateMinGas(), otherwise call may fail
    // @param callback_receiver - address that will receive callback
    // @param callback_nonce - nonce that will be sent with callback
    // @param sync_time - timestamp. Ve stats will be updated up to this moment
    function getVeAverage(address callback_receiver, uint32 callback_nonce, uint32 sync_time) external {
        require (msg.sender == address(this) || msg.sender == callback_receiver, Errors.BAD_SENDER);
        tvm.rawReserve(_reserve(), 0);

        // update ve stats before sending callback
        bool update_finished = _syncDeposits(sync_time);
        // continue update in next message with same parameters
        if (!update_finished) {
            IVoteEscrowAccount(address(this)).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                callback_receiver, callback_payload
            );
            return;
        }
        IGaugeAccount(callback_receiver).receiveVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            callback_nonce, veQubeAverage, veQubeAveragePeriod, lastUpdateTime
        );
    }

    // view function for getting actual ve stats without modifying data
    function calculateVeAverage(uint32 sync_time) external view returns (uint128 _veQubeAverage, uint128 _veQubeAveragePeriod) {
        _veQubeAverage = veQubeAverage;
        _veQubeAveragePeriod = veQubeAveragePeriod;
        _lastUpdateTime = lastUpdateTime;
        _veQubeBalance = veQubeBalance;

        optional(uint64, QubeDeposit) pointer = deposits.next(-1);
        uint64 cur_key;
        QubeDeposit cur_deposit;
        while (true) {
            if (!pointer.hasValue()) {
                break;
            }
            (cur_key, cur_deposit) = pointer.get();

            uint32 deposit_lock_end = cur_deposit.deposit_time + cur_deposit.lock_time;
            // no need to check further, deposits are sorted by lock time
            if (sync_time <= deposit_lock_end) {
                break;
            }

            if (deposit_lock_end <= _lastUpdateTime || _lastUpdateTime == 0) {
                // already updated on this block or this is our first update
                _lastUpdateTime = deposit_lock_end;
            } else {
                uint32 last_period = deposit_lock_end - _lastUpdateTime;
                _veQubeAverage = (_veQubeAverage * _veQubeAveragePeriod + _veQubeBalance * last_period) / (_veQubeAveragePeriod + last_period);
                _veQubeAveragePeriod += last_period;
                _lastUpdateTime = deposit_lock_end;
            }
            _veQubeBalance -= cur_deposit.ve_qube_amount;
            pointer = deposits.next(cur_key);
        }
        if (sync_time > _lastUpdateTime && _lastUpdateTime > 0) {
            uint32 last_period = sync_time - _lastUpdateTime;
            _veQubeAverage = (_veQubeAverage * _veQubeAveragePeriod + _veQubeBalance * last_period) / (_veQubeAveragePeriod + last_period);
            _veQubeAveragePeriod += last_period;
        }
    }
}
