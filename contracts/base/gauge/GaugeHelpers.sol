pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./GaugeStorage.sol";
import "../../libraries/Errors.sol";
import "../../libraries/Gas.sol";
import "../../interfaces/IGaugeAccount.sol";
import "../../libraries/PlatformTypes.sol";
import "../../interfaces/ICallbackReceiver.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";



abstract contract GaugeHelpers is GaugeStorage {
    // TODO: sync
    function getDetails() external view responsible returns (Details) {
        return { value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS }Details(
            lastRewardTime, voteEscrow, depositTokenRoot, depositTokenWallet, depositTokenBalance,
            qubeReward, extraRewards, owner, factory,gauge_account_version, gauge_version
        );
    }

    function calculateBoostedBalance(uint128 amount, uint32 lock_time) public view returns (uint128 boosted_amount) {
        if (maxLockTime == 0) {
            return amount;
        }
        lock_time = math.min(lock_time, maxLockTime);
        uint128 boost = BOOST_BASE + math.muldiv((maxBoost - BOOST_BASE), lock_time, maxLockTime);
        boosted_amount = math.muldiv(amount, boost, BOOST_BASE);
    }

    function encodeDepositPayload(
        address deposit_owner,
        uint32 lock_time,
        uint32 call_id,
        uint32 nonce
    ) external pure returns (TvmCell deposit_payload) {
        TvmBuilder builder;
        builder.store(deposit_owner);
        builder.store(lock_time);
        builder.store(call_id);
        builder.store(nonce);
        return builder.toCell();
    }

    function encodeRewardDepositPayload(uint32 call_id, uint32 nonce) external pure returns (TvmCell reward_deposit_payload) {
        TvmBuilder builder;
        builder.store(call_id);
        builder.store(nonce);
        return builder.toCell();
    }

    function decodeRewardDepositPayload(TvmCell payload) public pure returns (uint32 call_id, uint32 nonce, bool correct) {
        TvmSlice slice = payload.toSlice();
        if (slice.hasNBitsAndRefs(32 + 32, 0)) {
            call_id = slice.decode(uint32);
            nonce = slice.decode(uint32);
            correct = true;
        }
    }

    // try to decode deposit payload
    function decodeDepositPayload(TvmCell payload) public pure returns (
        address deposit_owner, uint32 lock_time, uint32 call_id, uint32 nonce, bool correct
    ) {
        // check if payload assembled correctly
        TvmSlice slice = payload.toSlice();
        // 1 address and 1 cell
        if (slice.hasNBitsAndRefs(267 + 32 + 32 + 32, 0)) {
            deposit_owner = slice.decode(address);
            lock_time = slice.decode(uint32);
            call_id = slice.decode(uint32);
            nonce = slice.decode(uint32);
            correct = true;
        }
    }

    function _makeCell(uint32 nonce) internal pure returns (TvmCell) {
        TvmBuilder builder;
        if (nonce > 0) {
            builder.store(nonce);
        }
        return builder.toCell();
    }

    function _transferTokens(
        address token_wallet, uint128 amount, address receiver, TvmCell payload, address send_gas_to, uint16 flag
    ) internal pure {
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
        ITokenWallet(token_wallet).transfer{value: value, flag: flag}(
            amount,
            receiver,
            0,
            send_gas_to,
            notify,
            payload
        );
    }

    function _transferReward(
        address gauge_account_addr,
        address receiver_addr,
        uint128 qube_amount,
        uint128[] extra_amounts,
        address send_gas_to,
        uint32 nonce
    ) internal returns (
        uint128 _qube_amount,
        uint128[] _extra_amount,
        uint128 _qube_debt,
        uint128[] _extra_debt
    ){
        _qube_amount = qube_amount;
        _extra_amount = extra_amounts;
        _extra_debt = new uint128[](extra_amounts.length);

        bool have_debt;
        // check if we have enough special rewards, emit debt otherwise
        for (uint i = 0; i < extra_amounts.length; i++) {
            if (extraRewards[i].tokenData.tokenBalance < extra_amounts[i]) {
                _extra_debt[i] = extra_amounts[i] - extraRewards[i].tokenData.tokenBalance;
                _extra_amount[i] -= _extra_debt[i];
                have_debt = true;
            }
        }
        // check if we have enough qube, emit debt otherwise
        if (qubeReward.tokenData.tokenBalance < qube_amount) {
            _qube_debt = qube_amount - qubeReward.tokenData.tokenBalance;
            _qube_amount -= _qube_debt;
            have_debt = true;
        }

        // check if its user or admin
        // for user we emit debt, for admin just claim possible extra_amounts (withdrawUnclaimed)
        if (gauge_account_addr != address.makeAddrNone() && have_debt) {
            IGaugeAccount(gauge_account_addr).increasePoolDebt{value: Gas.INCREASE_DEBT_VALUE, flag: 0}(
                _qube_debt, _extra_debt, send_gas_to
            );
        }

        // pay extra rewards
        for (uint i = 0; i < _extra_amount.length; i++) {
            if (_extra_amount[i] > 0) {
                _transferTokens(extraRewards[i].tokenData.tokenWallet, _extra_amount[i], receiver_addr, _makeCell(nonce), send_gas_to, 0);
                extraRewards[i].tokenData.tokenBalance -= _extra_amount[i];
            }
        }
        // pay qube rewards
        if (_qube_amount > 0) {
            _transferTokens(qubeReward.tokenData.tokenWallet, _qube_amount, receiver_addr, _makeCell(nonce), send_gas_to, 0);
            qubeReward.tokenData.tokenBalance -= _qube_amount;
        }
        return (_qube_amount, _extra_amount, _qube_debt, _extra_debt);
    }

    /*
        @notice Creates token wallet for configured root token, initialize arrays and send callback to factory
    */
    function _setUpTokenWallets() internal view {
        // Deploy vault's token wallet
        ITokenRoot(depositTokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: IGauge.receiveTokenWalletAddress }(
            address(this), // owner
            Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
        );

        // deploy qube wallet
        ITokenRoot(qubeReward.tokenData.tokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: IGauge.receiveTokenWalletAddress }(
            address(this), // owner
            Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
        );

        for (uint i = 0; i < extraRewards.length; i++) {
            ITokenRoot(extraRewards[i].tokenData.tokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: IGauge.receiveTokenWalletAddress}(
                address(this), // owner address
                Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
            );
        }
    }

    /*
        @notice Store vault's token wallet address
        @dev Only root can call with correct params
        @param wallet Gauge's token wallet
    */
    function receiveTokenWalletAddress(address wallet) external override {
        tvm.rawReserve(_reserve(), 0);

        if (msg.sender == depositTokenRoot) {
            depositTokenWallet = wallet;
        } else if (msg.sender == qubeReward.tokenData.tokenRoot) {
            qubeReward.tokenData.tokenWallet = wallet;
        } else {
            for (uint i = 0; i < extraRewards.length; i++) {
                if (msg.sender == extraRewards[i].tokenData.tokenRoot) {
                    extraRewards[i].tokenData.tokenWallet = wallet;
                }
            }
        }
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

    modifier onlyGaugeAccount(address user) {
        address expectedAddr = getGaugeAccountAddress(user);
        require (expectedAddr == msg.sender, Errors.NOT_GAUGE_ACCOUNT);
        _;
    }

    function getGaugeAccountAddress(address user) public virtual view responsible returns (address) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } address(tvm.hash(_buildInitData(_buildGaugeAccountParams(user))));
    }

    function _buildGaugeAccountParams(address user) internal virtual pure returns (TvmCell) {
        TvmBuilder builder;
        builder.store(user);
        return builder.toCell();
    }

    function _buildInitData(TvmCell _initialData) internal virtual view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Platform,
            varInit: {
                root: address(this),
                platformType: PlatformTypes.GaugeAccount,
                initialData: _initialData,
                platformCode: platformCode
            },
            pubkey: 0,
            code: platformCode
        });
    }

    modifier onlyOwner() {
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    function _reserve() internal virtual pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }
}
