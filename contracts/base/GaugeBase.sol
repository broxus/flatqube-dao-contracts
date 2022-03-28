pragma ton-solidity ^0.58.2;
pragma AbiHeader expire;


import "./GaugeUpgradable.sol";
import "../interfaces/IGaugeAccount.sol";
import "../libraries/PlatformTypes.sol";
import "../libraries/Errors.sol";
import "../GaugeAccount.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";


abstract contract GaugeBase is GaugeUpgradable {
    function _initRewardData(
        RewardRound[] _extraRewardRounds,
        address[] _reward_token_root,
        uint32[] _vesting_period,
        uint32[] _vesting_ratio
    ) internal {
        for (uint i = 0; i < _reward_token_root[i].length; i++) {
            ExtraRewardData _reward;
            _reward.mainData.tokenRoot = _reward_token_root[i];
            _reward.mainData.vestingPeriod = _vesting_period[i];
            _reward.mainData.vestingRatio = _vesting_ratio[i];
            _reward.rewardRounds.push(_extraRewardRounds[i]);
        }
    }

    modifier onlyGaugeAccount(address user) {
        address expectedAddr = getGaugeAccountAddress(user);
        require (expectedAddr == msg.sender, Errors.NOT_GAUGE_ACCOUNT);
        _;
    }

    // TODO: sync
    function getDetails() external view responsible returns (Details) {
        return { value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS }Details(
            lastRewardTime, voteEscrow, depositTokenRoot, depositTokenWallet, depositTokenBalance,
            qubeReward, extraRewards, owner, factory,gauge_account_version, gauge_version
        );
    }

    /*
        @notice Creates token wallet for configured root token, initialize arrays and send callback to factory
    */
    function _setUpTokenWallets() internal {
        // Deploy vault's token wallet
        ITokenRoot(depositTokenRoot).deployWallet{value: TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.receiveTokenWalletAddress }(
            address(this), // owner
            TOKEN_WALLET_DEPLOY_GRAMS_VALUE // deploy grams
        );

        // deploy qube wallet
        ITokenRoot(qubeReward.mainData.tokenRoot).deployWallet{value: TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.receiveTokenWalletAddress }(
            address(this), // owner
            TOKEN_WALLET_DEPLOY_GRAMS_VALUE // deploy grams
        );

        for (uint i = 0; i < extraRewards.length; i++) {
            ITokenRoot(extraRewards[i].mainData.tokenRoot).deployWallet{value: TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.receiveTokenWalletAddress}(
                address(this), // owner address
                TOKEN_WALLET_DEPLOY_GRAMS_VALUE // deploy grams
            );
        }
    }

    function dummy(address user_wallet) external { tvm.rawReserve(_reserve(), 0); }

    /*
        @notice Store vault's token wallet address
        @dev Only root can call with correct params
        @param wallet Gauge's token wallet
    */
    function receiveTokenWalletAddress(
        address wallet
    ) external {
        tvm.rawReserve(_reserve(), 0);

        if (msg.sender == depositTokenRoot) {
            depositTokenWallet = wallet;
        } else if (msg.sender == qubeReward.mainData.tokenRoot) {
            qubeReward.mainData.tokenWallet = wallet;
        } else {
            for (uint i = 0; i < extraRewards.length; i++) {
                if (msg.sender == extraRewards[i].mainData.tokenRoot) {
                    extraRewards[i].mainData.tokenWallet = wallet;
                }
            }
        }
    }

    function _transferTokens(
        address token_wallet, uint128 amount, address receiver, TvmCell payload, address send_gas_to, uint16 flag
    ) internal {
        uint128 value;
        if (flag != MsgFlag.ALL_NOT_RESERVED) {
            value = TOKEN_TRANSFER_VALUE;
        }
        ITokenWallet(token_wallet).transfer{value: value, flag: flag}(
            amount,
            receiver,
            0,
            send_gas_to,
            true,
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
            if (extraRewards[i].mainData.tokenBalance < extra_amounts[i]) {
                _extra_debt[i] = extra_amounts[i] - extraRewards[i].mainData.tokenBalance;
                _extra_amount[i] -= _extra_debt[i];
                have_debt = true;
            }
        }
        // check if we have enough qube, emit debt otherwise
        if (qubeReward.mainData.tokenBalance < qube_amount) {
            _qube_debt = qube_amount - qubeReward.mainData.tokenBalance;
            _qube_amount -= _qube_debt;
            have_debt = true;
        }

        // check if its user or admin
        // for user we emit debt, for admin just claim possible extra_amounts (withdrawUnclaimed)
        if (gauge_account_addr != address.makeAddrNone() && have_debt) {
            IGaugeAccount(gauge_account_addr).increasePoolDebt{value: INCREASE_DEBT_VALUE, flag: 0}(
                _qube_debt, _extra_debt, send_gas_to, gauge_account_version
            );
        }

        TvmBuilder builder;
        builder.store(nonce);

        // pay extra rewards
        for (uint i = 0; i < _extra_amount.length; i++) {
            if (_extra_amount[i] > 0) {
                _transferTokens(extraRewards[i].mainData.tokenWallet, _extra_amount[i], receiver_addr, builder.toCell(), send_gas_to, 0);
                extraRewards[i].mainData.tokenBalance -= _extra_amount[i];
            }
        }
        // pay qube rewards
        if (_qube_amount > 0) {
            _transferTokens(qubeReward.mainData.tokenWallet, _qube_amount, receiver_addr, builder.toCell(), send_gas_to, 0);
            qubeReward.mainData.tokenBalance -= _qube_amount;
        }
        return (_qube_amount, _extra_amount, _qube_debt, _extra_debt);
    }

    function encodeDepositPayload(address deposit_owner, uint32 nonce) external pure returns (TvmCell deposit_payload) {
        TvmBuilder builder;
        builder.store(deposit_owner);
        builder.store(nonce);
        return builder.toCell();
    }

    // try to decode deposit payload
    function decodeDepositPayload(TvmCell payload) public view returns (address deposit_owner, uint32 nonce, bool correct) {
        // check if payload assembled correctly
        TvmSlice slice = payload.toSlice();
        // 1 address and 1 cell
        if (!slice.hasNBitsAndRefs(267 + 32, 0)) {
            return (address.makeAddrNone(), 0, false);
        }

        deposit_owner = slice.decode(address);
        nonce = slice.decode(uint32);

        return (deposit_owner, nonce, true);
    }

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
            (address deposit_owner, uint32 nonce, bool correct) = decodeDepositPayload(payload);

            if (!correct || msg.value < (MIN_CALL_MSG_VALUE + TOKEN_TRANSFER_VALUE * extraRewards.length)) {
                // too low deposit value or too low msg.value or incorrect deposit payload
                // for incorrect deposit payload send tokens back to sender
                _transferTokens(depositTokenWallet, amount, sender, payload, remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
                return;
            }

            updateRewardData();

            deposit_nonce += 1;
            deposits[deposit_nonce] = PendingDeposit(deposit_owner, amount, remainingGasTo, nonce);

            address gaugeAccountAddr = getGaugeAccountAddress(deposit_owner);
            // TODO: up
            IGaugeAccount(gaugeAccountAddr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                deposit_nonce,
                amount,
                extraRewards,
                lastRewardTime,
                gauge_account_version
            );
        } else {
            for (uint i = 0; i < extraRewards.length; i++) {
                if (msg.sender == extraRewards[i].mainData.tokenWallet) {
                    extraRewards[i].mainData.tokenBalance += amount;
                    extraRewards[i].mainData.tokenBalanceCumulative += amount;

                    emit RewardDeposit(extraRewards[i].mainData.tokenRoot, amount);
                }
            }
            remainingGasTo.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }
    }

    function finishDeposit(address user, uint64 _deposit_nonce) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        PendingDeposit deposit = deposits[_deposit_nonce];
        depositTokenBalance += deposit.amount;

        emit Deposit(deposit.user, deposit.amount);
        delete deposits[_deposit_nonce];

        deposit.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdraw(uint128 amount, address send_gas_to, uint32 nonce) external {
        require (amount > 0, Errors.ZERO_AMOUNT_INPUT);
        require (msg.value >= MIN_CALL_MSG_VALUE + TOKEN_TRANSFER_VALUE * extraRewards.length, Errors.LOW_WITHDRAW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        updateRewardData();

        address gaugeAccountAddr = getGaugeAccountAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to GaugeAccount
        IGaugeAccount(gaugeAccountAddr).processWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            amount, extraRewards, lastRewardTime, send_gas_to, nonce, gauge_account_version
        );
    }

    function claimReward(address send_gas_to, uint32 nonce) external {
        require (msg.value >= MIN_CALL_MSG_VALUE + TOKEN_TRANSFER_VALUE * extraRewards.tokenRoot.length, Errors.LOW_WITHDRAW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        updateRewardData();

        address gaugeAccountAddr = getGaugeAccountAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to GaugeAccount
        IGaugeAccount(gaugeAccountAddr).processClaimReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            extraRewards, lastRewardTime, send_gas_to, nonce, gauge_account_version
        );
    }

    function finishWithdraw(
        address user,
        uint128 _withdrawAmount,
        address send_gas_to,
        uint32 nonce
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        depositTokenBalance -= _withdrawAmount;

        emit Withdraw(user, _withdrawAmount);
        TvmBuilder builder;
        builder.store(nonce);
        _transferTokens(depositTokenWallet, _withdrawAmount, user, builder.toCell(), send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }

    function finishClaim(
        address user,
        uint128 qube_amount,
        uint128[] extra_amounts,
        address send_gas_to,
        uint32 nonce
    ) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        (
            uint128 _qube_amount,
            uint128[] _extra_amount,
            uint128 _qube_debt,
            uint128[] _extra_debt
        ) = _transferReward(msg.sender, user, qube_amount, extra_amounts, send_gas_to, nonce);

        emit Claim(user, _qube_amount, _extra_amount, _qube_debt, _extra_debt);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdrawUnclaimed(uint128[] ids, address to, address send_gas_to, uint32 nonce) external onlyOwner {
        require (msg.value >= MIN_CALL_MSG_VALUE + TOKEN_TRANSFER_VALUE * ids.length, Errors.LOW_WITHDRAW_MSG_VALUE);
        uint128[] extra_amounts = new uint128[](extraRewards.length);

        for (uint i = 0; i < ids.length; i++) {
            require (extraRewards[ids[i]].farmEndTime > 0, Errors.CANT_WITHDRAW_UNCLAIMED_ALL);
            uint32 lock_time = extraRewards[ids[i]].farmEndTime + extraRewards[ids[i]].mainData.vestingPeriod + withdrawAllLockPeriod;
            require (now >= lock_time, Errors.CANT_WITHDRAW_UNCLAIMED_ALL);

            extra_amounts[ids[i]] = extraRewards[ids[i]].mainData.rewardTokenBalance;
        }
        tvm.rawReserve(_reserve(), 0);

        _transferReward(address.makeAddrNone(), to, 0, extra_amounts, send_gas_to, nonce);

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function addRewardRounds(uint128[] ids, RewardRound[] new_rounds, address send_gas_to) external onlyOwner {
        require (ids.length == new_rounds.length, Errors.BAD_REWARD_ROUNDS_INPUT);

        for (uint i = 0; i < ids.length; i++) {
            require (new_rounds[i].startTime >= now, Errors.BAD_REWARD_ROUNDS_INPUT);
            RewardRound[] _cur_rounds = extraRewards[ids[i]].rewardRounds;
            require (new_rounds[i].startTime >= _cur_rounds[_cur_rounds.length - 1].startTime, Errors.BAD_REWARD_ROUNDS_INPUT);
            require (extraRewards[ids[i]].farmEndTime == 0, Errors.BAD_REWARD_ROUNDS_INPUT);

            extraRewards[ids[i]].rewardRounds.push(new_rounds[i]);
        }

        tvm.rawReserve(_reserve(), 0);

        emit RewardRoundAdded(ids, new_rounds);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setExtraFarmEndTime(uint128[] ids, uint32[] farm_end_times, address send_gas_to) external onlyOwner {
        require (ids.length == farm_end_times.length, Errors.BAD_FARM_END_TIME);
        for (uint i = 0; i < ids.length; i++) {
            require (farm_end_times[i] >= now, Errors.BAD_FARM_END_TIME);
            RewardRound[] _cur_rounds = extraRewards[ids[i]].rewardRounds;
            require (farm_end_times[i] >=  _cur_rounds[_cur_rounds.length - 1].startTime, Errors.BAD_FARM_END_TIME);
            require (extraRewards[ids[i]].farmEndTime == 0, Errors.BAD_REWARD_ROUNDS_INPUT);

            extraRewards[ids[i]].farmEndTime = farm_end_times[i];
        }

        tvm.rawReserve(_reserve(), 0);

        emit ExtraFarmEndSet(ids, farm_end_times);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    // withdraw all staked tokens without reward in case of some critical logic error / insufficient tons on FarmPool balance
    function safeWithdraw(address send_gas_to) external view {
        require (msg.value >= MIN_CALL_MSG_VALUE, Errors.LOW_WITHDRAW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        address gauge_account_addr = getGaugeAccountAddress(msg.sender);
        IGaugeAccount(gauge_account_addr).processSafeWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            send_gas_to, gauge_account_version
        );
    }

    function finishSafeWithdraw(address user, uint128 amount, address send_gas_to) external override {
        address expectedAddr = getGaugeAccountAddress(user);
        require (expectedAddr == msg.sender, Errors.NOT_GAUGE_ACCOUNT);
        tvm.rawReserve(_reserve(), 0);

        depositTokenBalance -= amount;

        uint128[] _reward;
        uint128[] _reward_debt;

        TvmCell tvmcell;
        emit Withdraw(user, amount, _reward, _reward_debt);

        _transferTokens(depositTokenWallet, amount, user, tvmcell, send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }

    function _getMultiplier(uint32 _farmStartTime, uint32 _extraFarmEndTime, uint32 from, uint32 to) internal view returns(uint32) {
        require (from <= to, Errors.WRONG_INTERVAL);

        if ((from > _extraFarmEndTime) || (to < _farmStartTime)) {
            return 0;
        }

        if (to > _extraFarmEndTime) {
            to = _extraFarmEndTime;
        }

        if (from < _farmStartTime) {
            from = _farmStartTime;
        }

        return to - from;
    }

    function _getRoundEndTime(uint256 round_id) internal view returns (uint32) {
        bool last_round = round_id == rewardRounds.length - 1;
        uint32 _extraFarmEndTime;
        if (last_round) {
            // if this round is last, check if end is setup and return it, otherwise return max uint value
            _extraFarmEndTime = extraFarmEndTime > 0 ? extraFarmEndTime : MAX_UINT32;
        } else {
            // next round exists, its start time is this round's end time
            _extraFarmEndTime = rewardRounds[round_id + 1].startTime;
        }
        return _extraFarmEndTime;
    }

    function calculateRewardData() public view returns (uint32 _lastRewardTime, uint256[] _accRewardPerShare, uint128[] _unclaimedReward) {
        _lastRewardTime = lastRewardTime;
        _accRewardPerShare = extraRewards.accRewardPerShare;
        _unclaimedReward = extraRewards.unclaimedReward;

        uint32 first_round_start = rewardRounds[0].startTime;

        // reward rounds still not started, nothing to calculate
        if (now < first_round_start) {
            _lastRewardTime = now;
            return (_lastRewardTime, _accRewardPerShare, _unclaimedReward);
        }

        if (now > _lastRewardTime) {
            // special case - last update occurred before start of 1st round
            if (_lastRewardTime < first_round_start) {
                _lastRewardTime = math.min(first_round_start, now);
            }

            for (uint i = rewardRounds.length - 1; i >= 0; i--) {
                // find reward round when last update occurred
                if (_lastRewardTime >= rewardRounds[i].startTime) {
                    // we found reward round when last update occurred, start updating reward from this point
                    for (uint j = i; j < rewardRounds.length; j++) {
                        // we didnt reach this round
                        if (now <= rewardRounds[j].startTime) {
                            break;
                        }
                        uint32 _roundEndTime = _getRoundEndTime(j);
                        // get multiplier bounded by this reward round
                        uint32 multiplier = _getMultiplier(rewardRounds[j].startTime, _roundEndTime, _lastRewardTime, now);
                        uint128[] new_reward;
                        for (uint k = 0; k < rewardRounds[j].rewardPerSecond.length; k++) {
                            new_reward.push(rewardRounds[j].rewardPerSecond[k] * multiplier);
                        }
                        uint32 new_reward_time;
                        if (_roundEndTime == extraFarmEndTime) {
                            new_reward_time = now;
                        } else {
                            new_reward_time = math.min(_roundEndTime, now);
                        }

                        if (depositTokenBalance == 0) {
                            for (uint k = 0; k < rewardRounds[j].rewardPerSecond.length; k++) {
                                _unclaimedReward[k] += new_reward[k];
                            }
                            _lastRewardTime = new_reward_time;
                            continue;
                        }

                        for (uint k = 0; k < rewardRounds[j].rewardPerSecond.length; k++) {
                            uint256 scaled_reward = uint256(new_reward[k]) * SCALING_FACTOR;
                            _accRewardPerShare[k] += scaled_reward / depositTokenBalance;
                        }
                        _lastRewardTime = new_reward_time;
                    }
                    break;
                }
                if (i == 0) {
                    // break to avoid integer overflow
                    break;
                }
            }
        }
        return (_lastRewardTime, _accRewardPerShare, _unclaimedReward);
    }

    function updateRewardData() internal {
        (uint32 _lastRewardTime, uint256[] _accRewardPerShare, uint128[] _unclaimedReward) = calculateRewardData();
        lastRewardTime = _lastRewardTime;
        extraRewards.accRewardPerShare = _accRewardPerShare;
        extraRewards.unclaimedReward = _unclaimedReward;
    }


    function deployGaugeAccount(address gauge_account_owner) internal returns (address) {
        TvmBuilder constructor_params;

        constructor_params.store(gauge_account_version);
        constructor_params.store(gauge_account_version);

        constructor_params.store(uint8(extraRewards.tokenRoot.length));
        constructor_params.store(qubeReward.vestingPeriod);
        constructor_params.store(qubeReward.vestingRatio);
        constructor_params.store(extraRewards.vestingRatio); // ref
        constructor_params.store(extraRewards.vestingRatio); // ref

        return new Platform{
            stateInit: _buildInitData(_buildGaugeAccountParams(gauge_account_owner)),
            value: GAUGE_ACCOUNT_DEPLOY_VALUE
        }(gaugeAccountCode, constructor_params.toCell(), gauge_account_owner);
    }

    onBounce(TvmSlice slice) external {
        tvm.accept();

        uint32 functionId = slice.decode(uint32);
        // if processing failed - contract was not deployed. Deploy and try again
        if (functionId == tvm.functionId(GaugeAccountV2.processDeposit)) {
            tvm.rawReserve(_reserve(), 0);

            uint64 _deposit_nonce = slice.decode(uint64);
            PendingDeposit deposit = deposits[_deposit_nonce];
            address gauge_account_addr = deployGaugeAccount(deposit.user);
            for (uint i = 0; i < extraRewards.tokenRoot.length; i++) {
                // user first deposit? try deploy wallet for him
                ITokenRoot(extraRewards.tokenRoot[i]).deployWallet{value: TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.dummy}(
                    deposit.user,
                    TOKEN_WALLET_DEPLOY_GRAMS_VALUE // deploy grams
                );
            }
            // try again
            IGaugeAccount(gauge_account_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(_deposit_nonce, deposit.amount, extraRewards.accRewardPerShare, lastRewardTime, extraFarmEndTime, gauge_account_version);

        }
    }
}
