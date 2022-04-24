pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";
import "./libraries/Errors.sol";
import "./VoteEscrowVoting.sol";


abstract contract VoteEscrowBase is VoteEscrowVoting {
    function receiveTokenWalletAddress(address wallet) external {
        require (msg.sender == qube);
        qubeWallet = wallet;
    }

    function onAcceptTokensTransfer(
        address tokenRoot,
        uint128 amount,
        address sender,
        address senderWallet,
        address remainingGasTo,
        TvmCell payload
    ) external {
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
        bool revert = !correct || paused || !initialized || emergency || msg.value < Gas.MIN_DEPOSIT_VALUE || uint8(deposit_type) > 2;
        // specific cases
        if (deposit_type == DepositType.userDeposit) {
            (address deposit_owner, uint32 lock_time) = decodeDepositPayload(additional_payload);
            revert = revert || lock_time < QUBE_MIN_LOCK_TIME || lock_time > QUBE_MAX_LOCK_TIME;
            sender = deposit_owner;
            if (!revert) {
                // deposit logic
                uint128 ve_minted = calculateVeMint(amount);
                deposit_nonce += 1;
                pending_deposits[deposit_nonce] = PendingDeposit(deposit_owner, amount, ve_minted, lock_time, remainingGasTo, nonce, call_id);

                address ve_account_addr = getVoteEscrowAccountAddress(deposit_owner);
                IVoteEscrowAccount(ve_account_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                    deposit_nonce, amount, ve_minted, lock_time, remainingGasTo, nonce
                );
                return;
            }
        } else if (deposit_type == DepositType.whitelist) {
            address whitelist_addr = decodeWhitelistPayload(additional_payload);
            revert = revert || whitelistedGauges[whitelist_addr] == true || amount < whitelistPrice;
            if (!revert) {
                // whitelist address
                qubeBalance += amount;
                whitelistPayments += amount;
                _addToWhitelist(call_id, whitelist_address);
                _sendCallbackOrGas(sender, nonce, true, remainingGasTo);
                return;
            }
        } else if (deposit_type == DepositType.adminDeposit) {
            if (!revert) {
                emit DistributionSupplyIncrease(call_id, amount);
                // tokens for distribution
                qubeBalance += amount;
                distributionSupply += amount;
                _sendCallbackOrGas(sender, nonce, true, remainingGasTo);
                return;
            }
        }

        if (revert) {
            emit DepositRevert(call_id, sender, amount);
            _transferTokens(qubeWallet, amount, sender, _makeCell(nonce), remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
        }
    }

    function revertDeposit(address user, uint32 deposit_nonce) external onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);
        PendingDeposit deposit = pending_deposits[deposit_nonce];
        delete pending_deposits[deposit_nonce];

        emit DepositRevert(deposit.call_id, deposit.user, deposit.amount);
        _transferTokens(
            qubeWallet, deposit.amount, deposit.user, _makeCell(deposit.nonce), deposit.send_gas_to, MsgFlag.ALL_NOT_RESERVED
        );
    }

    function finishDeposit(address user, uint32 deposit_nonce) external onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);
        PendingDeposit deposit = pending_deposits[deposit_nonce];
        delete pending_deposits[deposit_nonce];

        emit Deposit(deposit.call_id, deposit.user, deposit.amount, deposit.ve_amount, deposit.lock_time);
        updateAverage();
        qubeBalance += deposit.amount;
        veQubeSupply += deposit.ve_amount;

        _sendCallbackOrGas(user, deposit.nonce, true, deposit.send_gas_to);
    }

    function withdraw(uint32 call_id, uint32 nonce, address send_gas_to) external onlyActive {
        // TODO: gas
        require (msg.value >= Gas.MIN_CALL_MSG_VALUE, Errors.LOW_WITHDRAW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        address ve_acc_addr = getVoteEscrowAccountAddress(msg.sender);
        IVoteEscrowAccount(ve_acc_addr).processWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(call_id, nonce, send_gas_to);
    }

    function revertWithdraw(
        address user, uint32 call_id, uint32 nonce, address send_gas_to
    ) external onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        emit WithdrawRevert(call_id, user);
        _sendCallbackOrGas(user, deposit.nonce, false, send_gas_to);
    }

    function finishWithdraw(
        address user, uint128 unlockedQubes, uint32 call_id, uint32 nonce, address send_gas_to
    ) external onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        updateAverage();
        qubeBalance -= unlockedQubes;
        emit Withdraw(call_id, user, unlockedQubes);

        _transferTokens(qubeWallet, unlockedQubes, user, _makeCell(nonce), send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }

    function burnVeQubes(address user, uint128 expiredVeQubes) external onlyVoteEscrowAccount(user) {
        updateAverage();
        veQubeSupply -= expiredVeQubes;
        emit VeQubesBurn(user, expiredVeQubes);
    }

    function setWhitelistPrice(uint128 new_price, uint32 call_id, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        whitelistPrice = new_price;

        emit WhitelistPriceUpdate(call_id, new_price);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function addToWhitelist(address gauge, uint32 call_id, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        _addToWhitelist(call_id, gauge);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function removeFromWhitelist(address gauge, uint32 call_id, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        _removeFromWhitelist(call_id, gauge);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function calculateVeMint(uint128 qube_amount, uint32 lock_time) public view returns (uint128 ve_amount) {
        // qube has 18 decimals, there should be no problems with division precision
        return math.muldiv(qube_amount, lock_time, QUBE_MAX_LOCK_TIME);
    }

    function getVeAverage(uint32 nonce) external {
        tvm.rawReserve(_reserve(), 0);

        updateAverage();

        IGaugeAccount(msg.sender).receiveAverage{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            nonce, veQubeAverage, veQubeAveragePeriod
        );
    }

    function updateAverage() internal {
        if (now <= lastUpdateTime || lastUpdateTime == 0) {
            // already updated on this block or this is our first update
            lastUpdateTime = now;
            return;
        }

        uint32 last_period = now - lastUpdateTime;
        veQubeAverage = (veQubeAverage * veQubeAveragePeriod + veQubeSupply * last_period) / (veQubeAveragePeriod + last_period);
        veQubeAveragePeriod += last_period;
    }

    onBounce(TvmSlice slice) external {
        tvm.accept();

        uint32 functionId = slice.decode(uint32);
        // if processing failed - contract was not deployed. Deploy and try again
        if (functionId == tvm.functionId(VoteEscrowAccount.processDeposit)) {
            tvm.rawReserve(_reserve(), 0);

            uint64 _deposit_nonce = slice.decode(uint32);
            PendingDeposit deposit = pending_deposits[_deposit_nonce];
            address gauge_account_addr = deployVoteEscrowAccount(deposit.user);

            IVoteEscrowAccount(gauge_account_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                _deposit_nonce, deposit.amount, deposit.ve_amount, deposit.lock_time, deposit.nonce, deposit.send_gas_to
            );
        }
    }
}
