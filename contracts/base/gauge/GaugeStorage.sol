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
    uint128 constant CONTRACT_MIN_BALANCE = 1 ton;
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

    uint32 deposit_nonce = 0;
    // this is used to prevent data loss on bounced messages during deposit
    mapping (uint64 => PendingDeposit) deposits;

    // TODO: remove useless from static
    TvmCell static platformCode;
    TvmCell static gaugeAccountCode;
    address static factory;
    uint64 static deploy_nonce;
    uint32 static gauge_account_version;
    uint32 static gauge_version;
}