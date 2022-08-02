pragma ever-solidity ^0.62.0;


interface IGauge {
    // Events
    event Deposit(uint32 call_id, address user, uint128 amount, uint32 lock_time);
    event DepositRevert(uint32 call_id, address user, uint128 amount);
    event Withdraw(uint32 call_id, address user, uint128 amount);
    event WithdrawRevert(uint32 call_id, address user);
    event Claim(uint32 call_id, address user, uint128 qube_reward, uint128[] extra_reward, uint128 qube_debt, uint128[] extra_debt);
    event LockBoostedBurn(address user, uint128 lock_boosted_burned);
    event WithdrawUnclaimed(uint32 call_id, address to, uint128[] extra_amounts);

    event RewardDeposit(uint32 call_id, uint256 reward_id, uint128 amount);
    event ExtraFarmEndSet(uint32 call_id, uint256[] ids, uint32[] farm_end_times);
    event GaugeAccountCodeUpdated(uint32 call_id, uint32 prev_version, uint32 new_version);
    event GaugeAccountCodeUpdateRejected(uint32 call_id);
    event GaugeUpdated(uint32 prev_version, uint32 new_version);
    event RewardRoundAdded(uint32 call_id, uint256 ids, RewardRound new_reward_round, RewardRound[] updated_reward_rounds);
    event QubeRewardRoundAdded(RewardRound new_qube_round, RewardRound[] updated_qube_rounds);

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

    struct PendingDeposit {
        address user;
        uint128 amount;
        uint128 boosted_amount;
        uint32 lock_time;
        bool claim;
        address send_gas_to;
        uint32 nonce;
        uint32 call_id;
    }
    function finishDeposit(
        address user,
        uint128 qube_reward,
        uint128[] extra_rewards,
        bool claim,
        uint128 ve_bal_old,
        uint128 ve_bal_new,
        uint32 _deposit_nonce
    ) external;
    function finishWithdraw(
        address user,
        uint128 amount,
        uint128 qube_reward,
        uint128[] extra_reward,
        bool claim,
        uint128 ve_bal_old,
        uint128 ve_bal_new,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external;
    function finishClaim(
        address user,
        uint128 qube_amount,
        uint128[] extra_amounts,
        uint128 ve_bal_old,
        uint128 ve_bal_new,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external;
    function revertWithdraw(address user, uint32 call_id, uint32 nonce, address send_gas_to) external;
    function revertDeposit(address user, uint32 _deposit_nonce) external;
    function burnBoostedBalance(address user, uint128 expired_boosted) external;
    function forceUpgradeGaugeAccount(address user, uint32 call_id, address send_gas_to) external view;
    function upgrade(TvmCell new_code, uint32 new_version, uint32 call_id, address send_gas_to) external;
    function updateGaugeAccountCode(TvmCell new_code, uint32 new_version, uint32 call_id, address send_gas_to) external;
    function onGaugeAccountDeploy(address user, address send_gas_to) external;
    function receiveTokenWalletAddress(address wallet) external;
    function setupTokens(
        address _depositTokenRoot,
        address _qubeTokenRoot,
        address[] _extraRewardTokenRoot
    ) external;
    function setupVesting(
        uint32 _qubeVestingPeriod,
        uint32 _qubeVestingRatio,
        uint32[] _extraVestingPeriods,
        uint32[] _extraVestingRatios,
        uint32 _withdrawAllLockPeriod
    ) external;
    function setupBoostLock(uint32 _maxBoost, uint32 _maxLockTime) external;
    function initialize(uint32 call_id) external;
}
