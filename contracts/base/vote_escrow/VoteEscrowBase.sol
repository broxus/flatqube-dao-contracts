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
    function _setupTokenWallet() internal {
        ITokenRoot(qube).deployWallet{value: TOKEN_WALLET_DEPLOY_VALUE, callback: VoteEscrow.receiveTokenWalletAddress }(
            address(this), // owner
            TOKEN_WALLET_DEPLOY_GRAMS_VALUE / 2 // deploy grams
        );
    }

    function receiveTokenWalletAddress(address wallet) external {
        require (msg.sender == qube);
        qubeWallet = wallet;
    }

    function _makeCell(uint32 nonce) internal {
        TvmBuilder builder;
        if (nonce > 0) {
            builder.store(nonce);
        }
        return builder.toCell();
    }

    // We have 3 cases on receiving qubes, each case is determined by deposit_type
    // @Case 1 - user make deposit
    // deposit_type - 0
    // deposit_owner - address on which behalf sender making deposit
    // whitelist_address - ignored
    // nonce - nonce, that will be sent with callback, should be > 0 if callback is needed
    // lock_time - lock time for qubes
    // @Case 2 - user pay for whitelisting address
    // deposit_type - 1
    // deposit_owner - ignored
    // whitelist_address - address which will be whitelisted
    // nonce - nonce, that will be sent with callback, should be > 0 if callback is needed
    // lock_time - ignored
    // @Case 3 - send qubes for further distribution
    // deposit_type - 2
    // deposit_owner - ignored
    // whitelist_address - ignored
    // nonce - nonce, that will be sent with callback, should be > 0 if callback is needed
    // lock_time - ignored
    function encodeDepositPayload(
        address deposit_owner, address whitelist_address, uint32 nonce, uint32 lock_time, uint8 deposit_type
    ) external pure returns (TvmCell deposit_payload) {
        TvmBuilder builder;
        builder.store(deposit_owner);
        builder.store(whitelist_address);
        builder.store(nonce);
        builder.store(lock_time);
        builder.store(deposit_type);
        return builder.toCell();
    }

    // try to decode deposit payload
    function decodeDepositPayload(TvmCell payload) public view returns (
        address deposit_owner, address whitelist_address, uint32 nonce, uint32 lock_time, uint8 deposit_type, bool correct
    ) {
        // check if payload assembled correctly
        TvmSlice slice = payload.toSlice();
        // 1 address and 1 cell
        if (!slice.hasNBitsAndRefs(267 + 267 + 32 + 32 + 8, 0)) {
            return (address.makeAddrNone(), address.makeAddrNone(), 0, 0, 0, false);
        }

        deposit_owner = slice.decode(address);
        whitelist_address = slice.decode(address);
        nonce = slice.decode(uint32);
        lock_time = slice.decode(uint32);
        deposit_type = slice.decode(uint8);

        return (deposit_owner, whitelist_address, nonce, lock_time, deposit_type, true);
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
            address deposit_owner,
            address whitelist_address,
            uint32 nonce,
            uint32 lock_time,
            uint8 deposit_type,
            bool correct
        ) = decodeDepositPayload(payload);

        // transfer back on incorrect cases
        if (
            // bad payload
            !correct ||
            // contract is paused
            paused ||
            // origin epoch not created
            !initialized ||
            // emergency mode is on
            emergency ||
            // too low msg.value
            msg.value < MIN_DEPOSIT_VALUE ||
            // too low lock time
            (deposit_type == DepositType.userDeposit && (lock_time < QUBE_MIN_LOCK_TIME || lock_time > QUBE_MAX_LOCK_TIME)) ||
            // address already whitelisted
            (deposit_type == DepositType.whitelist && whitelistedGauges[whitelist_address] == true) ||
            // incorrect deposit_type
            deposit_type > DepositType.adminDeposit
        ) {
            // TODO: emit event
            if (deposit_type == DepositType.userDeposit) {
                sender = deposit_owner;
            }
            _transferTokens(qubeWallet, amount, sender, _makeCell(nonce), remainingGasTo, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

        if (deposit_type == DepositType.userDeposit) {
            // deposit logic
            uint128 ve_minted = calculateVeMint(amount);
            deposit_nonce += 1;
            pending_deposits[deposit_nonce] = PendingDeposit(deposit_owner, amount, ve_minted, lock_time, remainingGasTo, nonce);

            address ve_account_addr = getVoteEscrowAccountAddress(deposit_owner);
            IVoteEscrowAccount(ve_account_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                deposit_nonce, amount, ve_minted, lock_time, remainingGasTo, nonce
            );
        } else if (deposit_type == DepositType.whitelist) {
            // whitelist address
            qubeBalance += amount;
            whitelistPayments += amount;
            _addToWhitelist(whitelist_address);
            remainingGasTo.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
        } else if (deposit_type == DepositType.adminDeposit) {
            // TODO: add event
            // tokens for distribution
            qubeBalance += amount;
            distributionSupply += amount;
            remainingGasTo.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
        }
    }


    modifier onlyActive() {
        require (!paused && !emergency || msg.sender == owner, Errors.NOT_ACTIVE);
        _;
    }

    modifier onlyEmergency() {
        require (emergency, Errors.NOT_EMERGENCY);
        _;
    }

    function revertDeposit(address user, uint32 deposit_nonce) external onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);
        PendingDeposit deposit = pending_deposits[deposit_nonce];
        delete pending_deposits[deposit_nonce];

        // TODO: emit event
        _transferTokens(
            qubeWallet, deposit.amount, deposit.user, _makeCell(deposit.nonce), deposit.send_gas_to, MsgFlag.ALL_NOT_RESERVED
        );
    }

    function finishDeposit(address user, uint32 deposit_nonce) external onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);
        PendingDeposit deposit = pending_deposits[deposit_nonce];
        delete pending_deposits[deposit_nonce];

        // TODO: emit event
        updateAverage();
        qubeBalance += deposit.amount;
        veQubeSupply += deposit.ve_amount;

        // Add callback if nonce >= 0
        deposit.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdraw(uint32 nonce, address send_gas_to) external onlyActive {
        // TODO: gas
        require (msg.value >= Gas.MIN_CALL_MSG_VALUE, Errors.LOW_WITHDRAW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        address ve_acc_addr = getVoteEscrowAccountAddress(msg.sender);
        IVoteEscrowAccount(ve_acc_addr).processWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce, send_gas_to);
    }

    function finishWithdraw(address user, uint128 unlockedQubes, uint32 nonce, address send_gas_to) onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        updateAverage();
        qubeBalance -= unlockedQubes;
        // TODO: emit event

        _transferTokens(qubeWallet, unlockedQubes, user, _makeCell(nonce), send_gas_to, MsgFlag.ALL_NOT_RESERVED);
    }

    function burnVeQubes(address user, uint128 expiredVeQubes) external onlyVoteEscrowAccount(user) {
        updateAverage();
        veQubeSupply -= expiredVeQubes;
    }

    function addToWhitelist(address gauge, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        _addToWhitelist(gauge);
    }

    function removeFromWhitelist(address gauge, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        _removeFromWhitelist(gauge);
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
