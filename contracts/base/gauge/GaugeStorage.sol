pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";

import "../../interfaces/IGaugeAccount.sol";
import "../../interfaces/IGauge.sol";
import "../../interfaces/IFactory.sol";
import "../../GaugeAccount.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


abstract contract GaugeStorage is IGauge, IAcceptTokensTransferCallback {
    // constants
    uint128 constant TOKEN_WALLET_DEPLOY_VALUE = 0.5 ton;
    uint128 constant TOKEN_WALLET_DEPLOY_GRAMS_VALUE = 0.1 ton;
    uint128 constant MIN_CALL_MSG_VALUE = 1 ton;
    uint128 constant GAUGE_ACCOUNT_DEPLOY_VALUE = 0.2 ton;
    uint128 constant GAUGE_ACCOUNT_UPGRADE_VALUE = 1 ton;
    uint128 constant REQUEST_UPGRADE_VALUE = 1.5 ton;
    uint128 constant TOKEN_TRANSFER_VALUE = 1 ton;
    uint128 constant FACTORY_DEPLOY_CALLBACK_VALUE = 0.1 ton;
    uint128 constant ADD_REWARD_ROUND_VALUE = 0.5 ton;
    uint128 constant SET_END_TIME_VALUE = 0.5 ton;
    uint128 constant INCREASE_DEBT_VALUE = 0.3 ton;
    uint128 constant CONTRACT_MIN_BALANCE = 1 ton;

    uint32 constant MAX_UINT32 = 0xFFFFFFFF;
    uint128 constant SCALING_FACTOR = 1e18;

    // for additional tokens owner will be allowed to withdraw all funds after extraFarmEndTime + this
    uint32 withdrawAllLockPeriod;
    // time when reward what updated last time
    uint32 lastRewardTime;

    // deposit token data
    address depositTokenRoot;
    address depositTokenWallet;
    uint128 depositTokenBalance;

    // VE contract that manage qube emission
    address voteEscrow;

    // reward params for qube
    QubeRewardData qubeReward;
    // reward params for additional tokens
    ExtraRewardData[] extraRewards;
    // deserializing structure is very expensive, so that we store vars that we send to other contracts separately
    uint32[] extraVestingPeriods;
    uint32[] extraVestingRatios;

    address owner;

    uint64 deposit_nonce = 0;
    // this is used to prevent data loss on bounced messages during deposit
    mapping (uint64 => PendingDeposit) deposits;

    TvmCell static platformCode;
    TvmCell static gaugeAccountCode;
    address static factory;
    uint64 static deploy_nonce;
    uint32 static gauge_account_version;
    uint32 static gauge_version;
}