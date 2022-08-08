pragma ever-solidity ^0.62.0;


import "broxus-token-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";


interface IVoteEscrow is IAcceptTokensTransferCallback {
    event NewOwner(address prev_owner, address new_owner);
    event NewPendingOwner(address pending_owner);
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
    event VotingEndRevert(uint32 call_id);
    event VotingStartedAlready(uint32 call_id, uint32 start, uint32 end);
    event Vote(uint32 call_id, address user, mapping (address => uint128) votes);
    event VoteRevert(uint32 call_id, address user);
    event NewQubeLockLimits(uint32 call_id, uint32 new_min, uint32 new_max);
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
    event PaymentWithdraw(
        uint32 call_id,
        address receiver,
        uint128 amount
    );
    event NewVotingParams(
        uint32 call_id,
        uint32 epochTime,
        uint32 timeBeforeVoting,
        uint32 votingTime,
        uint32 gaugeMinVotesRatio,
        uint32 gaugeMaxVotesRatio,
        uint8 gaugeMaxDowntime,
        uint32 maxGaugesPerVote
    );
    event Pause(uint32 call_id, bool new_state);
    event Emergency(uint32 call_id, bool new_state);
    event PlatformCodeInstall();
    event VeAccountCodeUpdate(uint32 old_version, uint32 new_version);
    event VoteEscrowAccountUpgrade(uint32 call_id, address user, uint32 old_version, uint32 new_version);

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
    function receiveTokenWalletAddress(address wallet) external;
    function getVoteEscrowAccountAddress(address user) external view responsible returns (address);
    function onVoteEscrowAccountDeploy(address user, address send_gas_to) external;
    function deployVoteEscrowAccount(address user) external view returns (address);
    function installPlatformCode(TvmCell code, address send_gas_to) external;
    function installOrUpdateVeAccountCode(TvmCell code, address send_gas_to) external;
    function setVotingParams(
        uint32 epoch_time,
        uint32 time_before_voting,
        uint32 voting_time,
        uint32 gauge_min_votes_ratio,
        uint32 gauge_max_votes_ratio,
        uint8 gauge_max_downtime,
        uint32 max_gauges_per_vote,
        uint32 call_id,
        address send_gas_to
    ) external;
    function setDistributionScheme(uint32[] scheme, uint32 call_id, address send_gas_to) external;
    function setDistribution(uint128[] distribution, uint32 call_id, address send_gas_to) external;
    function setQubeLockTimeLimits(uint32 new_min, uint32 new_max, uint32 call_id, address send_gas_to) external;
    function setWhitelistPrice(uint128 whitelist_price, uint32 call_id, address send_gas_to) external;
    function initialize(uint32 start_time, address send_gas_to) external;
    function transferOwnership(address new_owner, address send_gas_to) external;
    function onVeAccountUpgrade(
        address user,
        uint32 old_version,
        uint32 new_version,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external view;
    function countVotesStep(
        address start_addr,
        uint128 exceeded_votes,
        uint128 valid_votes,
        uint32 call_id,
        address send_gas_to
    ) external;
    function normalizeVotesStep(
        address start_addr,
        uint128 treasury_votes,
        uint128 exceeded_votes,
        uint128 valid_votes,
        uint32 call_id,
        address send_gas_to
    ) external;
    function distributeEpochQubesStep(
        address start_addr,
        uint128 bonus_treasury_votes,
        mapping (address => uint128) distributed,
        uint32 call_id,
        address send_gas_to
    ) external;

    // DAO
    function castVote(uint32 proposal_id, bool support) external view;
    function castVoteWithReason(uint32 proposal_id, bool support, string reason) external view;
    function tryUnlockVoteTokens(uint32 proposal_id) external view;
    function tryUnlockCastedVotes(uint32[] proposal_ids) external view;
}