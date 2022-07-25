pragma ever-solidity ^0.62.0;


import "../../../libraries/Gas.sol";
import "../../../libraries/Errors.sol";
import "../../interfaces/IVoteEscrow.sol";
import "../../interfaces/IVoteEscrowAccount.sol";
import "../../../gauge/interfaces/IGaugeAccount.sol";

import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "./VoteEscrowAccountDAO.sol";


abstract contract VoteEscrowAccountBase is VoteEscrowAccountDAO {
    function onDeployRetry(TvmCell, TvmCell, address sendGasTo) external view onlyVoteEscrowOrSelf functionID(0x23dc4360){
        tvm.rawReserve(_reserve(), 0);
        sendGasTo.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function processEpochVote(
        uint32 voteEpoch, mapping (address => uint128) votes, uint32 call_id, uint32 nonce, address send_gas_to
    ) external override onlyVoteEscrowOrSelf {
        require (lastEpochVoted < voteEpoch, Errors.ALREADY_VOTED);

        tvm.rawReserve(_reserve(), 0);

        // check gas only at beginning
        if (msg.sender == voteEscrow && msg.value < calculateMinGas()) {
            IVoteEscrow(voteEscrow).revertVote{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, call_id, nonce, send_gas_to);
            return;
        }

        bool update_finished = _syncDeposits(now);
        if (!update_finished) {
            IVoteEscrowAccount(address(this)).processEpochVote{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                voteEpoch, votes, call_id, nonce, send_gas_to
            );
            return;
        }

        uint128 totalVotes = 0;
        for ((, uint128 vote_value) : votes) {
            totalVotes += vote_value;
        }
        if (veQubeBalance < totalVotes) {
            // soft fail, because ve qubes could be burned while syncing and we want to return gas to user and notify him
            IVoteEscrow(voteEscrow).revertVote{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, call_id, nonce, send_gas_to);
            return;
        }

        lastEpochVoted = voteEpoch;
        IVoteEscrow(voteEscrow).finishVote{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, votes, call_id, nonce, send_gas_to);
    }

    function processWithdraw(uint32 call_id, uint32 nonce, address send_gas_to) external override onlyVoteEscrowOrSelf {
        tvm.rawReserve(_reserve(), 0);

        // check gas only at beginning
        if (msg.sender == voteEscrow && msg.value < calculateMinGas()) {
            IVoteEscrow(msg.sender).revertWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, call_id, nonce, send_gas_to);
            return;
        }

        bool update_finished = _syncDeposits(now);
        // continue update in next message with same parameters
        if (!update_finished) {
            IVoteEscrowAccount(address(this)).processWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                call_id, nonce, send_gas_to
            );
            return;
        }

        qubeBalance -= unlockedQubes;
        uint128 _withdraw_qubes = unlockedQubes;
        unlockedQubes = 0;

        IVoteEscrow(voteEscrow).finishWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, _withdraw_qubes, call_id, nonce, send_gas_to);
    }

    function processDeposit(
        uint32 deposit_nonce,
        uint128 qube_amount,
        uint128 ve_amount,
        uint32 lock_time,
        uint32 nonce,
        address send_gas_to
    ) external override onlyVoteEscrowOrSelf {
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
    // @dev attach gas >= calculateMinGas(), otherwise call may fail with gas exception!
    // Caller contract is responsible for attaching enough gas
    // This call could be called by anyone, user will only benefit from this
    // @param callback_receiver - address that will receive callback
    // @param callback_nonce - nonce that will be sent with callback
    // @param sync_time - timestamp. Ve stats will be updated up to this moment
    function getVeAverage(address callback_receiver, uint32 callback_nonce, uint32 sync_time) external override {
        require (msg.sender == address(this) || msg.sender == callback_receiver, Errors.BAD_SENDER);
        tvm.rawReserve(_reserve(), 0);

        // update ve stats before sending callback
        bool update_finished = _syncDeposits(sync_time);
        // continue update in next message with same parameters
        if (!update_finished) {
            IVoteEscrowAccount(address(this)).getVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                callback_receiver, callback_nonce, sync_time
            );
            return;
        }
        IGaugeAccount(callback_receiver).receiveVeAccAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            callback_nonce, veQubeBalance, veQubeAverage, veQubeAveragePeriod
        );
    }
}
