pragma ton-solidity ^0.58.2;
pragma AbiHeader expire;

interface IGauge {
    // Events
    event Deposit(address user, uint128 amount);
    event Withdraw(address user, uint128 amount);
    event Claim(address user, uint128 qube_reward, uint128[] extra_reward, uint128 qube_debt, uint128[] extra_debt);

    event RewardDeposit(address token_root, uint128 amount);
    event ExtraFarmEndSet(uint128[] ids, uint32[] farm_end_times);
    event GaugeAccountCodeUpdated(uint32 prev_version, uint32 new_version);
    event GaugeUpdated(uint32 prev_version, uint32 new_version);
    event RewardRoundAdded(uint128[] ids, RewardRound[] reward_rounds);

    struct RewardRound {
        uint32 startTime;
        uint128 rewardPerSecond;
    }

    struct RewardTokenData {
        uint256 accRewardPerShare;
        address tokenRoot;
        address tokenWallet;
        uint128 tokenBalance;
        uint128 tokenBalanceCumulative;
        uint32 vestingPeriod;
        uint32 vestingRatio;
    }

    struct ExtraRewardData {
        RewardTokenData mainData;
        RewardRound[] rewardRounds;
        uint32 farmEndTime;
    }

    struct QubeRewardData {
        RewardTokenData mainData;
        // qube current reward speed
        uint128 rewardPerSecond;
        // qube reward speed for future epoch
        uint128 nextEpochRewardPerSecond;
        // timestamp when qubeRewardPerSecond will be changed
        uint32 nextEpochTime;
        // timestamp when next epoch will end
        // we need this for case when next epoch wont end in time, so that farm speed will be 0 after that point
        uint32 nextEpochEndTime;
    }

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
        address send_gas_to;
        uint32 nonce;
    }
    function finishDeposit(
        uint64 _nonce,
        uint128[] vested
    ) external;
    function finishWithdraw(
        address user,
        uint128 withdrawAmount,
        uint128[] vested,
        address send_gas_to,
        uint32 nonce
    ) external;
    function forceUpgradeGaugeAccount(address user, address send_gas_to) external;
    function finishSafeWithdraw(address user, uint128 amount, address send_gas_to) external;
    function upgrade(TvmCell new_code, uint32 new_version, address send_gas_to) external;
    function updateGaugeAccountCode(TvmCell new_code, uint32 new_version, address send_gas_to) external;
}
