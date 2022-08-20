pragma ever-solidity ^0.62.0;
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
        address dao,
        uint32 start_offset,
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
    ) external view onlyOwner returns (address _vote_escrow) {
        tvm.accept();
        require (!VoteEscrowCode.toSlice().empty(), 1000);
        require (!PlatformCode.toSlice().empty(), 1000);
        require (!veAccountCode.toSlice().empty(), 1000);

        TvmCell stateInit = tvm.buildStateInit({
            contr: VoteEscrow,
            varInit: {
                deploy_nonce: uint32(_randomNonce)
            },
            pubkey: tvm.pubkey(),
            code: VoteEscrowCode
        });

        address ve = new VoteEscrow{
            stateInit: stateInit,
            value: 1 ever,
            wid: address(this).wid,
            flag: MsgFlag.SENDER_PAYS_FEES
        }(address(this), qube, dao);

        Callback.CallMeta meta = Callback.CallMeta(0, 0, ve);
        IVoteEscrow(ve).installPlatformCode{value: 0.5 ever, flag: MsgFlag.SENDER_PAYS_FEES}(PlatformCode, meta);
        IVoteEscrow(ve).installOrUpdateVeAccountCode{value: 0.5 ever, flag: MsgFlag.SENDER_PAYS_FEES}(veAccountCode, meta);
        IVoteEscrow(ve).setVotingParams{value: 0.5 ever, flag: MsgFlag.SENDER_PAYS_FEES}(
            epoch_time, time_before_voting, voting_time, gauge_min_votes_ratio,
            gauge_max_votes_ratio, gauge_max_downtime, max_gauges_per_vote, meta
        );
        IVoteEscrow(ve).setDistributionScheme{value: 0.5 ever, flag: MsgFlag.SENDER_PAYS_FEES}(distribution_scheme, meta);
        IVoteEscrow(ve).setDistribution{value: 0.5 ever, flag: MsgFlag.SENDER_PAYS_FEES}(distribution, meta);
        IVoteEscrow(ve).setQubeLockTimeLimits{value: 0.5 ever, flag: MsgFlag.SENDER_PAYS_FEES}(min_lock, max_lock, meta);
        IVoteEscrow(ve).setWhitelistPrice{value: 0.5 ever, flag: MsgFlag.SENDER_PAYS_FEES}(whitelist_price, meta);
        IVoteEscrow(ve).initialize{value: 0.5 ever, flag: MsgFlag.SENDER_PAYS_FEES}(start_offset, meta);
        IVoteEscrow(ve).transferOwnership{value: 0.5 ever, flag: MsgFlag.SENDER_PAYS_FEES}(owner, meta);
        return ve;
    }
}
