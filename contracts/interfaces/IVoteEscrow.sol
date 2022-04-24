pragma ton-solidity ^0.57.1;


import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";


interface IVoteEscrow is IAcceptTokensTransferCallback {
    event Deposit(uint32 call_id, address user, uint128 amount, uint128 ve_amount, uint32 lock_time);
    event DepositRevert(uint32 call_id, address user, uint128 amount);
    event GaugeWhitelist(uint32 call_id, address gauge);
    event GaugeRemoveWhitelist(uint32 call_id, address gauge);
    event WhitelistPriceUpdate(uint32 call_id, uint128 amount);
    event DistributionSupplyIncrease(uint32 call_id, uint128 amount);
    event Withdraw(uint32 call_id, address user, uint128 amount);
    event WithdrawRevert(uint32 call_id, address user);
    event VeQubesBurn(address user, uint128 amount);
    event VoteEscrowAccountDeploy(address user);
    event Initialize(uint32 init_time, uint32 epoch_start, uint32 epoch_end);
    event DistributionScheduleUpdate(uint32 call_id, uint128[] distribution);
    event DistributionSchemeUpdate(uint32 call_id, uint32[] distribution_scheme);
    event VotingStart(uint32 call_id, uint32 start, uint32 end);
    event Vote(uint32 call_id, address user, mapping (address => uint128) votes);
    event VoteRevert(uint32 call_id, address user);
    event VotingEnd(
        uint32 call_id,
        mapping (address => uint128) votes,
        uint128 total_votes,
        uint128 treasury_votes,
        uint32 new_epoch,
        uint32 new_epoch_start,
        uint32 new_epoch_end
    );
    event EpochDistribution(
        uint32 call_id,
        uint32 epoch_num,
        mapping (address => uint128) farming_distribution,
        uint128 team_tokens,
        uint128 treasury_tokens
    );
    event TreasuryWithdraw(
        uint32 call_id,
        address receiver,
        uint128 amount
    );
    event TeamWithdraw(
        uint32 call_id,
        address receiver,
        uint128 amount
    );

    struct PendingDeposit {
        address user;
        uint128 amount;
        uint128 ve_amount;
        uint32 lock_time;
        address send_gas_to;
        uint32 nonce;
        uint32 call_id;
    }

    enum DepositType { userDeposit, whitelist, adminDeposit }

    function getVeAverage(uint32 nonce) external;
    function finishDeposit(address user, uint32 deposit_nonce) external;
    function revertDeposit(address user, uint32 deposit_nonce) external;
    function revertWithdraw(address user, uint32 call_id, uint32 nonce, address send_gas_to) external;
    function finishWithdraw(address user, uint128 unlockedQubes, uint32 call_id, uint32 nonce, address send_gas_to) external;
    function burnVeQubes(address user, uint128 expiredVeQubes) external;
    function finishVote(address user, mapping (address => uint128) votes, uint32 call_id, uint32 nonce, address send_gas_to) external;
    function revertVote(address user, uint32 call_id, uint32 nonce, address send_gas_to) external;
}