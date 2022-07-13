pragma ever-solidity ^0.60.0;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../../../libraries/Gas.sol";
import "./VoteEscrowUpgradable.sol";


abstract contract VoteEscrowDAO is VoteEscrowUpgradable {
    function castVote(uint32 proposal_id, bool support) public view override {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        require (!emergency, Errors.EMERGENCY);
        _castVote(proposal_id, support, '');
    }

    function castVoteWithReason(
        uint32 proposal_id,
        bool support,
        string reason
    ) public view override {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        require (!emergency, Errors.EMERGENCY);
        _castVote(proposal_id, support, reason);
    }

    function _castVote(uint32 proposal_id, bool support, string reason) private view {
        tvm.rawReserve(_reserve(), 0);
        IVoteEscrowAccount(getVoteEscrowAccountAddress(msg.sender)).castVote{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(proposal_id, support, reason);
    }

    function tryUnlockVoteTokens(uint32 proposal_id) public view override {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        require (!emergency, Errors.EMERGENCY);
        tvm.rawReserve(_reserve(), 0);

        IVoteEscrowAccount(getVoteEscrowAccountAddress(msg.sender)).tryUnlockVoteTokens{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(proposal_id);

    }

    function tryUnlockCastedVotes(uint32[] proposal_ids) public view override {
        require (!emergency, Errors.EMERGENCY);
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IVoteEscrowAccount(getVoteEscrowAccountAddress(msg.sender)).tryUnlockCastedVotes{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(proposal_ids);
    }
}
