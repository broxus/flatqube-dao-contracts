pragma ever-solidity ^0.62.0;


import "./GaugeStorage.sol";
import "../../../libraries/Errors.sol";
import "../../../libraries/Gas.sol";
import "../../../libraries/PlatformTypes.sol";
import {RPlatform as Platform} from "../../../Platform.sol";
import "../../interfaces/IGaugeAccount.sol";
import "../../interfaces/ICallbackReceiver.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


abstract contract GaugeHelpers is GaugeStorage {
    function getDetails() external view returns (
        address _owner,
        address _voteEscrow,
        uint128 _lockBoostedSupply,
        uint128 _totalBoostedSupply,
        uint32 _maxBoost,
        uint32 _maxLockTime,
        uint256[] _lastExtraRewardRoundIdx,
        uint256 _lastQubeRewardRoundIdx,
        uint32 _lastRewardTime,
        uint32 _lastAverageUpdateTime,
        bool _initialized
    ) {
        _owner = owner;
        _voteEscrow = voteEscrow;
        _lockBoostedSupply = lockBoostedSupply;
        _totalBoostedSupply = totalBoostedSupply;
        _maxBoost = maxBoost;
        _maxLockTime = maxLockTime;
        _lastExtraRewardRoundIdx = lastExtraRewardRoundIdx;
        _lastQubeRewardRoundIdx = lastQubeRewardRoundIdx;
        _lastRewardTime = lastRewardTime;
        _lastAverageUpdateTime = lastAverageUpdateTime;
        _initialized = initialized;
    }

    function getRewardDetails() external view returns (
        RewardRound[] _qubeRewardRounds,
        uint32 _qubeVestingPeriod,
        uint32 _qubeVestingRatio,
        RewardRound[][] _extraRewardRounds,
        uint32[] _extraVestingPeriods,
        uint32[] _extraVestingRatios,
        bool[] _extraRewardEnded,
        uint32 _withdrawAllLockPeriod
    ) {
        _qubeRewardRounds = qubeRewardRounds;
        _qubeVestingPeriod = qubeVestingPeriod;
        _qubeVestingRatio = qubeVestingRatio;
        _extraRewardRounds = extraRewardRounds;
        _extraVestingPeriods = extraVestingPeriods;
        _extraVestingRatios = extraVestingRatios;
        _extraRewardEnded = extraRewardEnded;
        _withdrawAllLockPeriod = withdrawAllLockPeriod;
    }

    function getTokenDetails() external view returns (
        TokenData _depositTokenData,
        TokenData _qubeTokenData,
        TokenData[] _extraTokenData
    ) {
        _depositTokenData = depositTokenData;
        _qubeTokenData = qubeTokenData;
        _extraTokenData = extraTokenData;
    }

    function getCodes() external view returns (
        TvmCell _platformCode,
        TvmCell _gaugeAccountCode,
        uint32 _gaugeAccountVersion,
        uint32 _gaugeVersion
    ) {
        _platformCode = platformCode;
        _gaugeAccountCode = gaugeAccountCode;
        _gaugeAccountVersion = gauge_account_version;
        _gaugeVersion = gauge_version;
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
        bool claim,
        uint32 call_id,
        uint32 nonce
    ) external pure returns (TvmCell deposit_payload) {
        TvmBuilder builder;
        builder.store(deposit_owner);
        builder.store(lock_time);
        builder.store(claim);
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
        address deposit_owner, uint32 lock_time, bool claim, uint32 call_id, uint32 nonce, bool correct
    ) {
        // check if payload assembled correctly
        TvmSlice slice = payload.toSlice();
        // 1 address and 1 cell
        if (slice.hasNBitsAndRefs(267 + 32 + 32 + 1 + 32, 0)) {
            deposit_owner = slice.decode(address);
            lock_time = slice.decode(uint32);
            claim = slice.decode(bool);
            call_id = slice.decode(uint32);
            nonce = slice.decode(uint32);
            correct = true;
        }
    }

    function _syncData() internal view returns (GaugeSyncData) {
        return GaugeSyncData(
            depositTokenData.tokenBalance,
            supplyAverage,
            supplyAveragePeriod,
            extraRewardRounds,
            qubeRewardRounds,
            lastRewardTime
        );
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
            if (extraTokenData[i].tokenBalance < extra_amounts[i]) {
                _extra_debt[i] = extra_amounts[i] - extraTokenData[i].tokenBalance;
                _extra_amount[i] -= _extra_debt[i];
                have_debt = true;
            }
        }
        // check if we have enough qube, emit debt otherwise
        if (qubeTokenData.tokenBalance < qube_amount) {
            _qube_debt = qube_amount - qubeTokenData.tokenBalance;
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
                _transferTokens(extraTokenData[i].tokenWallet, _extra_amount[i], receiver_addr, _makeCell(nonce), send_gas_to, 0);
                extraTokenData[i].tokenBalance -= _extra_amount[i];
            }
        }
        // pay qube rewards
        if (_qube_amount > 0) {
            _transferTokens(qubeTokenData.tokenWallet, _qube_amount, receiver_addr, _makeCell(nonce), send_gas_to, 0);
            qubeTokenData.tokenBalance -= _qube_amount;
        }
        return (_qube_amount, _extra_amount, _qube_debt, _extra_debt);
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

    modifier onlyFactory() {
        require (msg.sender == factory, Errors.NOT_FACTORY);
        _;
    }

    function _reserve() internal virtual pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }
}
