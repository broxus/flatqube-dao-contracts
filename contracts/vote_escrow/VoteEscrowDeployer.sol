pragma solidity ^0.60.0;
pragma AbiHeader pubkey;
pragma AbiHeader expire;


import "./VoteEscrow.sol";
import "./interfaces/IVoteEscrow.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import '@broxus/contracts/contracts/utils/RandomNonce.sol';
import '@broxus/contracts/contracts/access/ExternalOwner.sol';


contract VoteEscrowDeployer is RandomNonce, ExternalOwner {
    TvmCell static PlatformCode;
    TvmCell static veAccountCode;
    TvmCell VoteEscrowCode; // too big and should be deployed with separate msg

    constructor() public {
        require (tvm.pubkey() != 0, Errors.WRONG_PUBKEY);
        require (tvm.pubkey() == msg.pubkey(), Errors.WRONG_PUBKEY);
        tvm.accept();

        setOwnership(msg.pubkey());
    }

    function installVoteEscrowCode(TvmCell code) external onlyOwner {
        tvm.accept();
        VoteEscrowCode = code;
    }

    function deployVoteEscrow(
        address owner,
        address qube,
        uint32 start_time,
        uint32 min_lock,
        uint32 max_lock,
        uint32[] distribution_scheme,
        uint128[] distribution,
        uint32 epoch_time,
        uint32 time_before_voting,
        uint32 voting_time,
        uint32 gauge_min_votes_ratio,
        uint32 gauge_max_votes_ratio,
        uint8 gauge_max_downtime,
        uint32 max_gauges_per_vote,
        uint128 whitelist_price
    ) external onlyOwner returns (address _vote_escrow) {
        tvm.accept();
        require (!VoteEscrowCode.toSlice().empty(), 1000);
        require (!PlatformCode.toSlice().empty(), 1000);
        require (!veAccountCode.toSlice().empty(), 1000);

        TvmCell stateInit = tvm.buildStateInit({
            contr: VoteEscrow,
            varInit: {
                deploy_nonce: uint64(_randomNonce)
            },
            pubkey: tvm.pubkey(),
            code: VoteEscrowCode
        });

        address ve = new VoteEscrow{
            stateInit: stateInit,
            value: 5 ton,
            wid: address(this).wid,
            flag: MsgFlag.SENDER_PAYS_FEES
        }(address(this), qube);

        IVoteEscrow(ve).installPlatformCode{value: 1.5 ton, flag: MsgFlag.SENDER_PAYS_FEES}(PlatformCode, ve);
        IVoteEscrow(ve).installOrUpdateVeAccountCode{value: 1.5 ton, flag: MsgFlag.SENDER_PAYS_FEES}(veAccountCode, ve);
        IVoteEscrow(ve).setVotingParams{value: 1.5 ton, flag: MsgFlag.SENDER_PAYS_FEES}(
            epoch_time, time_before_voting, voting_time, gauge_min_votes_ratio,
            gauge_max_votes_ratio, gauge_max_downtime, max_gauges_per_vote, 0, ve
        );
        IVoteEscrow(ve).setDistributionScheme{value: 1.5 ton, flag: MsgFlag.SENDER_PAYS_FEES}(distribution_scheme, 0, ve);
        IVoteEscrow(ve).setDistribution{value: 1.5 ton, flag: MsgFlag.SENDER_PAYS_FEES}(distribution, 0, ve);
        IVoteEscrow(ve).setQubeLockTimeLimits{value: 1.5 ton, flag: MsgFlag.SENDER_PAYS_FEES}(min_lock, max_lock, 0, ve);
        IVoteEscrow(ve).setWhitelistPrice{value: 1.5 ton, flag: MsgFlag.SENDER_PAYS_FEES}(whitelist_price, 0, ve);
        IVoteEscrow(ve).initialize{value: 1.5 ton, flag: MsgFlag.SENDER_PAYS_FEES}(start_time, ve);
        IVoteEscrow(ve).transferOwnership{value: 1.5 ton, flag: MsgFlag.SENDER_PAYS_FEES}(owner, ve);
        return ve;
    }
}
