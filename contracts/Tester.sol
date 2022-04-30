pragma ton-solidity ^0.57.1;


import "locklift/locklift/console.sol";


contract Tester {
    struct QubeDeposit {
        uint128 qube_amount;
        uint128 ve_qube_amount; // expire after deposit_time + lock_time
        uint32 deposit_time; // timestamp of deposit
        uint32 lock_time; // lock interval
    }

    uint32 lastUpdateTime = 1;
    uint128 veQubeAveragePeriod = 1;
    uint128 veQubeBalance = 9999999129999999;
    uint128 veQubeAverage = 12;
    uint128 activeDeposits = 99999999999999;
    uint128 unlockedQubes;

    mapping (uint64 => QubeDeposit) deposits;
    uint32 counter = 0;
    uint128 MAX_ITERATIONS_PER_MSG = 100000;
    uint128 expiredVeQubes;

    constructor() public {
        tvm.accept();
    }

    function create(uint amount) external {
        tvm.accept();

        for (uint i = 0; i < amount; i++) {
            deposits[counter] = QubeDeposit(counter, counter, counter, counter);
            counter += 1;
        }
        console.log(format('Created {} deposits', amount));
    }

    function massCreate(uint num) external {
        tvm.accept();
        for (uint i = 0; i < num; i++) {
            Tester(address(this)).create{value: 1.1 ton, flag: 0}(100);
        }
    }

    function checkUpgrade(TvmCell new_code) external {
        tvm.accept();

        TvmCell data = abi.encode(deposits);

        tvm.setcode(new_code);
        tvm.setCurrentCode(new_code);
        migrate(data);
    }

    function migrate(TvmCell data) internal {
        (deposits) = abi.decode(data, (mapping (uint64 => QubeDeposit)));
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

    function syncDeposits(uint128 iterations) external {
        tvm.accept();

        bool finished = false;
        uint32 sync_time = 2**32 - 1;

        uint32 counter;
        // TODO: check how many deposits can be processed in 1 txn
        // get deposit with lowest unlock time
        optional(uint64, QubeDeposit) pointer = deposits.next(-1);
        uint64 cur_key;
        QubeDeposit cur_deposit;

        while (true) {
            // if we reached iteration limit -> stop, we dont need gas overflow
            // if we checked all deposits -> stop
            if (counter >= iterations || !pointer.hasValue()) {
                finished = !pointer.hasValue();
                break;
            }
            (cur_key, cur_deposit) = pointer.get();

            uint32 deposit_lock_end = cur_deposit.deposit_time + cur_deposit.lock_time;
            // no need to check further, deposits are sorted by lock time
            if (sync_time < deposit_lock_end) {
                finished = true;
                break;
            }

            _updateVeAverage(deposit_lock_end);
            // now stats are updated up to deposit_lock_end moment
            veQubeBalance -= cur_deposit.ve_qube_amount;
            expiredVeQubes += cur_deposit.ve_qube_amount;
            unlockedQubes += cur_deposit.qube_amount;
            activeDeposits -= 1;
//            delete deposits[cur_key];

            counter += 1;
            pointer = deposits.next(cur_key);
        }
        if (finished) {
            _updateVeAverage(sync_time);
//            if (expiredVeQubes > 0) {
//                IVoteEscrow(voteEscrow).burnVeQubes{value: 0.1 ton}(user, expiredVeQubes);
//                expiredVeQubes = 0;
//            }
        }
        return;
    }
}
