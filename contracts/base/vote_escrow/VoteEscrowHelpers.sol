pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "@broxus/contracts/contracts/platform/Platform.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "./VoteEscrowStorage.sol";
import "../../interfaces/IVoteEscrowCallbackReceiver.sol";


abstract contract VoteEscrowHelpers is VoteEscrowStorage {
    // @param deposit_owner -address on which behalf sender making deposit
    // @param nonce - nonce, that will be sent with callback, should be > 0 if callback is needed
    // @param lock_time - lock time for deposited qubes
    // @param call_id - will be used in result event, helper for front and indexer
    function encodeDepositPayload(
        address deposit_owner, uint32 nonce, uint32 lock_time, uint32 call_id
    ) external pure returns (TvmCell payload){
        TvmBuilder builder;
        builder.store(deposit_owner, lock_time);
        return _encodeTokenTransferPayload(0, nonce, call_id, builder.toCell());
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
        return _encodeTokenTransferPayload(1, nonce, call_id, builder.toCell());
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
        return _encodeTokenTransferPayload(2, nonce, call_id, empty);
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

    function decodeTokenTransferPayload(TvmCell payload) public returns (
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

    function _addToWhitelist(uint32 call_id, address gauge) internal {
        gaugesNum += 1;
        whitelistedGauges[gauge] = true;
        emit GaugeWhitelist(call_id, gauge);
    }

    function _removeFromWhitelist(uint32 call_id, address gauge) internal {
        gaugesNum -= 1;
        whitelistedGauges[gauge] = false;
        emit GaugeRemoveWhitelist(call_id, gauge);
    }

    function _sendCallbackOrGas(address callback_receiver, uint32 nonce, bool success, address send_gas_to) internal {
        if (nonce > 0) {
            if (success) {
                IVoteEscrowCallbackReceiver(
                    callback_receiver
                ).acceptVoteEscrowSuccessCallback{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
            } else {
                IVoteEscrowCallbackReceiver(
                    callback_receiver
                ).acceptVoteEscrowFailCallback{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce);
            }
        } else {
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
        }
    }

    // TODO: add value
    function _transferTokens(
        address token_wallet, uint128 amount, address receiver, TvmCell payload, address send_gas_to, uint16 flag
    ) internal {
        uint128 value;
        if (flag != MsgFlag.ALL_NOT_RESERVED) {
            value = TOKEN_TRANSFER_VALUE;
        }
        bool notify = false;
        // notify = true if payload is non-empty
        if (payload.bits() > 0) {
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

    function _makeCell(uint32 nonce) internal {
        TvmBuilder builder;
        if (nonce > 0) {
            builder.store(nonce);
        }
        return builder.toCell();
    }


    function _setupTokenWallet() internal {
        ITokenRoot(qube).deployWallet{value: TOKEN_WALLET_DEPLOY_VALUE, callback: VoteEscrow.receiveTokenWalletAddress }(
            address(this), // owner
            TOKEN_WALLET_DEPLOY_GRAMS_VALUE / 2 // deploy grams
        );
    }

    function getVoteEscrowAccountAddress(address user) public view responsible returns (address) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } address(
            tvm.hash(_buildInitData(_buildVoteEscrowAccountParams(user)))
        );
    }

    function _buildVoteEscrowAccountParams(address user) internal view returns (TvmCell) {
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

    modifier onlyVoteEscrowAccount(address user) {
        address ve_account_addr = getVoteEscrowAccountAddress(user);
        require (msg.sender == ve_account_addr, NOT_VOTE_ESCROW_ACCOUNT);
        _;
    }
}
