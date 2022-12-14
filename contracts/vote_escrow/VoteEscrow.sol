pragma ever-solidity ^0.62.0;
pragma AbiHeader expire;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../libraries/Errors.sol";
import "./base/vote_escrow/VoteEscrowBase.sol";


contract VoteEscrow is VoteEscrowBase {
    constructor(address _owner, address _qube, address _dao) public {
        // Deployed by Deployer contract
        require (msg.sender.value != 0, Errors.BAD_SENDER);
        owner = _owner;
        qube = _qube;
        dao = _dao;

        _setupTokenWallet();
    }

    function upgrade(TvmCell code,  Callback.CallMeta meta) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);

        TvmCell data = abi.encode(
            meta,
            deploy_nonce,
            platformCode,
            veAccountCode,
            ve_account_version,
            ve_version,
            owner,
            pendingOwner,
            dao,
            qube,
            qubeWallet,
            treasuryTokens,
            teamTokens,
            distributionScheme,
            qubeBalance,
            veQubeBalance,
            lastUpdateTime,
            distributionSupply,
            distributionSchedule,
            veQubeAverage,
            veQubeAveragePeriod,
            qubeMinLockTime,
            qubeMaxLockTime,
            initialized,
            paused,
            emergency,
            currentEpoch,
            currentEpochStartTime,
            currentEpochEndTime,
            currentVotingStartTime,
            currentVotingEndTime,
            currentVotingTotalVotes,
            epochTime,
            votingTime,
            timeBeforeVoting,
            gaugeMaxVotesRatio,
            gaugeMinVotesRatio,
            gaugeMaxDowntime,
            votingNormalizing, // new field
            emissionDebt, // new field
            maxGaugesPerVote,
            gaugesNum,
            gaugeWhitelist,
            currentVotingVotes,
            gaugeDowntimes,
            gaugeWhitelistPrice,
            whitelistPayments,
            deposit_nonce,
            pending_deposits
        );

        // set code after complete this method
        tvm.setcode(code);

        // run onCodeUpgrade from new code
        tvm.setCurrentCode(code);
        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell upgrade_data) private {
        tvm.resetStorage();
        tvm.rawReserve(_reserve(), 0);

        Callback.CallMeta meta;
        (
            meta,
            deploy_nonce,
            platformCode,
            veAccountCode,
            ve_account_version,
            ve_version,
            owner,
            pendingOwner,
            dao,
            qube,
            qubeWallet,
            treasuryTokens,
            teamTokens,
            distributionScheme,
            qubeBalance,
            veQubeBalance,
            lastUpdateTime,
            distributionSupply,
            distributionSchedule,
            veQubeAverage,
            veQubeAveragePeriod,
            qubeMinLockTime,
            qubeMaxLockTime,
            initialized,
            paused,
            emergency,
            currentEpoch,
            currentEpochStartTime,
            currentEpochEndTime,
            currentVotingStartTime,
            currentVotingEndTime,
            currentVotingTotalVotes,
            epochTime,
            votingTime,
            timeBeforeVoting,
            gaugeMaxVotesRatio,
            gaugeMinVotesRatio,
            gaugeMaxDowntime,
            maxGaugesPerVote,
            gaugesNum,
            gaugeWhitelist,
            currentVotingVotes,
            gaugeDowntimes,
            gaugeWhitelistPrice,
            whitelistPayments,
            deposit_nonce,
            pending_deposits
        ) = abi.decode(
            upgrade_data,
            (
                Callback.CallMeta,
                uint32,
                TvmCell,
                TvmCell,
                uint32,
                uint32,
                address,
                address,
                address,
                address,
                address,
                uint128,
                uint128,
                uint32[],
                uint128,
                uint128,
                uint32,
                uint128,
                uint128[],
                uint128,
                uint32,
                uint32,
                uint32,
                bool,
                bool,
                bool,
                uint32,
                uint32,
                uint32,
                uint32,
                uint32,
                uint128,
                uint32,
                uint32,
                uint32,
                uint32,
                uint32,
                uint8,
                uint32,
                uint32,
                mapping (address => bool),
                mapping (address => uint128) ,
                mapping (address => uint8),
                uint128,
                uint128,
                uint32,
                mapping (uint32 => PendingDeposit)
            )
        );

        // fix wrong gauges num, caused by lack of duplicate check on admin whitelist func
        gaugesNum = uint32(gaugeWhitelist.keys().length);
        // migrate to new normalizing logic
        votingNormalizing = VotingNormalizingType.overflowTreasury;
        meta.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }
}
