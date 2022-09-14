pragma ever-solidity ^0.62.0;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "./GaugeRewards.sol";
import "../../interfaces/IGaugeAccount.sol";
import "../../../vote_escrow/interfaces/IVoteEscrow.sol";
import "../../../libraries/PlatformTypes.sol";
import "../../../libraries/Callback.sol";
import "../../../libraries/Errors.sol";
import {RPlatform as Platform} from "../../../Platform.sol";


abstract contract GaugeBase is GaugeRewards {
    function dummy(address user_wallet) external {}

    // deposit occurs here
    function onAcceptTokensTransfer(
        address,
        uint128 amount,
        address sender,
        address,
        address remainingGasTo,
        TvmCell payload
    ) external override {
        tvm.rawReserve(_reserve(), 0);

        if (msg.sender == depositTokenData.wallet) {
            // check if payload assembled correctly
            (address deposit_owner, uint32 lock_time, bool claim, uint32 call_id, uint32 nonce, bool correct) = decodeDepositPayload(payload);

            if (!correct || msg.value < Gas.MIN_MSG_VALUE || lock_time > maxLockTime) {
                // too low deposit value or too low msg.value or incorrect deposit payload
                // for incorrect deposit payload send tokens back to sender
                emit DepositRevert(call_id, deposit_owner, amount);
                _transferTokens(depositTokenData.wallet, amount, sender, payload, remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
                return;
            }

            updateRewardData();

            uint128 boosted_amount = calculateBoostedBalance(amount, lock_time);
            depositTokenData.balance += amount;
            lockBoostedSupply += boosted_amount;

            deposit_nonce += 1;
            deposits[deposit_nonce] = PendingDeposit(
                deposit_owner, amount, boosted_amount, lock_time, claim, Callback.CallMeta(call_id, nonce, remainingGasTo)
            );

            address gaugeAccountAddr = getGaugeAccountAddress(deposit_owner);
            IGaugeAccount(gaugeAccountAddr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                deposit_nonce,
                amount,
                boosted_amount,
                lock_time,
                claim,
                _syncData(),
                Callback.CallMeta(call_id, nonce, remainingGasTo)
            );
        } else if (msg.sender == qubeTokenData.wallet && sender == voteEscrow) {
            TvmSlice slice = payload.toSlice();
            uint32 round_start = slice.decode(uint32);
            uint32 round_len = slice.decode(uint32);

            qubeTokenData.balance += amount;
            qubeTokenData.cumulativeBalance += amount;

            _addQubeRewardRound(amount, round_start, round_len);
            remainingGasTo.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
        } else {
            for (uint i = 0; i < extraTokenData.length; i++) {
                if (msg.sender == extraTokenData[i].wallet) {
                    (uint32 call_id, uint32 nonce, bool correct) = decodeRewardDepositPayload(payload);
                    if (!correct) {
                        emit DepositRevert(call_id, sender, amount);
                        _transferTokens(msg.sender, amount, sender, payload, remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
                        return;
                    }

                    extraTokenData[i].balance += amount;
                    extraTokenData[i].cumulativeBalance += amount;
                    emit RewardDeposit(call_id, sender, i, amount);

                    _sendCallbackOrGas(sender, nonce, true, remainingGasTo);
                    return;
                }
            }
        }
    }

    function revertDeposit(address user, uint32 _deposit_nonce) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        PendingDeposit deposit = deposits[_deposit_nonce];
        depositTokenData.balance -= deposit.amount;
        lockBoostedSupply -= deposit.boosted_amount;

        emit DepositRevert(deposit.meta.call_id, deposit.user, deposit.amount);
        delete deposits[_deposit_nonce];

        _transferTokens(
            depositTokenData.wallet,
            deposit.amount,
            deposit.user,
            _makeCell(deposit.meta.nonce),
            deposit.meta.send_gas_to,
            MsgFlag.ALL_NOT_RESERVED
        );
    }

    function finishDeposit(
        address user,
        uint128 qube_reward,
        uint128[] extra_reward,
        bool claim,
        uint128 boosted_bal_old,
        uint128 boosted_bal_new,
        uint32 _deposit_nonce
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);
        PendingDeposit deposit = deposits[_deposit_nonce];

        totalBoostedSupply = totalBoostedSupply + boosted_bal_new - boosted_bal_old;

        emit Deposit(deposit.meta.call_id, deposit.user, deposit.amount, deposit.boosted_amount, deposit.lock_time);
        delete deposits[_deposit_nonce];

        if (claim) {
            (
            uint128 _qube_amount,
            uint128[] _extra_amount,
            uint128 _qube_debt,
            uint128[] _extra_debt
            ) = _transferReward(msg.sender, user, qube_reward, extra_reward, deposit.meta.send_gas_to, deposit.meta.nonce);

            emit Claim(deposit.meta.call_id, deposit.user, _qube_amount, _extra_amount, _qube_debt, _extra_debt);
        }

        _sendCallbackOrGas(deposit.user, deposit.meta.nonce, true, deposit.meta.send_gas_to);
    }

    function withdraw(uint128 amount, bool claim, Callback.CallMeta meta) external {
        require (amount > 0, Errors.BAD_INPUT);
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        updateRewardData();

        address gaugeAccountAddr = getGaugeAccountAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to GaugeAccount
        IGaugeAccount(gaugeAccountAddr).processWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            amount, claim, _syncData(), meta
        );
    }

    function revertWithdraw(address user, Callback.CallMeta meta) external override onlyGaugeAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        emit WithdrawRevert(meta.call_id, user);
        _sendCallbackOrGas(user, meta.nonce, false, meta.send_gas_to);
    }

    function claimReward(Callback.CallMeta meta) external {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        updateRewardData();

        address gaugeAccountAddr = getGaugeAccountAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to GaugeAccount
        IGaugeAccount(gaugeAccountAddr).processClaim{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(_syncData(), meta);
    }

    function finishWithdraw(
        address user,
        uint128 amount,
        uint128 qube_reward,
        uint128[] extra_reward,
        bool claim,
        uint128 boosted_bal_old,
        uint128 boosted_bal_new,
        Callback.CallMeta meta
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        totalBoostedSupply = totalBoostedSupply + boosted_bal_new - boosted_bal_old;
        depositTokenData.balance -= amount;
        lockBoostedSupply -= amount;

        emit Withdraw(meta.call_id, user, amount);

        if (claim) {
            (
                uint128 _qube_amount,
                uint128[] _extra_amount,
                uint128 _qube_debt,
                uint128[] _extra_debt
            ) = _transferReward(msg.sender, user, qube_reward, extra_reward, meta.send_gas_to, meta.nonce);

            emit Claim(meta.call_id, user, _qube_amount, _extra_amount, _qube_debt, _extra_debt);
        }

        // we dont need additional callback, we always send tokens as last action
        _transferTokens(
            depositTokenData.wallet, amount, user, _makeCell(meta.nonce), meta.send_gas_to, MsgFlag.ALL_NOT_RESERVED
        );
    }

    function finishClaim(
        address user,
        uint128 qube_reward,
        uint128[] extra_reward,
        uint128 boosted_bal_old,
        uint128 boosted_bal_new,
        Callback.CallMeta meta
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        totalBoostedSupply = totalBoostedSupply + boosted_bal_new - boosted_bal_old;
        (
            uint128 _qube_amount,
            uint128[] _extra_amount,
            uint128 _qube_debt,
            uint128[] _extra_debt
        ) = _transferReward(msg.sender, user, qube_reward, extra_reward, meta.send_gas_to, meta.nonce);

        emit Claim(meta.call_id, user, _qube_amount, _extra_amount, _qube_debt, _extra_debt);

        _sendCallbackOrGas(user, meta.nonce, true, meta.send_gas_to);
    }

    function burnLockBoostedBalance(address user, uint128 expired_boosted) external override onlyGaugeAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        updateSupplyAverage();

        lockBoostedSupply -= expired_boosted;
        emit LockBoostedBurn(user, expired_boosted);

        user.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdrawUnclaimed(uint128[] ids, address to, Callback.CallMeta meta) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE + Gas.TOKEN_TRANSFER_VALUE * ids.length, Errors.LOW_MSG_VALUE);
        uint128[] extra_amounts = new uint128[](extraTokenData.length);

        for (uint i = 0; i < ids.length; i++) {
            RewardRound[] _rounds = extraRewardRounds[ids[i]];
            RewardRound _last_round = _rounds[_rounds.length - 1];

            uint32 lock_time = _last_round.endTime + extraVestingPeriods[ids[i]] + withdrawAllLockPeriod;

            require (extraRewardEnded[ids[i]], Errors.CANT_WITHDRAW_UNCLAIMED_ALL);
            require (now >= lock_time, Errors.CANT_WITHDRAW_UNCLAIMED_ALL);

            extra_amounts[ids[i]] = extraTokenData[ids[i]].balance;
            extraTokenData[ids[i]].balance = 0;
        }
        tvm.rawReserve(_reserve(), 0);

        _transferReward(address.makeAddrNone(), to, 0, extra_amounts, meta.send_gas_to, meta.nonce);

        emit WithdrawUnclaimed(meta.call_id, to, extra_amounts);
        meta.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function deployGaugeAccount(address gauge_account_owner) internal view returns (address) {
        TvmBuilder constructor_params;

        constructor_params.store(gauge_account_version); // 32
        constructor_params.store(gauge_account_version); // 32

        constructor_params.store(voteEscrow);

        constructor_params.store(qubeVestingPeriod); // 32
        constructor_params.store(qubeVestingRatio); // 32

        constructor_params.store(extraVestingPeriods); // 32 + ref
        constructor_params.store(extraVestingRatios); // 32 + ref

        return new Platform{
            stateInit: _buildInitData(_buildGaugeAccountParams(gauge_account_owner)),
            value: Gas.GAUGE_ACCOUNT_DEPLOY_VALUE
        }(gaugeAccountCode, constructor_params.toCell(), gauge_account_owner);
    }

    onBounce(TvmSlice slice) external view {
        tvm.accept();

        uint32 functionId = slice.decode(uint32);
        // if processing failed - contract was not deployed. Deploy and try again
        if (functionId == tvm.functionId(IGaugeAccount.processDeposit)) {
            tvm.rawReserve(_reserve(), 0);

            uint32 _deposit_nonce = slice.decode(uint32);
            PendingDeposit deposit = deposits[_deposit_nonce];
            // deploy VE account
            IVoteEscrow(voteEscrow).deployVoteEscrowAccount{value: Gas.VE_ACCOUNT_DEPLOY_VALUE + 0.1 ever}(deposit.user);
            // deploy Gauge account
            address gauge_account_addr = deployGaugeAccount(deposit.user);
            // deploy qube and other wallets
            ITokenRoot(qubeTokenData.root).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.dummy}(
                deposit.user,
                Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
            );
            for (uint i = 0; i < extraTokenData.length; i++) {
                ITokenRoot(extraTokenData[i].root).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.dummy}(
                    deposit.user,
                    Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
                );
            }

            IGaugeAccount(gauge_account_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                _deposit_nonce,
                deposit.amount,
                deposit.boosted_amount,
                deposit.lock_time,
                deposit.claim,
                _syncData(),
                deposit.meta
            );
        }
    }
}
