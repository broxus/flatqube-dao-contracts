pragma ever-solidity ^0.62.0;
pragma AbiHeader expire;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../libraries/Errors.sol";
import "../vote_escrow/base/vote_escrow/VoteEscrowBase.sol";


contract TestVoteEscrow is VoteEscrowBase {
    constructor(address _owner, address _qube, address _dao) public {
        // Deployed by Deployer contract
        require (msg.sender.value != 0, Errors.BAD_SENDER);
        owner = _owner;
        qube = _qube;
        dao = _dao;

        _setupTokenWallet();
    }

    // ONLY FOR TESTING!
    function sendQubesToGauge(
        uint128 qube_amount,
        address gauge,
        uint32 round_len,
        uint32 round_start
    ) external view {
        TvmBuilder builder;
        builder.store(round_start);
        builder.store(round_len);
        TvmCell payload = builder.toCell();
        _transferQubes(qube_amount, gauge, payload, owner, MsgFlag.SENDER_PAYS_FEES);
    }

    function startVotingTest(uint32 start_time, uint32 end_time, Callback.CallMeta meta) external {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);

        tvm.rawReserve(_reserve(), 0);

        if (currentVotingStartTime > 0) {
            // emit event otherwise so we can catch function call result on front
            emit VotingStartedAlready(meta.call_id, currentVotingStartTime, currentVotingEndTime);
            return;
        }

        currentVotingStartTime = start_time;
        currentVotingEndTime = end_time;
        emit VotingStart(meta.call_id, currentVotingStartTime, currentVotingEndTime);

        meta.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setOwner(address new_owner) external {
        owner = new_owner;
    }

    function endVotingTest(uint32 epoch_time, Callback.CallMeta meta) external {
        // make sure we have enough admin deposit to pay for this epoch
        require (distributionSupply >= distributionSchedule[currentEpoch - 1], Errors.LOW_DISTRIBUTION_BALANCE);

        tvm.rawReserve(_reserve(), 0);
        uint128 min_gas = calculateGasForEndVoting();

        // soft fail, because this function could be called simultaneously by several users
        // we dont want require here, because we need to return gas to users which could be really big here
        if (msg.value < min_gas || currentVotingStartTime == 0 || now < currentVotingEndTime) {
            emit VotingEndRevert(meta.call_id);
            meta.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

        currentVotingEndTime = 0;
        currentVotingStartTime = 0;
        currentEpoch += 1;
        // if voting ended too late, start epoch now
        currentEpochStartTime = currentEpochEndTime < now ? now : currentEpochEndTime;
        currentEpochEndTime = currentEpochStartTime + epoch_time;

        address start_addr = address.makeAddrStd(address(this).wid, 0);
        IVoteEscrow(address(this)).countVotesStep{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(start_addr, 0, 0, meta);
    }

    function emitVotesTest(
        address user, mapping (address => uint128) votes, Callback.CallMeta meta
    ) external {
        tvm.rawReserve(_reserve(), 0);

        // this is possible if vote(...) was called right before voting end and data race happen
        if (currentVotingStartTime == 0) {
            emit VoteRevert(meta.call_id, user);
            _sendCallbackOrGas(user, meta.nonce, false, meta.send_gas_to);
            return;
        }

        for ((address gauge, uint128 vote_value) : votes) {
            currentVotingVotes[gauge] += vote_value;
            currentVotingTotalVotes += vote_value;
        }

        emit Vote(meta.call_id, user, votes);
        _sendCallbackOrGas(user, meta.nonce, true, meta.send_gas_to);
    }

    function upgrade(TvmCell code, Callback.CallMeta meta) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);

        TvmCell data = abi.encode(
            meta,
            deploy_nonce,
            platformCode,
            veAccountCode,
            ve_account_version,
            ve_version,
            owner,
            pendingOwner,
            dao,
            qube,
            qubeWallet,
            treasuryTokens,
            teamTokens,
            distributionScheme,
            qubeBalance,
            veQubeBalance,
            lastUpdateTime,
            distributionSupply,
            distributionSchedule,
            veQubeAverage,
            veQubeAveragePeriod,
            qubeMinLockTime,
            qubeMaxLockTime,
            initialized,
            paused,
            emergency,
            currentEpoch,
            currentEpochStartTime,
            currentEpochEndTime,
            currentVotingStartTime,
            currentVotingEndTime,
            currentVotingTotalVotes,
            epochTime,
            votingTime,
            timeBeforeVoting,
            gaugeMaxVotesRatio,
            gaugeMinVotesRatio,
            gaugeMaxDowntime,
            maxGaugesPerVote,
            gaugesNum,
            gaugeWhitelist,
            currentVotingVotes,
            gaugeDowntimes,
            gaugeWhitelistPrice,
            whitelistPayments,
            deposit_nonce,
            pending_deposits
        );

        // set code after complete this method
        tvm.setcode(code);

        // run onCodeUpgrade from new code
        tvm.setCurrentCode(code);
        onCodeUpgrade(data);
    }

    event Upgrade(uint32 old_version, uint32 new_version);

    function onCodeUpgrade(TvmCell data) private {
        tvm.resetStorage();

        Callback.CallMeta meta;
        (
            meta,
            deploy_nonce,
            platformCode,
            veAccountCode,
            ve_account_version,
            ve_version,
            owner,
            pendingOwner,
            dao,
            qube,
            qubeWallet,
            treasuryTokens,
            teamTokens,
            distributionScheme,
            qubeBalance,
            veQubeBalance,
            lastUpdateTime,
            distributionSupply,
            distributionSchedule,
            veQubeAverage,
            veQubeAveragePeriod,
            qubeMinLockTime,
            qubeMaxLockTime,
            initialized,
            paused,
            emergency,
            currentEpoch,
            currentEpochStartTime,
            currentEpochEndTime,
            currentVotingStartTime,
            currentVotingEndTime,
            currentVotingTotalVotes,
            epochTime,
            votingTime,
            timeBeforeVoting,
            gaugeMaxVotesRatio,
            gaugeMinVotesRatio,
            gaugeMaxDowntime,
            maxGaugesPerVote,
            gaugesNum,
            gaugeWhitelist,
            currentVotingVotes,
            gaugeDowntimes,
            gaugeWhitelistPrice,
            whitelistPayments,
            deposit_nonce,
            pending_deposits
        ) = abi.decode(
            data,
            (
                Callback.CallMeta,
                uint32,
                TvmCell,
                TvmCell,
                uint32,
                uint32,
                address,
                address,
                address,
                address,
                address,
                uint128,
                uint128,
                uint32[],
                uint128,
                uint128,
                uint32,
                uint128 , // current balance of tokens reserved for distribution
                uint128[],
                uint128,
                uint32,
                uint32,
                uint32,
                bool,
                bool,
                bool,
                uint32,
                uint32,
                uint32,
                uint32,
                uint32,
                uint128,
                uint32,
                uint32,
                uint32,
                uint32,
                uint32,
                uint8,
                uint32,
                uint32,
                mapping (address => bool),
                mapping (address => uint128),
                mapping (address => uint8),
                uint128,
                uint128,
                uint32,
                mapping (uint32 => PendingDeposit)
            )
        );

        ve_version += 1;
        emit Upgrade(ve_version - 1, ve_version);
    }
}
