pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./GaugeRewards.sol";
import "../../interfaces/IGaugeAccount.sol";
import "../../interfaces/IVoteEscrow.sol";
import "../../libraries/PlatformTypes.sol";
import "../../libraries/Errors.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";


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

        if (msg.sender == depositTokenWallet) {
            // check if payload assembled correctly
            (address deposit_owner, uint32 lock_time, bool claim, uint32 call_id, uint32 nonce, bool correct) = decodeDepositPayload(payload);

            if (!correct || msg.value < Gas.MIN_MSG_VALUE || lock_time > maxLockTime) {
                // too low deposit value or too low msg.value or incorrect deposit payload
                // for incorrect deposit payload send tokens back to sender
                emit DepositRevert(call_id, deposit_owner, amount);
                _transferTokens(depositTokenWallet, amount, sender, payload, remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
                return;
            }

            updateRewardData();

            uint128 boosted_amount = calculateBoostedBalance(amount, lock_time);
            depositTokenBalance += amount;
            lockBoostedSupply += boosted_amount;

            deposit_nonce += 1;
            deposits[deposit_nonce] = PendingDeposit(
                deposit_owner, amount, boosted_amount, lock_time, claim, remainingGasTo, nonce, call_id
            );

            address gaugeAccountAddr = getGaugeAccountAddress(deposit_owner);
            IGaugeAccount(gaugeAccountAddr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                deposit_nonce,
                amount,
                boosted_amount,
                lock_time,
                claim,
                lockBoostedSupply,
                lockBoostedSupplyAverage,
                lockBoostedSupplyAveragePeriod,
                extraRewardRounds,
                qubeRewardRounds,
                lastRewardTime
            );
        } else if (msg.sender == qubeTokenData.tokenWallet && sender == voteEscrow) {
            TvmSlice slice = payload.toSlice();
            uint32 round_len = slice.decode(uint32);
            _addQubeRewardRound(amount, round_len);
            remainingGasTo.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
        } else {
            for (uint i = 0; i < extraTokenData.length; i++) {
                if (msg.sender == extraTokenData[i].tokenWallet) {
                    (uint32 call_id, uint32 nonce, bool correct) = decodeRewardDepositPayload(payload);
                    if (!correct) {
                        emit DepositRevert(call_id, sender, amount);
                        _transferTokens(msg.sender, amount, sender, payload, remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
                        return;
                    }

                    extraTokenData[i].tokenBalance += amount;
                    emit RewardDeposit(call_id, i, amount);

                    _sendCallbackOrGas(sender, nonce, true, remainingGasTo);
                    return;
                }
            }
        }
    }

    function revertDeposit(address user, uint32 _deposit_nonce) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        PendingDeposit deposit = deposits[_deposit_nonce];
        depositTokenBalance -= deposit.amount;
        lockBoostedSupply -= deposit.boosted_amount;

        emit DepositRevert(deposit.call_id, deposit.user, deposit.amount);
        delete deposits[_deposit_nonce];

        _transferTokens(
            depositTokenWallet,
            deposit.amount,
            deposit.user,
            _makeCell(deposit.nonce),
            deposit.send_gas_to,
            MsgFlag.ALL_NOT_RESERVED
        );
    }

    function withdraw(uint128 amount, bool claim, uint32 call_id, uint32 nonce, address send_gas_to) external {
        require (amount > 0, Errors.BAD_INPUT);
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        updateRewardData();

        address gaugeAccountAddr = getGaugeAccountAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to GaugeAccount
        IGaugeAccount(gaugeAccountAddr).processWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            amount, claim, lockBoostedSupply, lockBoostedSupplyAverage, lockBoostedSupplyAveragePeriod,
            extraRewardRounds, qubeRewardRounds, lastRewardTime, call_id, nonce, send_gas_to
        );
    }

    function revertWithdraw(address user, uint32 call_id, uint32 nonce, address send_gas_to) external override onlyGaugeAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        emit WithdrawRevert(call_id, user);
        _sendCallbackOrGas(user, nonce, false, send_gas_to);
    }

    function claimReward(uint32 call_id, uint32 nonce, address send_gas_to) external {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        updateRewardData();

        address gaugeAccountAddr = getGaugeAccountAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to GaugeAccount
        IGaugeAccount(gaugeAccountAddr).processClaim{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            lockBoostedSupply, lockBoostedSupplyAverage, lockBoostedSupplyAveragePeriod,
            extraRewardRounds, qubeRewardRounds, lastRewardTime, call_id, nonce, send_gas_to
        );
    }

    function finishDeposit(
        address user,
        uint128 qube_reward,
        uint128[] extra_reward,
        bool claim,
        uint128 ve_bal_old,
        uint128 ve_bal_new,
        uint32 _deposit_nonce
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);
        PendingDeposit deposit = deposits[_deposit_nonce];

        veBoostedSupply = veBoostedSupply + ve_bal_new - ve_bal_old;

        emit Deposit(deposit.call_id, deposit.user, deposit.amount, deposit.lock_time);
        delete deposits[_deposit_nonce];

        if (claim) {
            (
                uint128 _qube_amount,
                uint128[] _extra_amount,
                uint128 _qube_debt,
                uint128[] _extra_debt
            ) = _transferReward(msg.sender, user, qube_reward, extra_reward, deposit.send_gas_to, deposit.nonce);

            emit Claim(deposit.call_id, deposit.user, _qube_amount, _extra_amount, _qube_debt, _extra_debt);
        }

        _sendCallbackOrGas(deposit.user, deposit.nonce, true, deposit.send_gas_to);
    }

    function finishWithdraw(
        address user,
        uint128 amount,
        uint128 qube_reward,
        uint128[] extra_reward,
        bool claim,
        uint128 ve_bal_old,
        uint128 ve_bal_new,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        veBoostedSupply = veBoostedSupply + ve_bal_new - ve_bal_old;
        depositTokenBalance -= amount;
        lockBoostedSupply -= amount;

        emit Withdraw(call_id, user, amount);

        if (claim) {
            (
                uint128 _qube_amount,
                uint128[] _extra_amount,
                uint128 _qube_debt,
                uint128[] _extra_debt
            ) = _transferReward(msg.sender, user, qube_reward, extra_reward, send_gas_to, nonce);

            emit Claim(call_id, user, _qube_amount, _extra_amount, _qube_debt, _extra_debt);
        }

        // we dont need additional callback, we always send tokens as last action
        _transferTokens(depositTokenWallet, amount, user, _makeCell(nonce), send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }

    function finishClaim(
        address user,
        uint128 qube_reward,
        uint128[] extra_reward,
        uint128 ve_bal_old,
        uint128 ve_bal_new,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        veBoostedSupply = veBoostedSupply + ve_bal_new - ve_bal_old;
        (
            uint128 _qube_amount,
            uint128[] _extra_amount,
            uint128 _qube_debt,
            uint128[] _extra_debt
        ) = _transferReward(msg.sender, user, qube_reward, extra_reward, send_gas_to, nonce);

        emit Claim(call_id, user, _qube_amount, _extra_amount, _qube_debt, _extra_debt);

        _sendCallbackOrGas(user, nonce, true, send_gas_to);
    }

    function burnBoostedBalance(address user, uint128 expired_boosted) external override onlyGaugeAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        updateSupplyAverage();

        lockBoostedSupply -= expired_boosted;
        emit LockBoostedBurn(user, expired_boosted);

        user.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdrawUnclaimed(uint128[] ids, address to, uint32 call_id, uint32 nonce, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE + Gas.TOKEN_TRANSFER_VALUE * ids.length, Errors.LOW_MSG_VALUE);
        uint128[] extra_amounts = new uint128[](extraTokenData.length);

        for (uint i = 0; i < ids.length; i++) {
            RewardRound[] _rounds = extraRewardRounds[ids[i]];
            RewardRound _last_round = _rounds[_rounds.length - 1];

            uint32 lock_time = _last_round.endTime + extraVestingPeriods[ids[i]] + withdrawAllLockPeriod;

            require (extraRewardEnded[ids[i]], Errors.CANT_WITHDRAW_UNCLAIMED_ALL);
            require (now >= lock_time, Errors.CANT_WITHDRAW_UNCLAIMED_ALL);

            extra_amounts[ids[i]] = extraTokenData[ids[i]].tokenBalance;
            extraTokenData[ids[i]].tokenBalance = 0;
        }
        tvm.rawReserve(_reserve(), 0);

        _transferReward(address.makeAddrNone(), to, 0, extra_amounts, send_gas_to, nonce);

        emit WithdrawUnclaimed(call_id, to, extra_amounts);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
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
            IVoteEscrow(voteEscrow).deployVoteEscrowAccount{value: Gas.VE_ACCOUNT_DEPLOY_VALUE + 0.1 ton}(deposit.user);
            // deploy Gauge account
            address gauge_account_addr = deployGaugeAccount(deposit.user);
            // deploy qube and other wallets
            ITokenRoot(qubeTokenData.tokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.dummy}(
                deposit.user,
                Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
            );
            for (uint i = 0; i < extraTokenData.length; i++) {
                ITokenRoot(extraTokenData[i].tokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.dummy}(
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
                lockBoostedSupply,
                lockBoostedSupplyAverage,
                lockBoostedSupplyAveragePeriod,
                extraRewardRounds,
                qubeRewardRounds,
                lastRewardTime
            );
        }
    }
}
