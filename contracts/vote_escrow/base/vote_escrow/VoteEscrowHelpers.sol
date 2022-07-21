pragma ever-solidity ^0.60.0;


import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "./VoteEscrowStorage.sol";
import {RPlatform as Platform} from "../../../Platform.sol";
import "../../interfaces/ICallbackReceiver.sol";
import "../../../libraries/Gas.sol";
import "../../../libraries/PlatformTypes.sol";
import "../../../libraries/Errors.sol";



abstract contract VoteEscrowHelpers is VoteEscrowStorage {
    // TODO: Up
    function getDetails() external view returns (
        address _owner,
        address _pendingOwner,
        address _qube,
        address _dao,
        address _qubeWallet,
        uint128 _treasuryTokens,
        uint128 _teamTokens,
        uint128 _qubeBalance,
        uint128 _veQubeBalance,
        uint32 _lastUpdateTime,
        uint128 _distributionSupply,
        uint32 _qubeMinLockTime,
        uint32 _qubeMaxLockTime,
        uint128 _gaugeWhitelistPrice,
        uint128 _whitelistPayments,
        bool _initialized,
        bool _paused,
        bool _emergency
    ) {
        _owner = owner;
        _pendingOwner = pendingOwner;
        _qube = qube;
        _dao = dao;
        _qubeWallet = qubeWallet;
        _treasuryTokens = treasuryTokens;
        _teamTokens = teamTokens;
        _qubeBalance = qubeBalance;
        _veQubeBalance = veQubeBalance;
        _lastUpdateTime = lastUpdateTime;
        _distributionSupply = distributionSupply;
        _qubeMinLockTime = qubeMinLockTime;
        _qubeMaxLockTime = qubeMaxLockTime;
        _gaugeWhitelistPrice = gaugeWhitelistPrice;
        _whitelistPayments = whitelistPayments;
        _initialized = initialized;
        _paused = paused;
        _emergency = emergency;
    }

    function getCurrentEpochDetails() external view returns (
        uint32 _currentEpoch,
        uint32 _currentEpochStartTime,
        uint32 _currentEpochEndTime,
        uint32 _currentVotingStartTime,
        uint32 _currentVotingEndTime,
        uint128 _currentVotingTotalVotes
    ) {
        _currentEpoch = currentEpoch;
        _currentEpochStartTime = currentEpochStartTime;
        _currentEpochEndTime = currentEpochEndTime;
        _currentVotingStartTime = currentVotingStartTime;
        _currentVotingEndTime = currentVotingEndTime;
        _currentVotingTotalVotes = currentVotingTotalVotes;
    }

    function getGaugeVotes(address gauge) external view returns (uint128) {
        return currentVotingVotes[gauge];
    }

    function getGaugeDowntime(address gauge) external view returns (uint8) {
        return gaugeDowntimes[gauge];
    }

    function isGaugeWhitelisted(address gauge) external view returns (bool) {
        return gaugeWhitelist[gauge];
    }

    function getVotingDetails() external view returns (
        uint32 _epochTime, // length of epoch in seconds
        uint32 _votingTime, // length of voting in seconds
        uint32 _timeBeforeVoting, // time after epoch start when next voting will take place
         uint32 _gaugeMaxVotesRatio, // up to 10000 (100%). Gauge cant have more votes. All exceeded votes will be distributed among other gauges
        uint32 _gaugeMinVotesRatio, // up to 10000 (100%). If gauge doesn't have min votes, it will not be elected in epoch
        uint8 _gaugeMaxDowntime, // if gauge was not elected for N times in a row, it is deleted from whitelist
        uint32 _maxGaugesPerVote, // max number of gauges user can vote for
        uint32 _gaugesNum
    ) {
        _epochTime = epochTime;
        _votingTime = votingTime;
        _timeBeforeVoting = timeBeforeVoting;
        _gaugeMaxVotesRatio = gaugeMaxVotesRatio;
        _gaugeMinVotesRatio = gaugeMinVotesRatio;
        _gaugeMaxDowntime = gaugeMaxDowntime;
        _maxGaugesPerVote = maxGaugesPerVote;
        _gaugesNum = gaugesNum;
    }

    function getCodes() external view returns (
        TvmCell _platform_code,
        TvmCell _ve_acc_code,
        uint32 _ve_acc_version,
        uint32 _ve_version
    ) {
        _platform_code = platformCode;
        _ve_acc_code = veAccountCode;
        _ve_acc_version = ve_account_version;
        _ve_version = ve_version;
    }

    // @param deposit_owner -address on which behalf sender making deposit
    // @param nonce - nonce, that will be sent with callback, should be > 0 if callback is needed
    // @param lock_time - lock time for deposited qubes
    // @param call_id - will be used in result event, helper for front and indexer
    function encodeDepositPayload(
        address deposit_owner, uint32 nonce, uint32 lock_time, uint32 call_id
    ) external pure returns (TvmCell payload){
        TvmBuilder builder;
        builder.store(deposit_owner, lock_time);
        return encodeTokenTransferPayload(0, nonce, call_id, builder.toCell());
    }

    function decodeDepositPayload(
        TvmCell additional_payload
    ) public pure returns (address deposit_owner, uint32 lock_time) {
        TvmSlice slice = additional_payload.toSlice();
        deposit_owner = slice.decode(address);
        lock_time = slice.decode(uint32);
    }

    // @param whitelist_addr - gauge address which will be whitelisted for distribution
    // @param nonce - nonce, that will be sent with callback, should be > 0 if callback is needed
    // @param call_id - will be used in result event, helper for front and indexer
    function encodeWhitelistPayload(
        address whitelist_addr, uint32 nonce, uint32 call_id
    ) external pure returns (TvmCell payload){
        TvmBuilder builder;
        builder.store(whitelist_addr);
        return encodeTokenTransferPayload(1, nonce, call_id, builder.toCell());
    }

    function decodeWhitelistPayload(
        TvmCell additional_payload
    ) public pure returns (address whitelist_addr) {
        TvmSlice slice = additional_payload.toSlice();
        whitelist_addr = slice.decode(address);
    }

    // @param nonce - nonce, that will be sent with callback, should be > 0 if callback is needed
    // @param call_id - will be used in result event, helper for front and indexer
    function encodeDistributionPayload(uint32 nonce, uint32 call_id) external pure returns (TvmCell payload) {
        TvmCell empty;
        return encodeTokenTransferPayload(2, nonce, call_id, empty);
    }

    function encodeTokenTransferPayload(
        uint8 deposit_type, uint32 nonce, uint32 call_id, TvmCell additional_payload
    ) public pure returns (TvmCell payload) {
        TvmBuilder builder;
        builder.store(deposit_type);
        builder.store(nonce);
        builder.store(call_id);
        builder.storeRef(additional_payload);
        return builder.toCell();
    }

    function decodeTokenTransferPayload(TvmCell payload) public pure returns (
        uint8 deposit_type, uint32 nonce, uint32 call_id, TvmCell additional_payload, bool correct
    ){
        // check if payload assembled correctly
        TvmSlice slice = payload.toSlice();
        // 1 uint8 and 2 uint32 address and 1 cell
        if (slice.hasNBitsAndRefs(8 + 32 + 32, 1)) {
            deposit_type = slice.decode(uint8);
            nonce = slice.decode(uint32);
            call_id = slice.decode(uint32);
            additional_payload = slice.loadRef();
            correct = true;
        }
    }

    function _addToWhitelist(address gauge, uint32 call_id) internal {
        gaugesNum += 1;
        gaugeWhitelist[gauge] = true;
        emit GaugeWhitelist(call_id, gauge);
    }

    function _removeFromWhitelist(address gauge, uint32 call_id) internal {
        gaugesNum -= 1;
        delete gaugeWhitelist[gauge];
        delete gaugeDowntimes[gauge];
        emit GaugeRemoveWhitelist(call_id, gauge);
    }

    function _sendCallbackOrGas(address callback_receiver, uint32 nonce, bool success, address send_gas_to) internal pure {
        if (nonce > 0) {
            if (success) {
                ICallbackReceiver(
                    callback_receiver
                ).acceptSuccessCallback{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
            } else {
                ICallbackReceiver(
                    callback_receiver
                ).acceptFailCallback{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
            }
        } else {
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
        }
    }

    function _transferQubes(
        uint128 amount, address receiver, TvmCell payload, address send_gas_to, uint16 flag
    ) internal view {
        uint128 value;
        if (flag != MsgFlag.ALL_NOT_RESERVED) {
            value = Gas.TOKEN_TRANSFER_VALUE;
        }
        bool notify = false;
        // notify = true if payload is non-empty
        TvmSlice slice = payload.toSlice();
        if (slice.bits() > 0 || slice.refs() > 0) {
            notify = true;
        }
        ITokenWallet(qubeWallet).transfer{value: value, flag: flag}(
            amount,
            receiver,
            0,
            send_gas_to,
            notify,
            payload
        );
    }

    function _makeCell(uint32 nonce) internal pure returns (TvmCell) {
        TvmBuilder builder;
        if (nonce > 0) {
            builder.store(nonce);
        }
        return builder.toCell();
    }


    function _setupTokenWallet() internal view {
        ITokenRoot(qube).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: IVoteEscrow.receiveTokenWalletAddress }(
            address(this), // owner
            Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
        );
    }

    function getVoteEscrowAccountAddress(address user) public view override responsible returns (address) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } address(
            tvm.hash(_buildInitData(_buildVoteEscrowAccountParams(user)))
        );
    }

    function _buildVoteEscrowAccountParams(address user) internal pure returns (TvmCell) {
        TvmBuilder builder;
        builder.store(user);
        return builder.toCell();
    }

    function _buildInitData(TvmCell _initialData) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Platform,
            varInit: {
                root: address(this),
                platformType: PlatformTypes.VoteEscrowAccount,
                initialData: _initialData,
                platformCode: platformCode
            },
            pubkey: 0,
            code: platformCode
        });
    }

    modifier onlyActive() {
        require (!paused && !emergency || msg.sender == owner, Errors.NOT_ACTIVE);
        _;
    }

    modifier onlyEmergency() {
        require (emergency, Errors.NOT_EMERGENCY);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    function _reserve() internal pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }

    modifier onlyVoteEscrowAccount(address user) {
        address ve_account_addr = getVoteEscrowAccountAddress(user);
        require (msg.sender == ve_account_addr, Errors.NOT_VOTE_ESCROW_ACCOUNT);
        _;
    }
}
