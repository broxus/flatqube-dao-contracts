pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "./VoteEscrowUpgradable.sol";
import "../../interfaces/IVoteEscrowAccount.sol";


abstract contract VoteEscrowVoting is VoteEscrowUpgradable {
    function initialize(uint32 start_time, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        // codes installed
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
        require (initialized, Errors.NOT_INITIALIZED);

        require (currentEpoch + 1 < distributionSchedule.length, Errors.LAST_EPOCH);

        require (now >= currentEpochStartTime + timeBeforeVoting, Errors.TOO_EARLY_FOR_VOTING);
        require (currentVotingStartTime == 0, Errors.VOTING_ALREADY_STARTED);

        tvm.rawReserve(_reserve(), 0);

        currentVotingStartTime = now;
        currentVotingEndTime = now + votingTime;

        emit VotingStart(call_id, currentVotingStartTime, currentVotingEndTime);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    // Function for voting with ve qubes user has
    // @param votes - mapping with user votes. Key - gauge address, value - number of ve tokens
    // @param call_id - id helper for front/indexing
    // @param nonce - nonce for callback, ignored if == 0
    // @param send_gas_to - address to send unspent gas
    function vote(mapping (address => uint128) votes, uint32 call_id, uint32 nonce, address send_gas_to) external view onlyActive {
        // minimum check for gas dependant on gauges count
        // TODO: dont need dynamic here, gauges num is limited
        require (msg.value >= Gas.MIN_MSG_VALUE + maxGaugesPerVote * Gas.PER_GAUGE_VOTE_VALUE, Errors.LOW_MSG_VALUE);
        require (currentVotingStartTime > 0, Errors.VOTING_NOT_STARTED);
        require (now <= currentEpochEndTime, Errors.VOTING_ENDED);

        uint32 counter = 0;
        for ((address gauge,) : votes) {
            require (whitelistedGauges[gauge], Errors.GAUGE_NOT_WHITELISTED);
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

    function endVoting(uint32 call_id, address send_gas_to) external onlyActive {
        uint128 min_gas = Gas.MIN_MSG_VALUE + Gas.PER_GAUGE_VOTE_VALUE * gaugesNum + Gas.VOTING_TOKEN_TRANSFER_VALUE * gaugesNum;
        require (msg.value >= min_gas, Errors.LOW_MSG_VALUE);
        require (currentVotingStartTime != 0, Errors.VOTING_NOT_STARTED);
        require (now >= currentVotingEndTime, Errors.VOTING_NOT_ENDED);

        uint128 min_votes = currentVotingTotalVotes * gaugeMinVotesRatio / MAX_VOTES_RATIO;
        uint128 max_votes = currentVotingTotalVotes * gaugeMaxVotesRatio / MAX_VOTES_RATIO;
        uint128 exceeded_votes = 0;
        uint128 valid_votes = 0;
        // get rid of "bad" gauges that dint reach vote threshold
        // + rearrange votes of too "big" gauges
        for ((address gauge, uint128 gauge_votes) : currentVotingVotes) {
            if (gauge_votes < min_votes) {
                exceeded_votes += gauge_votes;
                delete currentVotingVotes[gauge];
                gaugeDowntime[gauge] += 1;
                if (gaugeDowntime[gauge] >= gaugeMaxDowntime) {
                    _removeFromWhitelist(gauge, call_id);
                }
            } else if (gauge_votes > max_votes) {
                currentVotingVotes[gauge] = max_votes;
                exceeded_votes += gauge_votes - max_votes;
                gaugeDowntime[gauge] = 0;
            } else {
                valid_votes += gauge_votes;
                gaugeDowntime[gauge] = 0;
            }
        }

        uint128 treasury_votes = 0;
        if (exceeded_votes > 0) {
            for ((address gauge, uint128 gauge_votes) : currentVotingVotes) {
                if (gauge_votes < max_votes) {
                    uint128 bonus_votes = math.muldiv(gauge_votes, exceeded_votes, valid_votes);
                    gauge_votes += bonus_votes;
                    if (gauge_votes > max_votes) {
                        treasury_votes += gauge_votes - max_votes;
                        currentVotingVotes[gauge] = max_votes;
                    }
                }
            }
        }

        currentVotingEndTime = 0;
        currentVotingStartTime = 0;
        currentEpoch += 1;
        // if voting ended too late, start epoch now
        currentEpochStartTime = currentEpochEndTime < now ? now : currentEpochEndTime;
        currentEpochEndTime = currentEpochStartTime + epochTime;

        tvm.rawReserve(_reserve(), 0);

        emit VotingEnd(
            call_id,
            currentVotingVotes,
            currentVotingTotalVotes,
            treasury_votes,
            currentEpoch,
            currentEpochStartTime,
            currentVotingEndTime
        );
        IVoteEscrow(address(this)).distributeEpochQubes{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            treasury_votes, call_id, send_gas_to
        );
    }

    // We distribute qubes in separate message to be able to spend more gas
    function distributeEpochQubes(
        uint128 bonus_treasury_votes, uint32 call_id, address send_gas_to
    ) external override {
        require (msg.sender == address(this), Errors.NOT_OWNER);
        tvm.rawReserve(_reserve(), 0);

        // we start distributing qubes from 2 epoch
        uint256 epoch_idx = currentEpoch - 2;
        uint128 to_distribute_total = distributionSchedule[epoch_idx];
        uint128 to_distribute_farming = math.muldiv(to_distribute_total, distributionScheme[0], DISTRIBUTION_SCHEME_TOTAL);
        uint128 to_distribute_treasury = math.muldiv(to_distribute_total, distributionScheme[1], DISTRIBUTION_SCHEME_TOTAL);
        uint128 to_distribute_team = math.muldiv(to_distribute_total, distributionScheme[2], DISTRIBUTION_SCHEME_TOTAL);

        uint128 treasury_bonus = math.muldiv(to_distribute_farming, bonus_treasury_votes, currentVotingTotalVotes);
        to_distribute_treasury += treasury_bonus;
        to_distribute_farming -= treasury_bonus;

        treasuryTokens += to_distribute_treasury;
        teamTokens += to_distribute_team;

        mapping (address => uint128) distributed;

        TvmBuilder builder;
        builder.store(epochTime);
        TvmCell payload = builder.toCell();
        for ((address gauge, uint128 gauge_votes): currentVotingVotes) {
            uint128 qube_amount = math.muldiv(to_distribute_farming, gauge_votes, currentVotingTotalVotes);
            distributed[gauge] = qube_amount;
            _transferTokens(qubeWallet, qube_amount, gauge, payload, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
        }

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
        _transferTokens(qubeWallet, amount, receiver, empty, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
    }

    function withdrawTeamTokens(uint128 amount, address receiver, uint32 call_id, address send_gas_to) external onlyOwner {
        require (amount <= teamTokens, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);
        teamTokens -= amount;

        emit TeamWithdraw(call_id, receiver, amount);
        TvmCell empty;
        _transferTokens(qubeWallet, amount, receiver, empty, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
    }

    function withdrawPaymentTokens(uint128 amount, address receiver, uint32 call_id, address send_gas_to) external onlyOwner {
        require (amount <= whitelistPayments, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);
        whitelistPayments -= amount;

        emit PaymentWithdraw(call_id, receiver, amount);
        TvmCell empty;
        _transferTokens(qubeWallet, amount, receiver, empty, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
    }
}
