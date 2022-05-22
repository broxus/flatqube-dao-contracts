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
        address tokenRoot,
        uint128 amount,
        address sender,
        address senderWallet,
        address remainingGasTo,
        TvmCell payload
    ) external override {
        tvm.rawReserve(_reserve(), 0);

        if (msg.sender == depositTokenWallet) {
            // check if payload assembled correctly
            (address deposit_owner, uint32 lock_time, uint32 call_id, uint32 nonce, bool correct) = decodeDepositPayload(payload);

            if (!correct || msg.value < Gas.GAUGE_MIN_MSG_VALUE || lock_time > maxLockTime) {
                // too low deposit value or too low msg.value or incorrect deposit payload
                // for incorrect deposit payload send tokens back to sender
                emit DepositReverted(call_id, deposit_owner, amount);
                _transferTokens(depositTokenWallet, amount, sender, payload, remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
                return;
            }

            updateRewardData();

            uint128 boosted_amount = calculateBoostedBalance(amount, lock_time);
            depositTokenBalance += amount;
            lockBoostedSupply += boosted_amount;

            deposit_nonce += 1;
            deposits[deposit_nonce] = PendingDeposit(deposit_owner, amount, boosted_amount, lock_time, remainingGasTo, nonce, call_id);

            address gaugeAccountAddr = getGaugeAccountAddress(deposit_owner);
            // TODO: up
            IGaugeAccount(gaugeAccountAddr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                deposit_nonce,
                amount,
                boosted_amount,
                lock_time,
                extraRewards,
                qubeReward.rewardRounds,
                lastRewardTime
            );
        } else if (msg.sender == qubeReward.tokenData.tokenWallet && sender == voteEscrow) {
            TvmSlice slice = payload.toSlice();
            uint32 round_len = slice.decode(uint32);
            _addQubeRewardRound(amount, round_len);
            remainingGasTo.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
        } else {
            for (uint i = 0; i < extraRewards.length; i++) {
                if (msg.sender == extraRewards[i].tokenData.tokenWallet) {
                    (uint32 call_id, uint32 nonce, bool correct) = decodeRewardDepositPayload(payload);
                    if (!correct) {
                        emit DepositReverted(call_id, sender, amount);
                        _transferTokens(msg.sender, amount, sender, payload, remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
                        return;
                    }

                    extraRewards[i].tokenData.tokenBalance += amount;
                    emit RewardDeposit(call_id, i, amount);

                    _sendCallbackOrGas(sender, nonce, true, remainingGasTo);
                    return;
                }
            }
        }
    }

    function revertDeposit(address user, uint64 _deposit_nonce) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        PendingDeposit deposit = deposits[_deposit_nonce];
        depositTokenBalance -= deposit.amount;
        lockBoostedSupply -= deposit.boosted_amount;

        emit DepositReverted(deposit.call_id, deposit.user, deposit.amount);
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

    function finishDeposit(address user, uint64 _deposit_nonce) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        PendingDeposit deposit = deposits[_deposit_nonce];

        emit Deposit(deposit.call_id, deposit.user, deposit.amount, deposit.lock_time);
        delete deposits[_deposit_nonce];

        _sendCallbackOrGas(deposit.user, deposit.nonce, true, deposit.send_gas_to);
    }

    function withdraw(uint128 amount, uint32 call_id, uint32 nonce, address send_gas_to) external {
        require (amount > 0, Errors.BAD_INPUT);
        require (msg.value >= Gas.GAUGE_MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        updateRewardData();

        address gaugeAccountAddr = getGaugeAccountAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to GaugeAccount
        IGaugeAccount(gaugeAccountAddr).processWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            amount, extraRewards, qubeReward.rewardRounds, lastRewardTime, call_id, nonce, send_gas_to
        );
    }

    function claimReward(uint32 call_id, uint32 nonce, address send_gas_to) external {
        require (msg.value >= Gas.GAUGE_MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        updateRewardData();

        address gaugeAccountAddr = getGaugeAccountAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to GaugeAccount
        IGaugeAccount(gaugeAccountAddr).processClaimReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            extraRewards, qubeReward.rewardRounds, lastRewardTime, call_id, nonce, send_gas_to
        );
    }

    function finishWithdraw(
        address user,
        uint128 withdrawAmount,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        depositTokenBalance -= withdrawAmount;
        emit Withdraw(call_id, user, withdrawAmount);

        _transferTokens(depositTokenWallet, withdrawAmount, user, _makeCell(nonce), send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }

    function finishClaim(
        address user,
        uint128 qube_amount,
        uint128[] extra_amounts,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        (
            uint128 _qube_amount,
            uint128[] _extra_amount,
            uint128 _qube_debt,
            uint128[] _extra_debt
        ) = _transferReward(msg.sender, user, qube_amount, extra_amounts, send_gas_to, nonce);

        emit Claim(call_id, user, _qube_amount, _extra_amount, _qube_debt, _extra_debt);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdrawUnclaimed(uint128[] ids, address to, uint32 call_id, uint32 nonce, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.GAUGE_MIN_MSG_VALUE + Gas.TOKEN_TRANSFER_VALUE * ids.length, Errors.LOW_MSG_VALUE);
        uint128[] extra_amounts = new uint128[](extraRewards.length);

        for (uint i = 0; i < ids.length; i++) {
            ExtraRewardData _reward_data = extraRewards[ids[i]];
            RewardRound _last_round = _reward_data.rewardRounds[_reward_data.rewardRounds.length - 1];
            uint32 lock_time = _last_round.endTime + extraVestingPeriods[ids[i]] + withdrawAllLockPeriod;

            require (_reward_data.ended, Errors.CANT_WITHDRAW_UNCLAIMED_ALL);
            require (now >= lock_time, Errors.CANT_WITHDRAW_UNCLAIMED_ALL);

            extra_amounts[ids[i]] = extraRewards[ids[i]].tokenData.tokenBalance;
        }
        tvm.rawReserve(_reserve(), 0);

        _transferReward(address.makeAddrNone(), to, 0, extra_amounts, send_gas_to, nonce);

        emit WithdrawUnclaimed(call_id, to, extra_amounts);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function deployGaugeAccount(address gauge_account_owner) internal returns (address) {
        TvmBuilder constructor_params;

        constructor_params.store(gauge_account_version); // 32
        constructor_params.store(gauge_account_version); // 32

        constructor_params.store(uint8(extraRewards.length)); // 8

        constructor_params.store(qubeReward.vestingPeriod); // 32
        constructor_params.store(qubeReward.vestingRatio); // 32

        constructor_params.store(extraVestingPeriods); // 32 + ref
        constructor_params.store(extraVestingRatios); // 32 + ref

        return new Platform{
            stateInit: _buildInitData(_buildGaugeAccountParams(gauge_account_owner)),
            value: Gas.GAUGE_ACCOUNT_DEPLOY_VALUE
        }(gaugeAccountCode, constructor_params.toCell(), gauge_account_owner);
    }

    onBounce(TvmSlice slice) external {
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
            ITokenRoot(qubeReward.tokenData.tokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.dummy}(
                deposit.user,
                Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
            );
            for (uint i = 0; i < extraRewards.length; i++) {
                ITokenRoot(extraRewards[i].tokenData.tokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.dummy}(
                    deposit.user,
                    Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
                );
            }
             IGaugeAccount(gauge_account_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                _deposit_nonce,
                deposit.amount,
                deposit.boosted_amount,
                deposit.lock_time,
                extraRewards,
                qubeReward.rewardRounds,
                lastRewardTime
            );
        }
    }
}
