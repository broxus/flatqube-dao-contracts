pragma ever-solidity ^0.62.0;
pragma AbiHeader expire;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../libraries/Errors.sol";
import "../vote_escrow/base/vote_escrow/VoteEscrowBase.sol";


contract TestVoteEscrow is VoteEscrowBase {
    constructor(address _owner, address _qube, address _dao) public {
        // Deployed by Deployer contract
        require (msg.sender.value != 0, Errors.BAD_SENDER);
        owner = _owner;
        qube = _qube;
        dao = _dao;

        _setupTokenWallet();
    }

    function upgrade(TvmCell code, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);

        TvmCell data = abi.encode(
            send_gas_to,
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
        );

        // set code after complete this method
        tvm.setcode(code);

        // run onCodeUpgrade from new code
        tvm.setCurrentCode(code);
        onCodeUpgrade(data);
    }

    event Upgrade(uint32 old_version, uint32 new_version);

    function onCodeUpgrade(TvmCell) private {
        ve_version += 1;
        emit Upgrade(ve_version - 1, ve_version);
    }
}
