pragma ever-solidity ^0.62.0;


import "../../interfaces/IVoteEscrow.sol";


abstract contract VoteEscrowStorage is IVoteEscrow {
    uint64 static deploy_nonce;
    TvmCell platformCode;
    TvmCell veAccountCode;
    uint32 ve_account_version;
    uint32 ve_version;

    address owner;
    address pendingOwner;
    address qube;
    address qubeWallet;
    address dao;

    uint128 treasuryTokens;
    uint128 teamTokens;

    uint32 constant DISTRIBUTION_SCHEME_TOTAL = 10000;
    // should have 3 elems. 0 - farming, 1 - treasury, 2 - team
    uint32[] public distributionScheme;

    uint128 qubeBalance;
    uint128 veQubeBalance;
    uint32 lastUpdateTime;

    uint128 distributionSupply; // current balance of tokens reserved for distribution
    // Array of distribution amount for all epochs
    uint128[] public distributionSchedule;

    uint128 veQubeAverage;
    uint32 veQubeAveragePeriod;

    uint32 qubeMinLockTime = 7 * 24 * 60 * 60; // 7 days
    uint32 qubeMaxLockTime = 4 * 365 * 60 * 60; // 4 years

    bool initialized; // require origin epoch to be created
    bool paused; // pause contract in case of some error or update, disable user actions
    bool emergency; // allow admin to withdraw all qubes + allow users to withdraw qubes bypassing lock

    uint32 currentEpoch;
    uint32 currentEpochStartTime;
    uint32 currentEpochEndTime;
    uint32 currentVotingStartTime;
    uint32 currentVotingEndTime;
    uint128 currentVotingTotalVotes;

    uint32 epochTime; // length of epoch in seconds
    uint32 votingTime; // length of voting in seconds
    uint32 timeBeforeVoting; // time after epoch start when next voting will take place

    uint32 constant MAX_VOTES_RATIO = 10000;
    uint32 gaugeMaxVotesRatio; // up to 10000 (100%). Gauge cant have more votes. All exceeded votes will be distributed among other gauges
    uint32 gaugeMinVotesRatio; // up to 10000 (100%). If gauge doesn't have min votes, it will not be elected in epoch
    uint8 gaugeMaxDowntime; // if gauge was not elected for N times in a row, it is deleted from whitelist

    uint32 maxGaugesPerVote; // max number of gauges user can vote for
    uint32 gaugesNum; // current number of whitelisted gauges
    mapping (address => bool) public gaugeWhitelist;
    mapping (address => uint128) public currentVotingVotes;
    mapping (address => uint8) public gaugeDowntimes;

    // amount of QUBE tokens user should pay to add his gauge to QUBE dao
    uint128 gaugeWhitelistPrice;
    // amount of QUBEs available for withdraw as payments for whitelist
    uint128 whitelistPayments;

    uint128 constant SCALING_FACTOR = 10**18;

    uint32 deposit_nonce;
    mapping (uint32 => PendingDeposit) pending_deposits;

    uint128 constant CONTRACT_MIN_BALANCE = 0.5 ton;
    uint32 constant MAX_ITERATIONS_PER_COUNT = 35;
}
