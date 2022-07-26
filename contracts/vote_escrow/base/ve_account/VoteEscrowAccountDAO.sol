pragma ever-solidity ^0.62.0;


import "./VoteEscrowAccountHelpers.sol";
import "../../../libraries/Errors.sol";
import "../../../dao/interfaces/IProposer.sol";
import "../../../dao/interfaces/IProposal.sol";
import "../../../dao/interfaces/IDaoRoot.sol";
import "../../../dao/interfaces/IVoter.sol";
import {RPlatform as Platform} from "../../../Platform.sol";


abstract contract VoteEscrowAccountDAO is VoteEscrowAccountHelpers {
    function _buildPlatformInitData(address platform_root, uint8 platform_type, TvmCell initial_data) private view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Platform,
            varInit: {
                root: platform_root,
                platformType: platform_type,
                initialData: initial_data,
                platformCode: platform_code
            },
            pubkey: 0,
            code: platform_code
        });
    }

    function getProposalAddress(uint32 proposal_id) private view returns (address) {
        return address(tvm.hash(_buildPlatformInitData(
            dao_root,
            uint8(DaoPlatformTypes.PlatformType.Proposal),
            _buildProposalInitialData(proposal_id)))
        );
    }

    modifier onlyDaoProposal(uint32 proposal_id) {
        require(msg.sender == getProposalAddress(proposal_id), Errors.NOT_PROPOSAL);
        _;
    }

    modifier onlyDaoRoot {
        require(msg.sender == dao_root, Errors.NOT_DAO_ROOT);
        _;
    }

    function lockedTokens() override public view responsible returns(uint128) {
        return {value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false} _lockedTokens();
    }

    function propose(
        TvmCell proposal_data,
        uint128 threshold
    ) override public onlyDaoRoot {
        // TODO: SYNC VE QUBE BALANCE BEFORE APPLY
        if (veQubeBalance - _lockedTokens() >= threshold) {
            _proposal_nonce++;
            _tmp_proposals[_proposal_nonce] = threshold;
            IDaoRoot(dao_root).deployProposal{
                value: 0,
                flag: MsgFlag.REMAINING_GAS
            }(_proposal_nonce, user, proposal_data);
        } else {
            IProposer(user).onProposalNotCreated{
                value: 0,
                flag: MsgFlag.REMAINING_GAS,
                bounce: false
            }(proposal_data.toSlice().decode(uint32));
        }
    }

    function onProposalDeployed(uint32 nonce, uint32 proposal_id, uint32 answer_id) public override onlyDaoRoot {
        created_proposals[proposal_id] = _tmp_proposals[nonce];
        delete _tmp_proposals[nonce];
        IProposer(user).onProposalCreated{
            value: 0,
            flag: MsgFlag.REMAINING_GAS,
            bounce: false
        }(answer_id, proposal_id);
    }

    function castVote(uint32 proposal_id, bool support, string reason) public override onlyVoteEscrowOrSelf {
        // TODO: SYNC VE QUBE BALANCE BEFORE APPLY
        tvm.rawReserve(_reserve(), 0);

        uint16 error;

        if (msg.value < Gas.CAST_VOTE_VALUE) error = Errors.LOW_MSG_VALUE;
        if (casted_votes.exists(proposal_id)) error = Errors.ALREADY_VOTED;
        if (bytes(reason).length > MAX_REASON_LENGTH) error = Errors.REASON_IS_TOO_LONG;

        if (error != 0){
            IVoter(user).onVoteRejected{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(proposal_id, error);
            return;
        }

        emit VoteCast(proposal_id, support, veQubeBalance, reason);
        casted_votes[proposal_id] = support;
        IProposal(getProposalAddress(proposal_id)).castVote{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(proposal_id, user, veQubeBalance, support, reason);
    }

    function voteCasted(uint32 proposal_id) override public onlyDaoProposal(proposal_id) {
        IVoter(user).onVoteCasted{value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false}(proposal_id);
    }

    function rejectVote(uint32 proposal_id) override public onlyDaoProposal(proposal_id) {
        if (casted_votes.exists(proposal_id)) {
            delete casted_votes[proposal_id];
        }
        IVoter(user).onVoteRejected{
            value: 0,
            flag: MsgFlag.REMAINING_GAS,
            bounce: false
        }(proposal_id, Errors.PROPOSAL_IS_NOT_ACTIVE);
    }

    function tryUnlockVoteTokens(uint32 proposal_id) override public view onlyVoteEscrowOrSelf {
        tvm.rawReserve(_reserve(), 0);
        uint16 error;

        if (msg.value < Gas.UNLOCK_LOCKED_VOTE_TOKENS_VALUE) error = Errors.LOW_MSG_VALUE;
        if (!created_proposals.exists(proposal_id)) error = Errors.WRONG_PROPOSAL_ID;

        if (error != 0){
            IVoter(user).onVotesNotUnlocked{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(proposal_id, error);
            return;
        }

        IProposal(getProposalAddress(proposal_id)).unlockVoteTokens{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user);
    }

    function unlockVoteTokens(uint32 proposal_id, bool success) override public onlyDaoProposal(proposal_id) {
        if (success && created_proposals.exists(proposal_id)) {
            emit UnlockVotes(proposal_id, created_proposals[proposal_id]);
            delete created_proposals[proposal_id];
            IVoter(user).onVotesUnlocked{value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false}(proposal_id);
        } else {
            IVoter(user).onVotesNotUnlocked{
                value: 0,
                flag: MsgFlag.REMAINING_GAS,
                bounce: false
            }(proposal_id, Errors.WRONG_PROPOSAL_STATE);
        }
    }

    function tryUnlockCastedVotes(uint32[] proposal_ids) override public view onlyVoteEscrowOrSelf {
        tvm.rawReserve(_reserve(), 0);

        uint16 error;

        if (msg.value < proposal_ids.length * Gas.UNLOCK_CASTED_VOTE_VALUE + 1 ton) error = Errors.LOW_MSG_VALUE;

        if (error != 0){
            IVoter(user).onCastedVoteNotUnlocked{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(proposal_ids, error);
            return;
        }

        for (uint i = 0; i < proposal_ids.length; i++) {
            if (casted_votes.exists(proposal_ids[i])) {
                IProposal(getProposalAddress(proposal_ids[i])).unlockCastedVote{
                    value: Gas.UNLOCK_CASTED_VOTE_VALUE,
                    flag: MsgFlag.SENDER_PAYS_FEES
                }(user);
            }
        }
        user.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    function unlockCastedVote(uint32 proposal_id, bool success) override public onlyDaoProposal(proposal_id) {
        if (success && casted_votes.exists(proposal_id)) {
            delete casted_votes[proposal_id];
            emit UnlockCastedVotes(proposal_id);
            IVoter(user).onCastedVoteUnlocked{value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false}(proposal_id);
        } else {
            IVoter(user).onCastedVoteNotUnlocked{
                value: 0,
                flag: MsgFlag.REMAINING_GAS, bounce: false
            }([proposal_id], Errors.WRONG_PROPOSAL_STATE);
        }
    }

    function _buildProposalInitialData(uint32 proposal_id) private pure returns (TvmCell) {
        TvmBuilder builder;
        builder.store(proposal_id);
        return builder.toCell();
    }

    function _lockedTokens() private view returns (uint128 locked) {
        locked = 0;
        for ((,uint128 locked_val) : _tmp_proposals) {
            locked += locked_val;
        }

        for ((, uint128 locked_val) : created_proposals) {
            locked += locked_val;
        }
    }
}
