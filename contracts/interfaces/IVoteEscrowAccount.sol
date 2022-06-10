pragma ever-solidity ^0.60.0;


interface IVoteEscrowAccount {
    struct QubeDeposit {
        uint128 amount; // amount of qubes deposited
        uint128 veAmount; // amount of ve qubes minted for qubes, expire after deposit_time + lock_time
        uint32 createdAt; // timestamp of deposit
        uint32 lockTime; // lock interval
    }
    function processVote(
        uint32 voteEpoch, mapping (address => uint128) votes, uint32 call_id, uint32 nonce, address send_gas_to
    ) external;
    function processDeposit(
        uint32 deposit_nonce,
        uint128 qube_amount,
        uint128 ve_amount,
        uint32 lock_time,
        uint32 nonce,
        address send_gas_to
    ) external;
    function processWithdraw(uint32 call_id, uint32 nonce, address send_gas_to) external;
    function getVeAverage(address callback_receiver, uint32 callback_nonce, uint32 sync_time) external;
    function upgrade(TvmCell new_code, uint32 new_version, uint32 call_id, uint32 nonce, address send_gas_to) external;
}
