pragma ever-solidity ^0.62.0;


import "../../interfaces/IGauge.sol";
import "../../interfaces/IGaugeAccount.sol";


abstract contract GaugeAccountStorage is IGaugeAccount {
    uint32 current_version;

    // amount of all deposited tokens
    uint128 balance;
    // balance + bonus for locking deposit on moment of last action
    uint128 lockBoostedBalance;
    // balance + ve boost on moment of last action
    uint128 veBoostedBalance;
    // balance + lock boost + ve boost on moment of last action
    uint128 totalBoostedBalance;
    // aggregated amount of locked deposited tokens
    uint128 lockedBalance;
    // full state of user stats from all contracts (ve/veAcc/gauge) on moment of last action
    Averages lastAverageState;
    // same as above, but is used during sync
    Averages curAverageState;

    // timestamp of last update e.g updating average while syncing
    uint32 lastUpdateTime;
    // number of locked deposits. We need it for gas calculations
    uint32 lockedDepositsNum;

    address gauge;
    address user;
    address voteEscrow;
    address veAccount;

    // locked deposits are stored independently
    mapping (uint64 => DepositData) lockedDeposits;

    RewardData qubeReward;
    RewardData[] extraReward;

    VestingData qubeVesting;
    VestingData[] extraVesting;

    uint32 _nonce;
    mapping (uint32 => PendingWithdraw) _withdraws;
    mapping (uint32 => PendingDeposit) _deposits;
    mapping (uint32 => PendingClaim) _claims;
    mapping (uint32 => ActionType) _actions;
    mapping (uint32 => SyncData) _sync_data;

    uint128 constant CONTRACT_MIN_BALANCE = 0.3 ton;
    uint32 constant MAX_VESTING_RATIO = 1000;
    uint256 constant SCALING_FACTOR = 1e18;
    uint128 constant MAX_ITERATIONS_PER_MSG = 50;
}
