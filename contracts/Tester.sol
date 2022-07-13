//pragma ever-solidity ^0.60.0;
//
//
//import "locklift/locklift/console.sol";
//import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
//import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
//
//
//contract Tester {
//    struct QubeDeposit {
//        uint128 qube_amount;
//        uint128 ve_qube_amount; // expire after deposit_time + lock_time
//        uint32 deposit_time; // timestamp of deposit
//        uint32 lock_time; // lock interval
//    }
//
//    uint32 lastUpdateTime = 1;
//    uint128 veQubeAveragePeriod = 1;
//    uint128 veQubeBalance = 9999999129999999;
//    uint128 veQubeAverage = 12;
//    uint128 activeDeposits = 99999999999999;
//    uint128 unlockedQubes;
//    uint128 gaugesNum = 99999;
//    mapping (address => uint128) currentVotingVotes;
//    mapping (address => uint128) gaugeDowntime;
//    mapping (address => bool) whitelistedGauges;
//
//    event GaugeRemoveWhitelist(uint32 call_id, address gauge);
//
//    event VotingEnded(mapping (address => uint128) votes);
//
//    QubeDeposit[][] double_array;
//
//    mapping (uint64 => QubeDeposit) deposits;
//    uint32 counter = 0;
//    uint128 MAX_ITERATIONS_PER_MSG = 100000;
//    uint128 expiredVeQubes;
//
//    constructor() public {
//        tvm.accept();
//    }
//
//    function double_arr() external {
//        QubeDeposit[] _tmp = new QubeDeposit[](10);
//        double_array.push(_tmp);
//    }
//
//    function testAbi() external {
//        tvm.accept();
//
//        TvmBuilder builder;
//
//        uint32 call_id;
//        uint32 nonce;
//        uint128 qubeBalance = 123;
//        TvmCell storage_data = abi.encode(
//            qubeBalance,
//            qubeBalance,
//            qubeBalance,
//            qubeBalance,
//            qubeBalance,
//            qubeBalance,
//            qubeBalance,
//            qubeBalance,
//            qubeBalance,
//            qubeBalance
//        );
//        TvmCell data = abi.encode(call_id, nonce, storage_data);
//
//        TvmCell empty;
//        builder.storeRef(empty);
//        builder.storeRef(empty);
//        builder.storeRef(empty);
//
//        builder.storeRef(data);
//
//        TvmSlice builder_slice = builder.toCell().toSlice();
//
//        builder_slice.loadRef();
//        builder_slice.loadRef();
//        builder_slice.loadRef();
//
//        TvmCell unpacked = builder_slice.loadRef();
//        (uint32 one, uint32 two, TvmCell three) = abi.decode(unpacked, (uint32, uint32, TvmCell));
//    }
//
//    function create(uint amount) external {
//        tvm.accept();
//
//        for (uint i = 0; i < amount; i++) {
//            deposits[counter] = QubeDeposit(counter, counter, counter, counter);
//            counter += 1;
//        }
//        console.log(format('Created {} deposits', amount));
//    }
//
//    function massCreate(uint num) external {
//        tvm.accept();
//        for (uint i = 0; i < num; i++) {
//            Tester(address(this)).create{value: 1.1 ton, flag: 0}(100);
//        }
//    }
//
//    function checkUpgrade(TvmCell new_code) external {
//        tvm.accept();
//
//        TvmCell data = abi.encode(deposits);
//        (uint16 bits, uint8 refs) = data.toSlice().size();
//        console.log(format('Bits: {}, refs: {}', bits, refs));
//
//        tvm.setcode(new_code);
//        tvm.setCurrentCode(new_code);
//        migrate(data);
//    }
//
//    function migrate(TvmCell data) internal {
//        (deposits) = abi.decode(data, (mapping (uint64 => QubeDeposit)));
//
//        QubeDeposit one = deposits[0];
//        QubeDeposit two = deposits[1];
//        QubeDeposit three = deposits[2];
//
//        console.log(format('1 - {}, 2 - {}, 3 - {}', one.qube_amount, two.qube_amount, three.qube_amount));
//
//        (uint16 bits, uint8 refs) = data.toSlice().size();
//        console.log(format('Bits: {}, refs: {}', bits, refs));
//    }
//
//    function createVotes(uint128 number) external {
//        tvm.accept();
//
//        for (uint i = 0; i < number; i++) {
//            counter += 1;
//            address new_addr = address.makeAddrStd(0, counter);
//            currentVotingVotes[new_addr] = counter;
//        }
//    }
//
//    function _transferTokens(
//        address token_wallet, uint128 amount, address receiver, TvmCell payload, address send_gas_to, uint16 flag
//    ) internal pure {
//        uint128 value;
//        if (flag != MsgFlag.ALL_NOT_RESERVED) {
//            value = 0.7 ton;
//        }
//        bool notify = false;
//        // notify = true if payload is non-empty
//        TvmSlice slice = payload.toSlice();
//        if (slice.bits() > 0 || slice.refs() > 0) {
//            notify = true;
//        }
//        ITokenWallet(token_wallet).transfer{value: value, flag: flag}(
//            amount,
//            receiver,
//            0,
//            send_gas_to,
//            notify,
//            payload
//        );
//    }
//
//    function _removeFromWhitelist(address gauge, uint32 call_id) internal {
//        gaugesNum -= 1;
//        whitelistedGauges[gauge] = false;
//        emit GaugeRemoveWhitelist(call_id, gauge);
//    }
//
//    function endVoting() external {
//        tvm.accept();
//
//
//        optional(address, uint128) start = currentVotingVotes.next(address.makeAddrStd(address(this).wid, 0));
//        (address start_addr,) = start.get();
//
//        bool finished;
//        uint32 counter;
//        uint128 qqq;
//
//        optional(address, uint128) pointer = currentVotingVotes.nextOrEq(start_addr);
//        while (true) {
//            if (!pointer.hasValue()) {
//                finished = true;
//                break;
//            }
//
//            (address gauge, uint128 gauge_votes) = pointer.get();
//            if (gauge_votes > 1) {
//                qqq += gauge_votes;
//                gaugeDowntime[gauge] += 1;
////                if (gaugeDowntime[gauge] >= 0) {
////                    _removeFromWhitelist(gauge, 0);
////                }
//                currentVotingVotes[gauge] += 1;
//            }
//
//            counter += 1;
//            pointer = currentVotingVotes.next(gauge);
//        }
//
//
////        uint128 qqq;
////        for ((address gauge, uint128 gauge_votes) : currentVotingVotes) {
////            if (gauge_votes > 1) {
////                qqq += gauge_votes;
////                gaugeDowntime[gauge] += 1;
////                if (gaugeDowntime[gauge] >= 0) {
////                    _removeFromWhitelist(gauge, 0);
////                }
////                currentVotingVotes[gauge] += 1;
////            }
////        }
//////
////        for ((address gauge, uint128 gauge_votes) : currentVotingVotes) {
////            if (gauge_votes > 1) {
////                uint128 bonus_votes = math.muldiv(gauge_votes, gauge_votes, gauge_votes);
////                qqq += gauge_votes;
////                if (gaugeDowntime[gauge] >= 0) {
////                    qqq += gauge_votes;
////                    gaugeDowntime[gauge] += 1;
////                }
////            }
////        }
//
////        emit VotingEnded(currentVotingVotes);
////
////        TvmBuilder builder;
////        uint32 epochTime = 1;
////        builder.store(epochTime);
////        TvmCell payload = builder.toCell();
////        mapping (address => uint128) distributed;
////        for ((address gauge, uint128 gauge_votes): currentVotingVotes) {
////            uint128 qube_amount = math.muldiv(gauge_votes, gauge_votes, gauge_votes);
////            distributed[gauge] = qube_amount;
////            _transferTokens(gauge, qube_amount, gauge, payload, gauge, MsgFlag.SENDER_PAYS_FEES);
////        }
////
////        emit VotingEnded(distributed);
////
////        delete currentVotingVotes;
//    }
//
//
//
//
//    function _updateVeAverage(uint32 up_to_moment) internal {
//        if (up_to_moment <= lastUpdateTime || lastUpdateTime == 0) {
//            // already updated on this block or this is our first update
//            lastUpdateTime = lastUpdateTime == 0 ? up_to_moment: lastUpdateTime;
//            return;
//        }
//
//        uint32 last_period = up_to_moment - lastUpdateTime;
//        veQubeAverage = (veQubeAverage * veQubeAveragePeriod + veQubeBalance * last_period) / (veQubeAveragePeriod + last_period);
//        veQubeAveragePeriod += last_period;
//        lastUpdateTime = up_to_moment;
//    }
//
//    function syncDeposits(uint128 iterations) external {
//        tvm.accept();
//
//        bool finished = false;
//        uint32 sync_time = 2**32 - 1;
//
//        uint32 counter;
//        // TODO: check how many deposits can be processed in 1 txn
//        // get deposit with lowest unlock time
//        optional(uint64, QubeDeposit) pointer = deposits.next(-1);
//        uint64 cur_key;
//        QubeDeposit cur_deposit;
//
//        while (true) {
//            // if we reached iteration limit -> stop, we dont need gas overflow
//            // if we checked all deposits -> stop
//            if (counter >= iterations || !pointer.hasValue()) {
//                finished = !pointer.hasValue();
//                break;
//            }
//            (cur_key, cur_deposit) = pointer.get();
//
//            uint32 deposit_lock_end = cur_deposit.deposit_time + cur_deposit.lock_time;
//            // no need to check further, deposits are sorted by lock time
//            if (sync_time < deposit_lock_end) {
//                finished = true;
//                break;
//            }
//
//            _updateVeAverage(deposit_lock_end);
//            // now stats are updated up to deposit_lock_end moment
//            veQubeBalance -= cur_deposit.ve_qube_amount;
//            expiredVeQubes += cur_deposit.ve_qube_amount;
//            unlockedQubes += cur_deposit.qube_amount;
//            activeDeposits -= 1;
////            delete deposits[cur_key];
//
//            counter += 1;
//            pointer = deposits.next(cur_key);
//        }
//        if (finished) {
//            _updateVeAverage(sync_time);
////            if (expiredVeQubes > 0) {
////                IVoteEscrow(voteEscrow).burnVeQubes{value: 0.1 ton}(user, expiredVeQubes);
////                expiredVeQubes = 0;
////            }
//        }
//        return;
//    }
//}
