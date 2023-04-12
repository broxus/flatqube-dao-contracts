pragma ever-solidity ^0.62.0;

import "../../libraries/Callback.sol";


interface IVoteEscrowAccount {
    struct QubeDeposit {
        uint128 amount; // amount of qubes deposited
        uint128 veAmount; // amount of ve qubes minted for qubes, expire after deposit_time + lock_time
        uint32 createdAt; // timestamp of deposit
        uint32 lockTime; // lock interval
    }
    function processVoteEpoch(
        uint32 voteEpoch, mapping (address => uint128) votes, Callback.CallMeta meta
    ) external;
    function processDeposit(
        uint32 deposit_nonce,
        uint128 qube_amount,
        uint128 ve_amount,
        uint32 lock_time,
        Callback.CallMeta meta
    ) external;
    function processWithdraw(Callback.CallMeta meta) external;
    function getVeAverage(address callback_receiver, uint32 callback_nonce, uint32 sync_time) external;
    function upgrade(TvmCell new_code, uint32 new_version, Callback.CallMeta meta) external;

    // DAO
    function propose(TvmCell proposal_data, uint128 threshold) external;
    function onProposalDeployed(uint32 nonce, uint32 proposal_id, uint32 answer_id) external;
    function unlockVoteTokens(uint32 proposal_id, bool success) external;
    function rejectVote(uint32 proposal_id) external;
    function unlockCastedVote(uint32 proposal_id, bool success) external;
    function castVote(uint32 proposal_id, bool support, string reason) external;
    function voteCasted(uint32 proposal_id) external;
    function tryUnlockVoteTokens(uint32 proposal_id) external view;
    function tryUnlockCastedVotes(uint32[] proposalIds) external view;
    function lockedTokens() external view responsible returns(uint128);

    // DAO
    event VoteCast(uint32 proposal_id, bool support, uint128 votes, string reason);
    event UnlockVotes(uint32 proposal_id, uint128 value);
    event UnlockCastedVotes(uint32 proposal_id);
    event ProposalCreationRejected(uint128 votes_available, uint128 threshold);
    event ProposalCodeUpgraded(uint128 votes_available, uint128 threshold);
}
