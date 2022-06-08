pragma ton-solidity ^0.60.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../../libraries/Errors.sol";
import "../../interfaces/IGaugeAccount.sol";
import "./VoteEscrowVoting.sol";


// TODO: DEBUG ONLY
import "locklift/locklift/console.sol";


abstract contract VoteEscrowBase is VoteEscrowVoting {
    function receiveTokenWalletAddress(address wallet) external override {
        require (msg.sender == qube);
        qubeWallet = wallet;
    }

    function onAcceptTokensTransfer(
        address,
        uint128 amount,
        address sender,
        address,
        address remainingGasTo,
        TvmCell payload
    ) external override {
        require (msg.sender == qubeWallet, Errors.NOT_TOKEN_WALLET);
        tvm.rawReserve(_reserve(), 0);

        (
            uint8 deposit_type,
            uint32 nonce,
            uint32 call_id,
            TvmCell additional_payload,
            bool correct
        ) = decodeTokenTransferPayload(payload);

        // common cases
        bool exception = !correct || paused || !initialized || emergency || msg.value < Gas.MIN_MSG_VALUE || uint8(deposit_type) > 2;

        // specific cases
        if (deposit_type == uint8(DepositType.userDeposit)) {
            (address deposit_owner, uint32 lock_time) = decodeDepositPayload(additional_payload);
            exception = exception || lock_time < qubeMinLockTime || lock_time > qubeMaxLockTime;
            sender = deposit_owner;

            if (!exception) {
                // deposit logic
                uint128 ve_minted = calculateVeMint(amount, lock_time);
                deposit_nonce += 1;
                pending_deposits[deposit_nonce] = PendingDeposit(deposit_owner, amount, ve_minted, lock_time, remainingGasTo, nonce, call_id);

                address ve_account_addr = getVoteEscrowAccountAddress(deposit_owner);
                IVoteEscrowAccount(ve_account_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                    deposit_nonce, amount, ve_minted, lock_time, nonce, remainingGasTo
                );
                return;
            }
        } else if (deposit_type == uint8(DepositType.whitelist)) {
            address whitelist_addr = decodeWhitelistPayload(additional_payload);
            exception = exception || gaugeWhitelist[whitelist_addr] == true || amount < gaugeWhitelistPrice || currentVotingStartTime != 0;
            if (!exception) {
                // whitelist address
                qubeBalance += amount;
                whitelistPayments += amount;
                _addToWhitelist(whitelist_addr, call_id);
                _sendCallbackOrGas(sender, nonce, true, remainingGasTo);
                return;
            }
        } else if (deposit_type == uint8(DepositType.adminDeposit)) {
            if (!exception) {
                emit DistributionSupplyIncrease(call_id, amount);
                // tokens for distribution
                qubeBalance += amount;
                distributionSupply += amount;
                _sendCallbackOrGas(sender, nonce, true, remainingGasTo);
                return;
            }
        }

        if (exception) {
            emit DepositRevert(call_id, sender, amount);
            // if payload assembled correctly, send nonce, otherwise send payload we got with this transfer
            payload = correct ? _makeCell(nonce) : payload;
            _transferQubes(amount, sender, payload, remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
        }
    }

    function revertDeposit(address user, uint32 deposit_nonce) external override onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);
        PendingDeposit deposit = pending_deposits[deposit_nonce];
        delete pending_deposits[deposit_nonce];

        emit DepositRevert(deposit.call_id, deposit.user, deposit.amount);
        _transferQubes(
            deposit.amount, deposit.user, _makeCell(deposit.nonce), deposit.send_gas_to, MsgFlag.ALL_NOT_RESERVED
        );
    }

    function finishDeposit(address user, uint32 deposit_nonce) external override onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);
        PendingDeposit deposit = pending_deposits[deposit_nonce];
        delete pending_deposits[deposit_nonce];

        emit Deposit(deposit.call_id, deposit.user, deposit.amount, deposit.ve_amount, deposit.lock_time);
        updateAverage();
        qubeBalance += deposit.amount;
        veQubeBalance += deposit.ve_amount;

        _sendCallbackOrGas(user, deposit.nonce, true, deposit.send_gas_to);
    }

    function withdraw(uint32 call_id, uint32 nonce, address send_gas_to) external view onlyActive {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        address ve_acc_addr = getVoteEscrowAccountAddress(msg.sender);
        IVoteEscrowAccount(ve_acc_addr).processWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(call_id, nonce, send_gas_to);
    }

    function revertWithdraw(
        address user, uint32 call_id, uint32 nonce, address send_gas_to
    ) external override onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        emit WithdrawRevert(call_id, user);
        _sendCallbackOrGas(user, nonce, false, send_gas_to);
    }

    function finishWithdraw(
        address user, uint128 unlockedQubes, uint32 call_id, uint32 nonce, address send_gas_to
    ) external override onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        updateAverage();
        emit Withdraw(call_id, user, unlockedQubes);

        qubeBalance -= unlockedQubes;
        _transferQubes(unlockedQubes, user, _makeCell(nonce), send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }

    function burnVeQubes(address user, uint128 expiredVeQubes) external override onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        updateAverage();
        veQubeBalance -= expiredVeQubes;
        emit VeQubesBurn(user, expiredVeQubes);

        user.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setQubeLockTimeLimits(uint32 new_min, uint32 new_max, uint32 call_id, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        qubeMinLockTime = new_min;
        qubeMaxLockTime = new_max;

        emit NewQubeLockLimits(call_id, new_min, new_max);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setPause(bool new_state, uint32 call_id, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        paused = new_state;
        emit PauseUpdate(call_id, new_state);

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setEmergency(bool new_state, uint32 call_id, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        emergency = new_state;
        emit EmergencyUpdate(call_id, new_state);

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setWhitelistPrice(uint128 new_price, uint32 call_id, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        gaugeWhitelistPrice = new_price;

        emit WhitelistPriceUpdate(call_id, new_price);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function addToWhitelist(address gauge, uint32 call_id, address send_gas_to) external onlyOwner {
        // cant add gauge to whitelist during voting
        require (currentVotingStartTime == 0, Errors.BAD_INPUT);
        tvm.rawReserve(_reserve(), 0);

        _addToWhitelist(gauge, call_id);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function removeFromWhitelist(address gauge, uint32 call_id, address send_gas_to) external onlyOwner {
        // cant remove gauge from whitelist during voting
        require (currentVotingStartTime == 0, Errors.BAD_INPUT);
        tvm.rawReserve(_reserve(), 0);

        _removeFromWhitelist(gauge, call_id);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function calculateVeMint(uint128 qube_amount, uint32 lock_time) public view returns (uint128 ve_amount) {
        // qube has 18 decimals, there should be no problems with division precision
        return math.muldiv(qube_amount, lock_time, qubeMaxLockTime);
    }

    function getVeAverage(uint32 nonce) external override {
        tvm.rawReserve(_reserve(), 0);

        updateAverage();

        IGaugeAccount(msg.sender).receiveVeAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            nonce, veQubeBalance, veQubeAverage, veQubeAveragePeriod
        );
    }

    function calculateAverage() public view returns (
        uint32 _lastUpdateTime, uint128 _veQubeBalance, uint128 _veQubeAverage, uint32 _veQubeAveragePeriod
    ) {
        if (now <= lastUpdateTime || lastUpdateTime == 0) {
            // already updated on this block or this is our first update
            return (now, veQubeBalance, veQubeAverage, veQubeAveragePeriod);
        }

        uint32 last_period = now - lastUpdateTime;
        _veQubeAverage = (veQubeAverage * veQubeAveragePeriod + veQubeBalance * last_period) / (veQubeAveragePeriod + last_period);
        _veQubeAveragePeriod += last_period;
        _lastUpdateTime = now;
        _veQubeBalance = veQubeBalance;
    }

    function updateAverage() internal {
        (lastUpdateTime, veQubeBalance, veQubeAverage, veQubeAveragePeriod) = calculateAverage();
    }

    onBounce(TvmSlice slice) external view {
        tvm.accept();

        uint32 functionId = slice.decode(uint32);
        // if processing failed - contract was not deployed. Deploy and try again
        if (functionId == tvm.functionId(IVoteEscrowAccount.processDeposit)) {
            tvm.rawReserve(_reserve(), 0);

            uint32 _deposit_nonce = slice.decode(uint32);
            PendingDeposit deposit = pending_deposits[_deposit_nonce];
            address gauge_account_addr = deployVoteEscrowAccount(deposit.user);

            IVoteEscrowAccount(gauge_account_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                _deposit_nonce, deposit.amount, deposit.ve_amount, deposit.lock_time, deposit.nonce, deposit.send_gas_to
            );
        }
    }
}
