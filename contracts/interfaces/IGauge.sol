pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;

interface IGauge {
    // Events
    event Deposit(uint32 call_id, address user, uint128 amount, uint32 lock_time);
    event DepositReverted(uint32 call_id, address user, uint128 amount);
    event Withdraw(uint32 call_id, address user, uint128 amount);
    event WithdrawUnclaimed(uint32 call_id, address receiver, uint128[] amounts);
    event Claim(uint32 call_id, address user, uint128 qube_reward, uint128[] extra_reward, uint128 qube_debt, uint128[] extra_debt);

    event RewardDeposit(uint32 call_id, uint256 reward_id, uint128 amount);
    event ExtraFarmEndSet(uint32 call_id, uint256[] ids, uint32[] farm_end_times);
    event GaugeAccountCodeUpdated(uint32 call_id, uint32 prev_version, uint32 new_version);
    event GaugeAccountCodeUpdateRejected(uint32 call_id);
    event GaugeUpdated(uint32 prev_version, uint32 new_version);
    event RewardRoundAdded(uint32 call_id, uint256[] ids, RewardRound[] reward_rounds);
    event QubeRewardRoundAdded(RewardRound new_qube_round);

    event GaugeAccountUpgrade(uint32 call_id, address user, uint32 old_version, uint32 new_version);
    event GaugeAccountDeploy(address user);

    struct RewardRound {
        uint32 startTime;
        uint32 endTime;
        uint128 rewardPerSecond;
        uint256 accRewardPerShare; // snapshot on the moment of round end
    }

    struct TokenData {
        address tokenRoot;
        address tokenWallet;
        uint128 tokenBalance;
    }

    struct ExtraRewardData {
        TokenData tokenData;
        RewardRound[] rewardRounds;
        bool ended;
    }

    struct QubeRewardData {
        TokenData tokenData;
        RewardRound[] rewardRounds;
        uint32 vestingPeriod;
        uint32 vestingRatio;
    }

    // TODO: up
    struct Details {
        uint32 lastRewardTime;
        address voteEscrow;
        address depositTokenRoot;
        address depositTokenWallet;
        uint128 depositTokenBalance;
        QubeRewardData qubeReward;
        ExtraRewardData[] extraRewards;
        address owner;
        address factory;
        uint32 gauge_account_version;
        uint32 gauge_version;
    }
    struct PendingDeposit {
        address user;
        uint128 amount;
        uint32 lock_time;
        address send_gas_to;
        uint32 nonce;
        uint32 call_id;
    }
    function finishDeposit(
        address user,
        uint64 _nonce
    ) external;
    function finishWithdraw(
        address user,
        uint128 withdrawAmount,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external;
    function finishClaim(
        address user,
        uint128 qube_amount,
        uint128[] extra_amounts,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external;
    function revertDeposit(address user, uint64 _deposit_nonce) external;
    function forceUpgradeGaugeAccount(address user, uint32 call_id, uint32 nonce, address send_gas_to) external;
    function upgrade(TvmCell new_code, uint32 new_version, address send_gas_to) external;
    function updateGaugeAccountCode(TvmCell new_code, uint32 new_version, uint32 call_id, address send_gas_to) external;
    function onGaugeAccountDeploy(address user, address send_gas_to) external;
    function receiveTokenWalletAddress(address wallet) external;
}
