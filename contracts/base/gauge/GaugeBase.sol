pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./GaugeRewards.sol";
import "../../interfaces/IGaugeAccount.sol";
import "../../libraries/PlatformTypes.sol";
import "../../libraries/Errors.sol";
import "../../GaugeAccount.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";


abstract contract GaugeBase is GaugeRewards {
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
        ITokenRoot(qubeReward.tokenData.tokenRoot).deployWallet{value: TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.receiveTokenWalletAddress }(
            address(this), // owner
            TOKEN_WALLET_DEPLOY_GRAMS_VALUE // deploy grams
        );

        for (uint i = 0; i < extraRewards.length; i++) {
            ITokenRoot(extraRewards[i].tokenData.tokenRoot).deployWallet{value: TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.receiveTokenWalletAddress}(
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
            IGaugeAccount(gauge_account_addr).increasePoolDebt{value: INCREASE_DEBT_VALUE, flag: 0}(
                _qube_debt, _extra_debt, send_gas_to, gauge_account_version
            );
        }

        TvmBuilder builder;
        builder.store(nonce);

        // pay extra rewards
        for (uint i = 0; i < _extra_amount.length; i++) {
            if (_extra_amount[i] > 0) {
                _transferTokens(extraRewards[i].tokenData.tokenWallet, _extra_amount[i], receiver_addr, builder.toCell(), send_gas_to, 0);
                extraRewards[i].tokenData.tokenBalance -= _extra_amount[i];
            }
        }
        // pay qube rewards
        if (_qube_amount > 0) {
            _transferTokens(qubeReward.tokenData.tokenWallet, _qube_amount, receiver_addr, builder.toCell(), send_gas_to, 0);
            qubeReward.tokenData.tokenBalance -= _qube_amount;
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
                if (msg.sender == extraRewards[i].tokenData.tokenWallet) {
                    extraRewards[i].tokenData.tokenBalance += amount;
                    extraRewards[i].tokenData.tokenBalanceCumulative += amount;

                    emit RewardDeposit(i, amount);
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
        require (msg.value >= MIN_CALL_MSG_VALUE + TOKEN_TRANSFER_VALUE * extraRewards.length, Errors.LOW_WITHDRAW_MSG_VALUE);
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
            require (extraFarmEndTimes[ids[i]] > 0, Errors.CANT_WITHDRAW_UNCLAIMED_ALL);
            uint32 lock_time = extraFarmEndTimes[ids[i]] + extraVestingPeriods[ids[i]] + withdrawAllLockPeriod;
            require (now >= lock_time, Errors.CANT_WITHDRAW_UNCLAIMED_ALL);

            extra_amounts[ids[i]] = extraRewards[ids[i]].tokenData.tokenBalance;
        }
        tvm.rawReserve(_reserve(), 0);

        _transferReward(address.makeAddrNone(), to, 0, extra_amounts, send_gas_to, nonce);

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

    function finishSafeWithdraw(address user, uint128 amount, address send_gas_to) external onlyGaugeAccount(user) override {
        tvm.rawReserve(_reserve(), 0);

        depositTokenBalance -= amount;
        TvmCell tvmcell;
        emit SafeWithdraw(user, amount);
        _transferTokens(depositTokenWallet, amount, user, tvmcell, send_gas_to, MsgFlag.ALL_NOT_RESERVED);
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
            for (uint i = 0; i < extraRewards.length; i++) {
                // TODO: deploy qube wallet
                // user first deposit? try deploy wallet for him
                ITokenRoot(extraRewards[i].tokenData.tokenRoot).deployWallet{value: TOKEN_WALLET_DEPLOY_VALUE, callback: GaugeBase.dummy}(
                    deposit.user,
                    TOKEN_WALLET_DEPLOY_GRAMS_VALUE // deploy grams
                );
            }
            // try again
//            IGaugeAccount(gauge_account_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
//                _deposit_nonce, deposit.amount, extraRewards.accRewardPerShare, lastRewardTime, extraFarmEndTime, gauge_account_version
//            );

        }
    }
}
