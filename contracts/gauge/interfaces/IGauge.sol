pragma ever-solidity ^0.62.0;


import "../../libraries/Callback.sol";


interface IGauge {
    // Events
    event Deposit(
        uint32 call_id, address user, uint128 amount, uint128 boosted_amount,
        uint32 lock_time, uint128 totalBoostedSupply, uint128 lockBoostedSupply
    );
    event DepositRevert(uint32 call_id, address user, uint128 amount);
    event Withdraw(uint32 call_id, address user, uint128 amount, uint128 totalBoostedSupply, uint128 lockBoostedSupply);
    event WithdrawRevert(uint32 call_id, address user);
    event Claim(
        uint32 call_id, address user, uint128 qube_reward, uint128[] extra_reward,
        uint128 qube_debt, uint128[] extra_debt, uint128 totalBoostedSupply, uint128 lockBoostedSupply
    );
    event LockBoostedBurn(address user, uint128 lock_boosted_burned);
    event WithdrawUnclaimed(uint32 call_id, address to, uint128[] extra_amounts);

    event RewardDeposit(uint32 call_id, address sender, uint256 reward_id, uint128 amount);
    event ExtraFarmEndSet(uint32 call_id, uint256 id, uint32 farm_end_time);
    event GaugeAccountCodeUpdated(uint32 call_id, uint32 prev_version, uint32 new_version);
    event GaugeAccountCodeUpdateRejected(uint32 call_id);
    event GaugeUpdated(uint32 prev_version, uint32 new_version);
    event RewardRoundAdded(uint32 call_id, uint256 id, RewardRound new_reward_round);
    event QubeRewardRoundAdded(RewardRound new_qube_round);

    event GaugeAccountUpgrade(uint32 call_id, address user, uint32 old_version, uint32 new_version);
    event GaugeAccountDeploy(address user);

    struct GaugeSyncData {
        uint128 depositSupply;
        uint128 depositSupplyAverage;
        uint32 depositSupplyAveragePeriod;
        RewardRound[][] extraRewardRounds;
        RewardRound[] qubeRewardRounds;
        uint32 poolLastRewardTime;
    }

    struct RewardRound {
        uint32 startTime;
        uint32 endTime;
        uint128 rewardPerSecond;
        uint256 accRewardPerShare; // snapshot on the moment of round end
    }

    struct TokenData {
        address root;
        address wallet;
        uint128 balance;
        uint128 cumulativeBalance;
    }

    struct PendingDeposit {
        address user;
        uint128 amount;
        uint128 boosted_amount;
        uint32 lock_time;
        bool claim;
        Callback.CallMeta meta;
    }
    function finishDeposit(
        address user,
        uint128 qube_reward,
        uint128[] extra_rewards,
        bool claim,
        uint128 boosted_bal_old,
        uint128 boosted_bal_new,
        uint32 _deposit_nonce
    ) external;
    function finishWithdraw(
        address user,
        uint128 amount,
        uint128 qube_reward,
        uint128[] extra_reward,
        bool claim,
        uint128 boosted_bal_old,
        uint128 boosted_bal_new,
        Callback.CallMeta meta
    ) external;
    function finishClaim(
        address user,
        uint128 qube_amount,
        uint128[] extra_amounts,
        uint128 boosted_bal_old,
        uint128 boosted_bal_new,
        Callback.CallMeta meta
    ) external;
    function revertWithdraw(address user, Callback.CallMeta meta) external;
    function revertDeposit(address user, uint32 _deposit_nonce) external;
    function burnLockBoostedBalance(address user, uint128 expired_boosted) external;
    function forceUpgradeGaugeAccount(address user, Callback.CallMeta meta) external view;
    function upgrade(TvmCell new_code, uint32 new_version, Callback.CallMeta meta) external;
    function updateGaugeAccountCode(TvmCell new_code, uint32 new_version, Callback.CallMeta meta) external;
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
