pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.sol";
import "broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";
import "./libraries/Errors.sol";


contract VoteEscrow is IAcceptTokensTransferCallback {
//    uint64 static deploy_nonce;
//    TvmCell static platformCode;
//    TvmCell static veAccountCode;
//    uint32 static ve_account_version;
//    uint32 static ve_version;

    address owner;
    address qube;
    address qubeWallet;

    uint128 qubeBalance;
    uint128 veQubeSupply;
    uint32 lastUpdateTime;

    uint128 veQubeAverage;
    uint32 veQubeAveragePeriod;

    uint32 epochTime; // length of epoch in seconds
    uint32 votingTime; // length of voting in seconds
    uint32 timeBeforeVoting; // time after epoch start when next voting will take place

    bool initialized; // require origin epoch to be created
    bool paused; // pause contract in case of some error or update, disable user actions
    bool emergency; // allow admin to withdraw all qubes + allow users to withdraw qubes bypassing lock

    uint32 currentEpochStartTime;
    uint32 currentEpochEndTime;
    uint32 currentVotingStartTime;
    uint32 currentVotingEndTime;
    uint128 currentVotingTotalVotes;

    uint32 MAX_VOTES_RATIO = 10000;
    uint32 gaugeMaxVotesRatio; // up to 10000 (100%). Gauge cant have more votes. All exceeded votes will be distributed among other gauges
    uint32 gaugeMinVotesRatio; // up to 10000 (100%). If gauge doesn't have min votes, it will not be elected in epoch
    uint8 gaugeMaxDowntime; // if gauge was not elected for N times in a row, it is deleted from whitelist

    mapping (address => bool) whitelistedGauges;
    mapping (address => uint128) currentVotingVotes;
    mapping (address => uint8) gaugeDowntime;

    // amount of QUBE tokens user should pay to add his gauge to QUBE dao
    uint128 gaugeWhitelistPrice;
    // amount of QUBEs available for withdraw as payments for whitelist
    uint128 whitelistPayments;

    uint32 constant QUBE_MIN_LOCK_TIME = 7 * 24 * 60 * 60; // 7 days
    uint32 constant QUBE_MAX_LOCK_TIME = 4 * 365 * 60 * 60; // 4 years
    enum DepositType { userDeposit, whitelist, adminDeposit }

    struct PendingDeposit {
        address user;
        uint128 amount;
        uint128 ve_amount;
        uint32 lock_time;
        address send_gas_to;
        uint32 nonce;
    }

    uint32 deposit_nonce;
    mapping (uint32 => PendingDeposit) pending_deposits;

//    uint128 constant MIN_DEPOSIT_VALUE = 1 ton; // adjust dynamically
//    uint128 constant TOKEN_WALLET_DEPLOY_VALUE = 0.5 ton;


constructor(address _owner, address _qube) public {
        require (tvm.pubkey() != 0, WRONG_PUBKEY);
        require (tvm.pubkey() == msg.pubkey(), WRONG_PUBKEY);
        tvm.accept();

        owner = _owner;
        qube = _qube;

        _setupTokenWallet();
    }

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

    modifier onlyOwner() {
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    // We have 3 cases on receiving qubes, each case is determined by deposit_type
    // @Case 1 - user make deposit
    // deposit_type - 0
    // deposit_owner - address on which behalf sender making deposit
    // whitelist_address - ignored
    // nonce - nonce, that will be sent with callback
    // lock_time - lock time for qubes
    // @Case 2 - user pay for whitelisting address
    // deposit_type - 1
    // deposit_owner - ignored
    // whitelist_address - address which will be whitelisted
    // nonce - nonce, that will be sent with callback
    // lock_time - ignored
    // @Case 3 - send qubes for further distribution
    // deposit_type - 2
    // deposit_owner - ignored
    // whitelist_address - ignored
    // nonce - nonce, that will be sent with callback
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
            TvmBuilder builder;
            if (nonce > 0) {
                builder.store(nonce);
            }
            bool notify = false;
            ITokenWallet(qubeWallet).transfer{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                amount,
                sender,
                0,
                remainingGasTo,
                true,
                builder.toCell()
            );
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
            remainingGasTo.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
        }
    }

    modifier onlyVoteEscrowAccount(address user) {
        address ve_account_addr = getVoteEscrowAccountAddress(user);
        require (msg.sender == ve_account_addr, NOT_VOTE_ESCROW_ACCOUNT);
        _;
    }

    function revertDeposit(address user, uint32 deposit_nonce) external onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);
        PendingDeposit deposit = pending_deposits[deposit_nonce];
        delete pending_deposits[deposit_nonce];

        // TODO: emit event
        TvmBuilder builder;
        bool notify = false;
        if (deposit.nonce > 0) {
            notify = true;
            builder.store(deposit.nonce);
        }
        ITokenWallet(qubeWallet).transfer{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            deposit.amount, deposit.user, 0, deposit.send_gas_to, notify, builder.toCell()
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

    function _addToWhitelist(address gauge) internal {
        whitelistedGauges[gauge] = true;
        // TODO: add event
    }

    function addToWhitelist(address gauge) external onlyOwner {
        _addToWhitelist(gauge);
    }

    function _removeFromWhitelist(address gauge) internal {
        whitelistedGauges[gauge] = false;
        // TODO: add event
    }

    function removeFromWhitelist(address gauge) external onlyOwner {
        _removeFromWhitelist(gauge);
    }

    function calculateVeMint(uint128 qube_amount, uint32 lock_time) public view returns (uint128 ve_amount) {
        // qube has 18 decimals, there should be no problems with division precision
        return math.muldiv(qube_amount, lock_time, QUBE_MAX_LOCK_TIME);
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



}
