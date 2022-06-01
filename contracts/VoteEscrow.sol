pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";
import "./libraries/Errors.sol";
import "./base/vote_escrow/VoteEscrowBase.sol";


contract VoteEscrow is VoteEscrowBase {
    constructor(address _owner, address _qube) public {
        require (tvm.pubkey() != 0, Errors.WRONG_PUBKEY);
        require (tvm.pubkey() == msg.pubkey(), Errors.WRONG_PUBKEY);
        tvm.accept();

        owner = _owner;
        qube = _qube;

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
            qube,
            qubeWallet,
            treasuryTokens,
            teamTokens,
            distributionScheme,
            qubeBalance,
            veQubeSupply,
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
            whitelistedGauges,
            currentVotingVotes,
            gaugeDowntime,
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

    function onCodeUpgrade(TvmCell upgrade_data) private {}
}
