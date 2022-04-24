pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./VoteEscrowUpgradable.sol";


abstract contract VoteEscrowVoting is VoteEscrowUpgradable {
    function initialize(address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        require (distribution.length > 0, Errors.CANT_BE_INITIALIZED);
        require (distributionScheme.length > 0, Errors.CANT_BE_INITIALIZED);
        require (!initialized, Errors.ALREADY_INITIALIZED);

        tvm.rawReserve(_reserve(), 0);
        initializationTime = now;
        currentEpochStartTime = now;
        currentEpochEndTime = now + epochTime;
        currentEpoch = 1;
        initialized = true;

        // TODO: emit event
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setDistributionScheme(uint32[] _new_scheme, address send_gas_to) external onlyOwner {
        require (_new_scheme.length == 3, Errors.BAD_INPUT);
        require (_new_scheme[0] + _new_scheme[1] + _new_scheme[2] == DISTRIBUTION_SCHEME_TOTAL, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);

        distributionScheme = _new_scheme;

        // TODO: emit event
        send_gas_to.send(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setDistribution(uint128[] _new_distribution, address send_gas_to) external onlyOwner {
        // only symmetric
        require (_new_distribution.length / 2 == 0, Errors.BAD_INPUT);
        tvm.rawReserve(_reserve(), 0);

        distribution = _new_distribution;
        // TODO: emit event

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function startVoting(address send_gas_to) external onlyActive {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        require (initialized, Errors.NOT_INITIALIZED);

        currentEpoch + 1 == distribution.length - 1;
        require (currentEpoch + 1 < distribution.length * 2, Errors.LAST_EPOCH);

        require (now >= currentEpochStartTime + timeBeforeVoting, Errors.TOO_EARLY_FOR_VOTING);
        require (currentVotingStartTime == 0, Errors.VOTING_ALREADY_STARTED);

        tvm.rawReserve(_reserve(), 0);

        currentVotingStartTime = now;
        currentEpochEndTime = now + votingTime;
        // TODO: emit event

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    // Function for voting with ve qubes user has
    // @param votes - mapping with user votes. Key - gauge address, value - number of ve tokens
    // @param nonce - nonce for callback, ignored if == 0
    // @param send_gas_to - address to send unspent gas
    function vote(mapping (address => uint128) votes, uint32 nonce, address send_gas_to) external onlyActive {
        // minimum check for gas dependant on gauges count
        // TODO: dont need dynamic here, gauges num is limited
        require (msg.value >= Gas.MIN_MSG_VALUE + maxGaugesPerVote * Gas.PER_GAUGE_VOTE_VALUE, Errors.LOW_MSG_VALUE);
        require (currentVotingStartTime > 0, Errors.VOTING_NOT_STARTED);
        require (now <= currentEpochEndTime, Errors.VOTING_ENDED);

        uint32 counter = 0;
        //        for ((address gauge,) : votes) {
        //            require (whitelistedGauges[gauge], Errors.GAUGE_NOT_WHITELISTED);
        //            counter += 1;
        //        }
        require (counter <= maxGaugesPerVote, Errors.MAX_GAUGES_PER_VOTE);

        tvm.rawReserve(_reserve(), 0);

        address ve_acc_addr = getVoteEscrowAccountAddress(msg.sender);
        IVoteEscrowAccount(ve_acc_addr).processVote{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            currentEpoch, votes, nonce, send_gas_to
        );
    }

    function finishVote(
        address user, mapping (address => uint128) votes, uint32 nonce, address send_gas_to
    ) external onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        // this is possible if vote(...) was called right before voting end and data race happen
        if (currentVotingStartTime == 0 || now > currentVotingEndTime) {
            // TODO: emit event
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

        //        for ((address gauge, uint128 vote_value) : votes) {
        //            currentVotingVotes[gauge] += vote_value;
        //            currentVotingTotalVotes += vote_value;
        //        }

        // TODO: emit event
        // TODO send callback

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function endVoting(address send_gas_to) external {
        require (msg.value >= Gas.MIN_MSG_VALUE + Gas.MSG_VALUE_PER_GAUGE * gaugesNum, Errors.LOW_MSG_VALUE);
        require (currentVotingStartTime != 0, Errors.VOTING_NOT_STARTED);
        require (now > currentVotingEndTime, Errors.VOTING_NOT_ENDED);

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
                    _removeFromWhitelist(gauge);
                }
            } else if (gauge_votes > max_votes) {
                currentVotingVotes[gauge] = max_votes;
                exceeded_votes += gauge_votes - max_votes;
            } else {
                valid_votes += gauge_votes;
            }
        }

        uint128 treasury_votes = 0;
        //        if (exceeded_votes > 0) {
        //            for ((address gauge, uint128 gauge_votes) : currentVotingVotes) {
        //                if (gauge_votes < max_votes) {
        //                    uint128 bonus_votes = math.muldiv(gauge_votes, exceeded_votes, valid_votes);
        //                    gauge_votes += bonus_votes;
        //                    if (gauge_votes > max_votes) {
        //                        treasury_votes += gauge_votes - max_votes;
        //                        currentVotingVotes[gauge] = max_votes;
        //                    }
        //                }
        //            }
        //        }

        currentVotingEndTime = 0;
        currentVotingStartTime = 0;
        currentEpoch += 1;
        // if voting ended too late, start epoch now
        currentEpochStartTime = currentEpochEndTime < now ? now : currentEpochEndTime;
        currentVotingEndTime = currentEpochStartTime + epochTime;

        tvm.rawReserve(_reserve(), 0);

        // TODO: emit event
        IVoteEscrow(address(this)).distributeEpochQubes{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            treasury_votes, send_gas_to
        );
    }

    // We distribute qubes in separate message to be able to spend more gas
    function distributeEpochQubes(
        uint128 bonus_treasury_votes, address send_gas_to
    ) external {
        require (msg.sender == address(this), Errors.NOT_OWNER);
        tvm.rawReserve(_reserve(), 0);

        // we start distributing qubes from 2 epoch
        uint256 epoch_idx = currentEpoch - 2;
        uint128 to_distribute_total;
        if (epoch_idx >= distribution.length) {
            uint256 offset = epoch_idx - (distribution.length - 1);
            to_distribute_total = distribution[epoch_idx - offset];
        } else {
            to_distribute_total = distribution[epoch_idx];
        }
        uint128 to_distribute_farming = math.muldiv(to_distribute_total, distributionScheme[0], DISTRIBUTION_SCHEME_TOTAL);
        uint128 to_distribute_treasury = math.muldiv(to_distribute_total, distributionScheme[1], DISTRIBUTION_SCHEME_TOTAL);
        uint128 to_distribute_team = math.muldiv(to_distribute_total, distributionScheme[2], DISTRIBUTION_SCHEME_TOTAL);

        uint128 treasury_bonus = math.muldiv(to_distribute_farming, bonus_treasury_votes, currentVotingTotalVotes);
        to_distribute_treasury += treasury_bonus;
        to_distribute_farming -= treasury_bonus;

        treasuryTokens += to_distribute_treasury;
        teamTokens += to_distribute_team;

        TvmBuilder builder;
        builder.store(epochTime);
        TvmCell payload = builder.toCell();
        for ((address gauge, uint128 gauge_votes): currentVotingVotes) {
            uint128 qube_amount = math.muldiv(to_distribute_farming, gauge_votes, currentVotingTotalVotes);
            _transferTokens(qubeWallet, qube_amount, gauge, payload, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
        }

        currentVotingTotalVotes = 0;
        delete currentVotingVotes;

        // TODO: emit event
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdrawTreasuryTokens(uint128 amount, address receiver, address send_gas_to) external onlyOwner {
        require (amount <= treasuryTokens, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);

        treasuryTokens -= amount;
        // TODO: emit event

        TvmCell empty;
        _transferTokens(qubeWallet, amount, receiver, empty, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
    }

    function withdrawTeamTokens(uint128 amount, address receiver, address send_gas_to) external onlyOwner {
        require (amount <= teamTokens, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);

        teamTokens -= amount;
        // TODO: emit event

        TvmCell empty;
        _transferTokens(qubeWallet, amount, receiver, empty, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
    }

    function _addToWhitelist(address gauge) internal {
        gaugesNum += 1;
        whitelistedGauges[gauge] = true;
        // TODO: add event
    }

    function _removeFromWhitelist(address gauge) internal {
        gaugesNum -= 1;
        whitelistedGauges[gauge] = false;
        // TODO: add event
    }

    // TODO: add value
    function _transferTokens(
        address token_wallet, uint128 amount, address receiver, TvmCell payload, address send_gas_to, uint16 flag
    ) internal {
        uint128 value;
        if (flag != MsgFlag.ALL_NOT_RESERVED) {
            value = TOKEN_TRANSFER_VALUE;
        }
        bool notify = false;
        // notify = true if payload is non-empty
        if (payload.bits() > 0) {
            notify = true;
        }
        ITokenWallet(qubeWallet).transfer{value: value, flag: flag}(
            amount,
            receiver,
            0,
            send_gas_to,
            notify,
            payload
        );
    }
}
