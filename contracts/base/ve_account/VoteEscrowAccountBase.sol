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

    function calculateMinGas() public view returns (uint128 min_gas) {
        // TODO: sync
        return activeDeposits * GAS_PER_DEPOSIT;
    }

    function _updateAverage(uint32 up_to_moment) internal {
        if (up_to_moment <= lastUpdateTime || lastUpdateTime == 0) {
            // already updated on this block or this is our first update
            lastUpdateTime = up_to_moment;
            return;
        }

        uint32 last_period = up_to_moment - lastUpdateTime;
        veQubeAverage = (veQubeAverage * veQubeAveragePeriod + veQubeBalance * last_period) / (veQubeAveragePeriod + last_period);
        veQubeAveragePeriod += last_period;
    }


    function _updateDeposits() internal returns (bool finished) {
        finished = false;
        // nothing to update
        if (activeDeposits == 0) {
            finished = true;
            return;
        }

        uint32 counter;
        // TODO: check how many deposits can be processed in 1 txn
        // get deposit with lowest unlock time
        optional(uint64, QubeDeposit) pointer = deposits.next(-1);
        uint64 cur_key;
        QubeDeposit cur_deposit;
        while (true) {
            // if we reached iteration limit, stop, we dont need gas overflow
            if (counter >= MAX_ITERATIONS_PER_MSG) {
                break;
            }
            if (pointer.hasValue()) {
                (cur_key, cur_deposit) = pointer.get();
            } else {
                // no value, we checked all deposits
                finished = true;
                break;
            }
            uint32 deposit_lock_end = cur_deposit.deposit_time + cur_deposit.lock_time;
            // no need to check further, deposits are sorted by lock time
            if (now <= deposit_lock_end) {
                finished = true;
                break;
            }

            _updateAverage(deposit_lock_end);
            // now stats are updated up to deposit_lock_end moment
            lastUpdateTime = deposit_lock_end;
            // TODO: emit event?
            veQubeBalance -= cur_deposit.ve_qube_amount;
            unlockedQubes += cur_deposit.qube_amount;
            activeDeposits -= 1;
            delete deposits[cur_key];

            counter += 1;
            pointer = deposits.next(cur_key);
        }
        return finished;
    }

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
            IVoteEscrow(msg.sender).revertDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
            return;
        }

        bool update_finished = _updateDeposits();
        // continue update in next message with same parameters
        if (!update_finished) {
            IVoteEscrowAccount(address(this)).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                deposit_nonce, qube_amount, ve_amount, lock_time, nonce, send_gas_to
            );
            return;
        }

        _updateAverage(now);
        _saveDeposit(qube_amount, ve_amount, lock_time);

        IVoteEscrow(msg.sender).finishDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, deposit_nonce);
    }
}
