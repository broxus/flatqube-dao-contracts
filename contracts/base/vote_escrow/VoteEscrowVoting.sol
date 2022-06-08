pragma ton-solidity ^0.60.0;
pragma AbiHeader expire;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "./VoteEscrowUpgradable.sol";
import "../../interfaces/IVoteEscrowAccount.sol";


abstract contract VoteEscrowVoting is VoteEscrowUpgradable {
    function initialize(uint32 start_time, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        // codes installed
        require (start_time > now, Errors.CANT_BE_INITIALIZED);
        require (!platformCode.toSlice().empty(), Errors.CANT_BE_INITIALIZED);
        require (!veAccountCode.toSlice().empty(), Errors.CANT_BE_INITIALIZED);
        // distribution params
        require (distributionSchedule.length > 0, Errors.CANT_BE_INITIALIZED);
        require (distributionScheme.length > 0, Errors.CANT_BE_INITIALIZED);
        // people can but whitelist
        require (gaugeWhitelistPrice > 0, Errors.CANT_BE_INITIALIZED);
        // voting params were installed
        require (epochTime > 0 && timeBeforeVoting > 0 && votingTime > 0, Errors.CANT_BE_INITIALIZED);
        // additional voting params
        require (gaugeMaxVotesRatio > 0 && maxGaugesPerVote > 0, Errors.CANT_BE_INITIALIZED);
        require (!initialized, Errors.ALREADY_INITIALIZED);

        tvm.rawReserve(_reserve(), 0);
        currentEpochStartTime = start_time;
        currentEpochEndTime = start_time + epochTime;
        currentEpoch = 1;
        initialized = true;

        emit Initialize(now, start_time, currentEpochEndTime);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setVotingParams(
        uint32 _epoch_time,
        uint32 _time_before_voting,
        uint32 _voting_time,
        uint32 _gauge_min_votes_ratio,
        uint32 _gauge_max_votes_ratio,
        uint8 _gauge_max_downtime,
        uint32 _max_gauges_per_vote,
        uint32 call_id,
        address send_gas_to
    ) external onlyOwner {
        require (_gauge_min_votes_ratio < _gauge_max_votes_ratio, Errors.BAD_INPUT);
        require (_gauge_max_votes_ratio <= MAX_VOTES_RATIO, Errors.BAD_INPUT);
        require (_time_before_voting < _epoch_time, Errors.BAD_INPUT);
        require (_time_before_voting + _voting_time < _epoch_time, Errors.BAD_INPUT);
        require (_epoch_time > 0, Errors.BAD_INPUT);
        require (_max_gauges_per_vote > 0, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);

        epochTime = _epoch_time;
        timeBeforeVoting = _time_before_voting;
        votingTime = _voting_time;
        gaugeMinVotesRatio = _gauge_min_votes_ratio;
        gaugeMaxVotesRatio = _gauge_max_votes_ratio;
        gaugeMaxDowntime = _gauge_max_downtime;
        maxGaugesPerVote = _max_gauges_per_vote;

        emit NewVotingParams(
            call_id,
            epochTime,
            timeBeforeVoting,
            votingTime,
            gaugeMinVotesRatio,
            gaugeMaxVotesRatio,
            gaugeMaxDowntime,
            maxGaugesPerVote
        );
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setDistributionScheme(uint32[] _new_scheme, uint32 call_id, address send_gas_to) external onlyOwner {
        require (_new_scheme.length == 3, Errors.BAD_INPUT);
        require (_new_scheme[0] + _new_scheme[1] + _new_scheme[2] == DISTRIBUTION_SCHEME_TOTAL, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);
        distributionScheme = _new_scheme;

        emit DistributionSchemeUpdate(call_id, _new_scheme);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setDistribution(uint128[] _new_distribution, uint32 call_id, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);
        distributionSchedule = _new_distribution;

        emit DistributionScheduleUpdate(call_id, _new_distribution);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function startVoting(uint32 call_id, address send_gas_to) external onlyActive {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);

        tvm.rawReserve(_reserve(), 0);
        _tryStartVoting(call_id);

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function _tryStartVoting(uint32 call_id) internal {
        // if this is true, than someone already started voting
        // dont throw error on duplicate calls
        if (currentVotingStartTime > 0) {
            // emit event otherwise so we can catch function call result on front
            emit VotingStartedAlready(call_id, currentVotingStartTime, currentVotingEndTime);
            return;
        }
        require (initialized, Errors.NOT_INITIALIZED);
        require (currentEpoch - 1 < distributionSchedule.length, Errors.LAST_EPOCH);
        require (now >= currentEpochStartTime + timeBeforeVoting, Errors.TOO_EARLY_FOR_VOTING);

        currentVotingStartTime = now;
        currentVotingEndTime = now + votingTime;
        emit VotingStart(call_id, currentVotingStartTime, currentVotingEndTime);
    }

    // Function for voting with ve qubes user has
    // @param votes - mapping with user votes. Key - gauge address, value - number of ve tokens
    // @param call_id - id helper for front/indexing
    // @param nonce - nonce for callback, ignored if == 0
    // @param send_gas_to - address to send unspent gas
    function vote(mapping (address => uint128) votes, uint32 call_id, uint32 nonce, address send_gas_to) external onlyActive {
        require (msg.value >= Gas.MIN_MSG_VALUE + maxGaugesPerVote * Gas.PER_GAUGE_VOTE_GAS, Errors.LOW_MSG_VALUE);

        if (currentVotingStartTime == 0) {
            _tryStartVoting(call_id);
        }
        // minimum check for gas dependant on gauges count
        require (currentVotingStartTime > 0, Errors.VOTING_NOT_STARTED);
        require (now <= currentVotingEndTime, Errors.VOTING_ENDED);

        uint32 counter = 0;
        for ((address gauge,) : votes) {
            require (gaugeWhitelist[gauge], Errors.GAUGE_NOT_WHITELISTED);
            counter += 1;
        }
        require (counter <= maxGaugesPerVote, Errors.MAX_GAUGES_PER_VOTE);

        tvm.rawReserve(_reserve(), 0);

        address ve_acc_addr = getVoteEscrowAccountAddress(msg.sender);
        IVoteEscrowAccount(ve_acc_addr).processVote{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            currentEpoch, votes, call_id, nonce, send_gas_to
        );
    }

    function finishVote(
        address user, mapping (address => uint128) votes, uint32 call_id, uint32 nonce, address send_gas_to
    ) external override onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        // this is possible if vote(...) was called right before voting end and data race happen
        if (currentVotingStartTime == 0 || now > currentVotingEndTime) {
            emit VoteRevert(call_id, user);
            _sendCallbackOrGas(user, nonce, false, send_gas_to);
            return;
        }

        for ((address gauge, uint128 vote_value) : votes) {
            currentVotingVotes[gauge] += vote_value;
            currentVotingTotalVotes += vote_value;
        }

        emit Vote(call_id, user, votes);
        _sendCallbackOrGas(user, nonce, true, send_gas_to);
    }

    function revertVote(address user, uint32 call_id, uint32 nonce, address send_gas_to) external override onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        emit VoteRevert(call_id, user);
        _sendCallbackOrGas(user, nonce, false, send_gas_to);
    }

    function calculateGasForEndVoting() public view returns (uint128 min_gas) {
        min_gas = Gas.MIN_MSG_VALUE + ((gaugesNum / MAX_ITERATIONS_PER_COUNT) + 1) * Gas.GAS_FOR_MAX_ITERATIONS;
        min_gas += Gas.VOTING_TOKEN_TRANSFER_VALUE * gaugesNum;
    }

    function endVoting(uint32 call_id, address send_gas_to) external onlyActive {
        // make sure we have enough admin deposit to pay for this epoch
        require (distributionSupply >= distributionSchedule[currentEpoch - 1], Errors.LOW_DISTRIBUTION_BALANCE);

        tvm.rawReserve(_reserve(), 0);
        uint128 min_gas = calculateGasForEndVoting();

        // soft fail, because this function could be called simultaneously by several users
        // we dont want require here, because we need to return gas to users which could be really big here
        if (msg.value < min_gas || currentVotingStartTime == 0 || now < currentVotingEndTime) {
            emit VotingEndRevert(call_id);
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

        currentVotingEndTime = 0;
        currentVotingStartTime = 0;
        currentEpoch += 1;
        // if voting ended too late, start epoch now
        currentEpochStartTime = currentEpochEndTime < now ? now : currentEpochEndTime;
        currentEpochEndTime = currentEpochStartTime + epochTime;

        address start_addr = address.makeAddrStd(address(this).wid, 0);
        IVoteEscrow(address(this)).countVotesStep{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            start_addr, 0, 0, call_id, send_gas_to
        );
    }

    function countVotesStep(
        address start_addr,
        uint128 exceeded_votes,
        uint128 valid_votes,
        uint32 call_id,
        address send_gas_to
    ) external override {
        require (msg.sender == address(this), Errors.NOT_OWNER);
        tvm.rawReserve(_reserve(), 0);

        bool finished = false;
        uint32 counter = 0;
        uint128 min_votes = currentVotingTotalVotes * gaugeMinVotesRatio / MAX_VOTES_RATIO;
        uint128 max_votes = currentVotingTotalVotes * gaugeMaxVotesRatio / MAX_VOTES_RATIO;

        // no votes at all, set min_votes to 1, so that all gauges get +1 downtime
        if (currentVotingTotalVotes == 0) {
            min_votes = 1;
        }

        optional(address, bool) pointer = gaugeWhitelist.nextOrEq(start_addr);
        while (true) {
            if (!pointer.hasValue() || counter >= MAX_ITERATIONS_PER_COUNT) {
                finished = !pointer.hasValue();
                break;
            }

            (address gauge,) = pointer.get();
            uint128 gauge_votes = currentVotingVotes[gauge];

            if (gauge_votes < min_votes) {
                exceeded_votes += gauge_votes;
                delete currentVotingVotes[gauge];
                gaugeDowntimes[gauge] += 1;
                if (gaugeDowntimes[gauge] >= gaugeMaxDowntime) {
                    _removeFromWhitelist(gauge, call_id);
                }
            } else if (gauge_votes > max_votes) {
                currentVotingVotes[gauge] = max_votes;
                exceeded_votes += gauge_votes - max_votes;
                delete gaugeDowntimes[gauge];
            } else {
                valid_votes += gauge_votes;
                delete gaugeDowntimes[gauge];
            }

            counter += 1;
            pointer = gaugeWhitelist.next(gauge);
        }

        if (!finished) {
            (address gauge,) = pointer.get();
            IVoteEscrow(address(this)).countVotesStep{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                gauge, exceeded_votes, valid_votes, call_id, send_gas_to
            );
            return;
        }

        start_addr = address.makeAddrStd(address(this).wid, 0);
        IVoteEscrow(address(this)).normalizeVotesStep{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            start_addr, 0, exceeded_votes, valid_votes, call_id, send_gas_to
        );
    }

    function normalizeVotesStep(
        address start_addr,
        uint128 treasury_votes,
        uint128 exceeded_votes,
        uint128 valid_votes,
        uint32 call_id,
        address send_gas_to
    ) external override {
        require (msg.sender == address(this), Errors.NOT_OWNER);
        tvm.rawReserve(_reserve(), 0);

        // if no valid votes/exceeded_votes, we dont need normalization
        if (valid_votes == 0 || exceeded_votes == 0) {
            // if exceeded_votes > 0, set all for treasury
            treasury_votes = exceeded_votes;
        } else {
            bool finished = false;
            uint32 counter = 0;
            uint128 max_votes = currentVotingTotalVotes * gaugeMaxVotesRatio / MAX_VOTES_RATIO;

            optional(address, uint128) pointer = currentVotingVotes.nextOrEq(start_addr);
            while (true) {
                if (!pointer.hasValue() || counter >= MAX_ITERATIONS_PER_COUNT) {
                    finished = !pointer.hasValue();
                    break;
                }

                (address gauge, uint128 gauge_votes) = pointer.get();
                if (gauge_votes < max_votes) {
                    uint128 bonus_votes = math.muldiv(gauge_votes, exceeded_votes, valid_votes);
                    gauge_votes += bonus_votes;
                    if (gauge_votes > max_votes) {
                        treasury_votes += gauge_votes - max_votes;
                        currentVotingVotes[gauge] = max_votes;
                    }
                }

                counter += 1;
                pointer = currentVotingVotes.next(gauge);
            }

            if (!finished) {
                (address gauge,) = pointer.get();
                IVoteEscrow(address(this)).normalizeVotesStep{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                    gauge, treasury_votes, exceeded_votes, valid_votes, call_id, send_gas_to
                );
                return;
            }
        }

        emit VotingEnd(
            call_id,
            currentVotingVotes,
            currentVotingTotalVotes,
            treasury_votes,
            currentEpoch,
            currentEpochStartTime,
            currentEpochEndTime
        );

        start_addr = address.makeAddrStd(address(this).wid, 0);
        mapping (address => uint128) distributed;
        IVoteEscrow(address(this)).distributeEpochQubesStep{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            start_addr, treasury_votes, distributed, call_id, send_gas_to
        );
    }

    function distributeEpochQubesStep(
        address start_addr,
        uint128 bonus_treasury_votes,
        mapping (address => uint128) distributed,
        uint32 call_id,
        address send_gas_to
    ) external override {
        require (msg.sender == address(this), Errors.NOT_OWNER);
        tvm.rawReserve(_reserve(), 0);

        uint256 epoch_idx = currentEpoch - 2;
        uint128 to_distribute_total = distributionSchedule[epoch_idx];
        uint128 to_distribute_farming = math.muldiv(to_distribute_total, distributionScheme[0], DISTRIBUTION_SCHEME_TOTAL);
        uint128 treasury_bonus;
        if (currentVotingTotalVotes > 0) {
            treasury_bonus = math.muldiv(to_distribute_farming, bonus_treasury_votes, currentVotingTotalVotes);
        } else {
            treasury_bonus = to_distribute_farming;
        }

        bool finished = false;
        uint32 counter = 0;

        TvmBuilder builder;
        builder.store(epochTime);
        TvmCell payload = builder.toCell();

        optional(address, uint128) pointer = currentVotingVotes.nextOrEq(start_addr);
        while (true) {
            if (!pointer.hasValue() || counter >= MAX_ITERATIONS_PER_COUNT) {
                finished = !pointer.hasValue();
                break;
            }

            (address gauge, uint128 gauge_votes) = pointer.get();

            uint128 qube_amount = math.muldiv(to_distribute_farming, gauge_votes, currentVotingTotalVotes);
            distributed[gauge] = qube_amount;

            qubeBalance -= qube_amount;
            _transferQubes(qube_amount, gauge, payload, send_gas_to, MsgFlag.SENDER_PAYS_FEES);

            counter += 1;
            pointer = currentVotingVotes.next(gauge);
        }

        if (!finished) {
            (address gauge,) = pointer.get();
            IVoteEscrow(address(this)).distributeEpochQubesStep{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                gauge, bonus_treasury_votes, distributed, call_id, send_gas_to
            );
            return;
        }

        uint128 to_distribute_treasury = math.muldiv(to_distribute_total, distributionScheme[1], DISTRIBUTION_SCHEME_TOTAL);
        uint128 to_distribute_team = math.muldiv(to_distribute_total, distributionScheme[2], DISTRIBUTION_SCHEME_TOTAL);
        to_distribute_treasury += treasury_bonus;

        treasuryTokens += to_distribute_treasury;
        teamTokens += to_distribute_team;
        distributionSupply -= to_distribute_total;

        currentVotingTotalVotes = 0;
        delete currentVotingVotes;

        emit EpochDistribution(
            call_id,
            currentEpoch,
            distributed,
            to_distribute_team,
            to_distribute_treasury
        );
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdrawTreasuryTokens(uint128 amount, address receiver, uint32 call_id, address send_gas_to) external onlyOwner {
        require (amount <= treasuryTokens, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);
        treasuryTokens -= amount;

        emit TreasuryWithdraw(call_id, receiver, amount);
        TvmCell empty;
        qubeBalance -= amount;
        _transferQubes(amount, receiver, empty, send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdrawTeamTokens(uint128 amount, address receiver, uint32 call_id, address send_gas_to) external onlyOwner {
        require (amount <= teamTokens, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);
        teamTokens -= amount;

        emit TeamWithdraw(call_id, receiver, amount);
        TvmCell empty;
        qubeBalance -= amount;
        _transferQubes(amount, receiver, empty, send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdrawPaymentTokens(uint128 amount, address receiver, uint32 call_id, address send_gas_to) external onlyOwner {
        require (amount <= whitelistPayments, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);
        whitelistPayments -= amount;

        emit PaymentWithdraw(call_id, receiver, amount);
        TvmCell empty;
        qubeBalance -= amount;
        _transferQubes(amount, receiver, empty, send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }
}
