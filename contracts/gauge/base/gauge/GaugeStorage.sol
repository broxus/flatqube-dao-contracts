pragma ever-solidity ^0.62.0;


import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRootUpgradeable.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWalletUpgradeable.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";

import "../../interfaces/IGaugeAccount.sol";
import "../../interfaces/IGauge.sol";
import "../../GaugeAccount.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


abstract contract GaugeStorage is IGauge, IAcceptTokensTransferCallback {
    // constants
    uint128 constant CONTRACT_MIN_BALANCE = 1 ever;
    uint8 constant MAX_STORED_ROUNDS = 10;

    uint32 constant MAX_UINT32 = 0xFFFFFFFF;
    uint128 constant SCALING_FACTOR = 1e18;

    // for additional tokens owner will be allowed to withdraw all funds after extraFarmEndTime + this
    uint32 withdrawAllLockPeriod;
    // time when reward what updated last time
    uint32 lastRewardTime;
    // index used in updating reward round info
    uint256[] lastExtraRewardRoundIdx;
    // index used in updating reward round info
    uint256 lastQubeRewardRoundIdx;

    uint32 lastAverageUpdateTime;
    // sum of all deposits boosted with locks
    uint128 lockBoostedSupply;
    // average sum of all lock-boosted deposits
    uint128 lockBoostedSupplyAverage;
    uint32 lockBoostedSupplyAveragePeriod;

    // average sum of all deposits
    uint128 supplyAverage;
    uint32 supplyAveragePeriod;

    // sum of all deposits boosted with locks + with veQubes
    uint128 totalBoostedSupply;

    address owner;
    // VE contract that manage qube emission
    address voteEscrow;

    uint32 maxBoost; // should be bigger than BOOST_BASE. 1200 == 1.2x max boost that could be reached on maxLockTime
    uint32 maxLockTime;
    uint32 constant BOOST_BASE = 1000;

    uint8 init_mask = 1;
    bool initialized;

    // deposit token data
    TokenData depositTokenData;

    // qube data
    // storing in structs is better, but much more expensive
    TokenData qubeTokenData;
    RewardRound[] qubeRewardRounds;
    uint32 qubeVestingPeriod;
    uint32 qubeVestingRatio;

    // extra rewards data
    TokenData[] extraTokenData;
    RewardRound[][] extraRewardRounds;
    uint32[] extraVestingPeriods;
    uint32[] extraVestingRatios;
    bool[] extraRewardEnded;

    uint32 deposit_nonce = 0;
    // this is used to prevent data loss on bounced messages during deposit
    mapping (uint64 => PendingDeposit) deposits;

    TvmCell static platformCode;
    TvmCell static gaugeAccountCode;
    address static factory;
    uint32 static deploy_nonce;
    uint32 static gauge_account_version;
    uint32 static gauge_version;
}