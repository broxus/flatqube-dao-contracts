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
    event PauseUpdate(uint32 call_id, bool new_state);
    event EmergencyUpdate(uint32 call_id, bool new_state);
    event PlatformCodeInstall();
    event VeAccountCodeUpgrade(uint32 old_version, uint32 new_version);
    event VoteEscrowAccountUpgrade(uint32 call_id, address user, uint32 old_version, uint32 new_versioin);

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
}