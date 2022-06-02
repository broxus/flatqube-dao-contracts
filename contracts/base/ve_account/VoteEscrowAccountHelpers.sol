pragma ton-solidity ^0.57.1;


import "./VoteEscrowAccountStorage.sol";
import "../../libraries/Gas.sol";
import "../../libraries/Errors.sol";
import "../../interfaces/IVoteEscrow.sol";
import "../../interfaces/IVoteEscrowAccount.sol";
import "../../interfaces/IGaugeAccount.sol";

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


abstract contract VoteEscrowAccountHelpers is VoteEscrowAccountStorage {
    function getDetails() external view responsible returns (
        uint32 _current_version,
        address _voteEscrow,
        address _user,
        uint128 _qubeBalance, // total amount of deposited qubes
        uint128 _veQubeBalance, // current ve balance
        uint128 _expiredVeQubes, // expired ve qubes that should be withdrawn from vote escrow contract
        uint128 _unlockedQubes, // qubes with expired lock, that can be withdraw
        uint128 _veQubeAverage,
        uint32 _veQubeAveragePeriod,
        uint32 _lastUpdateTime,
        uint32 _lastEpochVoted, // number of last epoch when user voted
        uint32 _activeDeposits
    ) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false }(
            current_version,
            voteEscrow,
            user,
            qubeBalance, // total amount of deposited qubes
            veQubeBalance, // current ve balance
            expiredVeQubes, // expired ve qubes that should be withdrawn from vote escrow contract
            unlockedQubes, // qubes with expired lock, that can be withdraw
            veQubeAverage,
            veQubeAveragePeriod,
            lastUpdateTime,
            lastEpochVoted, // number of last epoch when user voted
            activeDeposits
        );
    }

    function getDeposits() external view responsible returns (mapping (uint64 => QubeDeposit) _deposits) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } deposits;
    }

    function _reserve() internal pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }

    modifier onlyVoteEscrowOrSelf() {
        require(msg.sender == voteEscrow || msg.sender == address(this), Errors.NOT_VOTE_ESCROW);
        _;
    }

    // min gas amount required to update this account based on number of stored deposits
    function calculateMinGas() public view responsible returns (uint128 min_gas) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } Gas.MIN_MSG_VALUE + activeDeposits * Gas.GAS_PER_DEPOSIT;
    }

    // @dev On first update just set lastUpdateTime to `up_to_moment`
    // If `up_to_moment` <= lastUpdateTime, nothing will be updated
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

    // Iterate through all qube deposits and check if any of them is expired
    // @dev 1. Deposits are ordered by unlock time, so we can stop iteration when reached deposit that is still locked
    // 2. VE stats updated on every iteration up to deposit unlock time to get maximum precision
    // 3. Iterations are limited by constant to avoid gas overflow
    // @param sync_time - timestamp. Update deposits up to this moment
    // @return finished - indicate if we checked all required deposits up to this moment
    function _syncDeposits(uint32 sync_time) internal returns (bool finished) {
        finished = false;

        uint32 counter;
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

            uint32 deposit_lock_end = cur_deposit.createdAt + cur_deposit.lockTime;
            // no need to check further, deposits are sorted by lock time
            if (sync_time < deposit_lock_end) {
                finished = true;
                break;
            }

            _updateVeAverage(deposit_lock_end);
            // now stats are updated up to deposit_lock_end moment
            veQubeBalance -= cur_deposit.veAmount;
            expiredVeQubes += cur_deposit.veAmount;
            unlockedQubes += cur_deposit.amount;
            activeDeposits -= 1;
            delete deposits[cur_key];

            counter += 1;
            pointer = deposits.next(cur_key);
        }
        if (finished) {
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
        // In worst case user (user has 101 deposits with unlock time N and M deposits with unlock time N + 1 and etc.)
        // user will have excess boost for 101th deposit for several seconds
        uint64 save_key = uint64(now + lock_time) * 100;
        // infinite loop is bad, but in reality it is practically impossible to make many deposits with equal unlock time
        while (deposits[save_key].amount != 0) {
            save_key++;
        }
        deposits[save_key] = QubeDeposit(qube_amount, ve_amount, now, lock_time);
        veQubeBalance += ve_amount;
        qubeBalance += qube_amount;
        activeDeposits += 1;
    }

    // view function for getting actual ve stats without modifying data on given time point
    // @dev If sync_time <= lastUpdateTime, will just return values stored on contract
    function calculateVeAverage(uint32 sync_time) external view returns (uint128 _veQubeAverage, uint128 _veQubeAveragePeriod) {
        _veQubeAverage = veQubeAverage;
        _veQubeAveragePeriod = veQubeAveragePeriod;
        uint32 _lastUpdateTime = lastUpdateTime;
        uint128 _veQubeBalance = veQubeBalance;

        optional(uint64, QubeDeposit) pointer = deposits.next(-1);
        uint64 cur_key;
        QubeDeposit cur_deposit;
        while (true) {
            if (!pointer.hasValue()) {
                break;
            }
            (cur_key, cur_deposit) = pointer.get();

            uint32 deposit_lock_end = cur_deposit.createdAt + cur_deposit.lockTime;
            // no need to check further, deposits are sorted by lock time
            if (sync_time < deposit_lock_end) {
                break;
            }

            uint32 last_period = deposit_lock_end - _lastUpdateTime;
            _veQubeAverage = (_veQubeAverage * _veQubeAveragePeriod + _veQubeBalance * last_period) / (_veQubeAveragePeriod + last_period);
            _veQubeAveragePeriod += last_period;
            _lastUpdateTime = deposit_lock_end;
            _veQubeBalance -= cur_deposit.veAmount;

            pointer = deposits.next(cur_key);
        }
        if (sync_time > _lastUpdateTime && _lastUpdateTime > 0) {
            uint32 last_period = sync_time - _lastUpdateTime;
            _veQubeAverage = (_veQubeAverage * _veQubeAveragePeriod + _veQubeBalance * last_period) / (_veQubeAveragePeriod + last_period);
            _veQubeAveragePeriod += last_period;
        }
    }
}
