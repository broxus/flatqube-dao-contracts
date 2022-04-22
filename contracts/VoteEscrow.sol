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

    uint128 treasuryTokens;
    uint128 teamTokens;

    uint32 constant DISTRIBUTION_SCHEME_TOTAL = 10000;
    // should have 3 elems. 0 - farming, 1 - treasury, 2 - team
    uint32[] distributionScheme;

    uint128 qubeBalance;
    uint128 veQubeSupply;
    uint32 lastUpdateTime;

    uint128 distributionSupply; // current balance of tokens reserved for distribution
    // Array of distribution amount for all epochs
    // We store only half of all numbers, because distribution function is symmetric
    uint128[] distribution;

    uint128 veQubeAverage;
    uint32 veQubeAveragePeriod;

    uint32 epochTime; // length of epoch in seconds
    uint32 votingTime; // length of voting in seconds
    uint32 timeBeforeVoting; // time after epoch start when next voting will take place

    bool initialized; // require origin epoch to be created
    bool paused; // pause contract in case of some error or update, disable user actions
    bool emergency; // allow admin to withdraw all qubes + allow users to withdraw qubes bypassing lock

    uint32 currentEpoch;
    uint32 currentEpochStartTime;
    uint32 currentEpochEndTime;
    uint32 currentVotingStartTime;
    uint32 currentVotingEndTime;
    uint128 currentVotingTotalVotes;

    uint32 constant MAX_VOTES_RATIO = 10000;
    uint32 gaugeMaxVotesRatio; // up to 10000 (100%). Gauge cant have more votes. All exceeded votes will be distributed among other gauges
    uint32 gaugeMinVotesRatio; // up to 10000 (100%). If gauge doesn't have min votes, it will not be elected in epoch
    uint8 gaugeMaxDowntime; // if gauge was not elected for N times in a row, it is deleted from whitelist

    uint32 maxGaugesPerVote = 10; // max number of gauges user can vote for
    uint32 gaugesNum;
    mapping (address => bool) whitelistedGauges;
    mapping (address => uint128) currentVotingVotes;
    mapping (address => uint8) gaugeDowntime;

    // amount of QUBE tokens user should pay to add his gauge to QUBE dao
    uint128 gaugeWhitelistPrice;
    // amount of QUBEs available for withdraw as payments for whitelist
    uint128 whitelistPayments;

    // TODO: make editable
    uint32 constant QUBE_MIN_LOCK_TIME = 7 * 24 * 60 * 60; // 7 days
    uint32 constant QUBE_MAX_LOCK_TIME = 4 * 365 * 60 * 60; // 4 years
    enum DepositType { userDeposit, whitelist, adminDeposit }

    uint128 constant SCALING_FACTOR = 10**18;

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


    // TODO: up
    constructor(address _owner, address _qube, uint32 _distribution_interval) public {
        require (tvm.pubkey() != 0, WRONG_PUBKEY);
        require (tvm.pubkey() == msg.pubkey(), WRONG_PUBKEY);
        tvm.accept();

        owner = _owner;
        qube = _qube;

        // 2 years
        distributionInterval = _distribution_interval;

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

    function _makeCell(uint32 nonce) internal {
        TvmBuilder builder;
        if (nonce > 0) {
            builder.store(nonce);
        }
        return builder.toCell();
    }

    // TODO: add value
    function _transferTokens(
        address token_wallet, uint128 amount, address receiver, TvmCell payload, address send_gas_to, uint16 flag
    ) internal {
        uint128 value;
        if (flag != MsgFlag.ALL_NOT_RESERVED) {
            value = TOKEN_TRANSFER_VALUE;
        }
        bool notify = false;
        // notify = true if payload is non-empty
        if (payload.bits() > 0) {
            notify = true;
        }
        ITokenWallet(qubeWallet).transfer{value: value, flag: flag}(
            amount,
            receiver,
            0,
            send_gas_to,
            notify,
            payload
        );
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

    modifier onlyVoteEscrowAccount(address user) {
        address ve_account_addr = getVoteEscrowAccountAddress(user);
        require (msg.sender == ve_account_addr, NOT_VOTE_ESCROW_ACCOUNT);
        _;
    }

    modifier onlyActive() {
        require (!paused && !emergency || msg.sender == owner, Errors.NOT_ACTIVE);
        _;
    }

    modifier onlyEmergency() {
        require (emergency, Errors.NOT_EMERGENCY);
        _;
    }

    function setDistributionScheme(uint32[] _new_scheme, address send_gas_to) external onlyOwner {
        require (_new_scheme.length == 3, Errors.BAD_INPUT);
        require (_new_scheme[0] + _new_scheme[1] + _new_scheme[2] == DISTRIBUTION_SCHEME_TOTAL, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);

        distributionScheme = _new_scheme;

        // TODO: emit event
        send_gas_to.send(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function setDistribution(uint128[] _new_distribution, address send_gas_to) external onlyOwner {
        // only symmetric
        require (_new_distribution.length / 2 == 0, Errors.BAD_INPUT);
        tvm.rawReserve(_reserve(), 0);

        distribution = _new_distribution;
        // TODO: emit event

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
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

    function initialize(address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        require (distribution.length > 0, Errors.CANT_BE_INITIALIZED);
        require (distributionScheme.length > 0, Errors.CANT_BE_INITIALIZED);
        require (!initialized, Errors.ALREADY_INITIALIZED);

        tvm.rawReserve(_reserve(), 0);
        initializationTime = now;
        currentEpochStartTime = now;
        currentEpochEndTime = now + epochTime;
        currentEpoch = 1;
        initialized = true;

        // TODO: emit event
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function startVoting(address send_gas_to) external onlyActive {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        require (initialized, Errors.NOT_INITIALIZED);

        currentEpoch + 1 == distribution.length - 1;
        require (currentEpoch + 1 < distribution.length * 2, Errors.LAST_EPOCH);

        require (now >= currentEpochStartTime + timeBeforeVoting, Errors.TOO_EARLY_FOR_VOTING);
        require (currentVotingStartTime == 0, Errors.VOTING_ALREADY_STARTED);

        tvm.rawReserve(_reserve(), 0);

        currentVotingStartTime = now;
        currentEpochEndTime = now + votingTime;
        // TODO: emit event

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    // Function for voting with ve qubes user has
    // @param votes - mapping with user votes. Key - gauge address, value - number of ve tokens
    // @param nonce - nonce for callback, ignored if == 0
    // @param send_gas_to - address to send unspent gas
    function vote(mapping (address => uint128) votes, uint32 nonce, address send_gas_to) external onlyActive {
        // minimum check for gas dependant on gauges count
        // TODO: dont need dynamic here, gauges num is limited
        require (msg.value >= Gas.MIN_MSG_VALUE + maxGaugesPerVote * Gas.PER_GAUGE_VOTE_VALUE, Errors.LOW_MSG_VALUE);
        require (currentVotingStartTime > 0, Errors.VOTING_NOT_STARTED);
        require (now <= currentEpochEndTime, Errors.VOTING_ENDED);

        uint32 counter = 0;
//        for ((address gauge,) : votes) {
//            require (whitelistedGauges[gauge], Errors.GAUGE_NOT_WHITELISTED);
//            counter += 1;
//        }
        require (counter <= maxGaugesPerVote, Errors.MAX_GAUGES_PER_VOTE);

        tvm.rawReserve(_reserve(), 0);

        address ve_acc_addr = getVoteEscrowAccountAddress(msg.sender);
        IVoteEscrowAccount(ve_acc_addr).processVote{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            currentEpoch, votes, nonce, send_gas_to
        );
    }

    function finishVote(
        address user, mapping (address => uint128) votes, uint32 nonce, address send_gas_to
    ) external onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        // this is possible if vote(...) was called right before voting end and data race happen
        if (currentVotingStartTime == 0 || now > currentVotingEndTime) {
            // TODO: emit event
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

//        for ((address gauge, uint128 vote_value) : votes) {
//            currentVotingVotes[gauge] += vote_value;
//            currentVotingTotalVotes += vote_value;
//        }

        // TODO: emit event
        // TODO send callback

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function endVoting(address send_gas_to) external {
        require (msg.value >= Gas.MIN_MSG_VALUE + Gas.MSG_VALUE_PER_GAUGE * gaugesNum, Errors.LOW_MSG_VALUE);
        require (currentVotingStartTime != 0, Errors.VOTING_NOT_STARTED);
        require (now > currentVotingEndTime, Errors.VOTING_NOT_ENDED);

        uint128 min_votes = currentVotingTotalVotes * gaugeMinVotesRatio / MAX_VOTES_RATIO;
        uint128 max_votes = currentVotingTotalVotes * gaugeMaxVotesRatio / MAX_VOTES_RATIO;
        uint128 exceeded_votes = 0;
        uint128 valid_votes = 0;
        // get rid of "bad" gauges that dint reach vote threshold
        // + rearrange votes of too "big" gauges
        for ((address gauge, uint128 gauge_votes) : currentVotingVotes) {
            if (gauge_votes < min_votes) {
                exceeded_votes += gauge_votes;
                delete currentVotingVotes[gauge];
                gaugeDowntime[gauge] += 1;
                if (gaugeDowntime[gauge] >= gaugeMaxDowntime) {
                    _removeFromWhitelist(gauge);
                }
            } else if (gauge_votes > max_votes) {
                currentVotingVotes[gauge] = max_votes;
                exceeded_votes += gauge_votes - max_votes;
            } else {
                valid_votes += gauge_votes;
            }
        }

        uint128 treasury_votes = 0;
//        if (exceeded_votes > 0) {
//            for ((address gauge, uint128 gauge_votes) : currentVotingVotes) {
//                if (gauge_votes < max_votes) {
//                    uint128 bonus_votes = math.muldiv(gauge_votes, exceeded_votes, valid_votes);
//                    gauge_votes += bonus_votes;
//                    if (gauge_votes > max_votes) {
//                        treasury_votes += gauge_votes - max_votes;
//                        currentVotingVotes[gauge] = max_votes;
//                    }
//                }
//            }
//        }

        currentVotingEndTime = 0;
        currentVotingStartTime = 0;
        currentEpoch += 1;
        // if voting ended too late, start epoch now
        currentEpochStartTime = currentEpochEndTime < now ? now : currentEpochEndTime;
        currentVotingEndTime = currentEpochStartTime + epochTime;

        tvm.rawReserve(_reserve(), 0);

        // TODO: emit event
        IVoteEscrow(address(this)).distributeEpochQubes{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            treasury_votes, send_gas_to
        );
    }

    // We distribute qubes in separate message to be able to spend more gas
    function distributeEpochQubes(
        uint128 bonus_treasury_votes, address send_gas_to
    ) external {
        require (msg.sender == address(this), Errors.NOT_OWNER);
        tvm.rawReserve(_reserve(), 0);

        // we start distributing qubes from 2 epoch
        uint256 epoch_idx = currentEpoch - 2;
        uint128 to_distribute_total;
        if (epoch_idx >= distribution.length) {
            uint256 offset = epoch_idx - (distribution.length - 1);
            to_distribute_total = distribution[epoch_idx - offset];
        } else {
            to_distribute_total = distribution[epoch_idx];
        }
        uint128 to_distribute_farming = math.muldiv(to_distribute_total, distributionScheme[0], DISTRIBUTION_SCHEME_TOTAL);
        uint128 to_distribute_treasury = math.muldiv(to_distribute_total, distributionScheme[1], DISTRIBUTION_SCHEME_TOTAL);
        uint128 to_distribute_team = math.muldiv(to_distribute_total, distributionScheme[2], DISTRIBUTION_SCHEME_TOTAL);

        uint128 treasury_bonus = math.muldiv(to_distribute_farming, bonus_treasury_votes, currentVotingTotalVotes);
        to_distribute_treasury += treasury_bonus;
        to_distribute_farming -= treasury_bonus;

        treasuryTokens += to_distribute_treasury;
        teamTokens += to_distribute_team;

        TvmBuilder builder;
        builder.store(epochTime);
        TvmCell payload = builder.toCell();
        for ((address gauge, uint128 gauge_votes): currentVotingVotes) {
            uint128 qube_amount = math.muldiv(to_distribute_farming, gauge_votes, currentVotingTotalVotes);
            _transferTokens(qubeWallet, qube_amount, gauge, payload, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
        }

        currentVotingTotalVotes = 0;
        delete currentVotingVotes;

        // TODO: emit event
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdrawTreasuryTokens(uint128 amount, address receiver, address send_gas_to) external onlyOwner {
        require (amount <= treasuryTokens, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);

        treasuryTokens -= amount;
        // TODO: emit event

        TvmCell empty;
        _transferTokens(qubeWallet, amount, receiver, empty, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
    }

    function withdrawTeamTokens(uint128 amount, address receiver, address send_gas_to) external onlyOwner {
        require (amount <= teamTokens, Errors.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);

        teamTokens -= amount;
        // TODO: emit event

        TvmCell empty;
        _transferTokens(qubeWallet, amount, receiver, empty, send_gas_to, MsgFlag.SENDER_PAYS_FEES);
    }


    function burnVeQubes(address user, uint128 expiredVeQubes) external onlyVoteEscrowAccount(user) {
        updateAverage();
        veQubeSupply -= expiredVeQubes;
    }

    function _addToWhitelist(address gauge) internal {
        gaugesNum += 1;
        whitelistedGauges[gauge] = true;
        // TODO: add event
    }

    function addToWhitelist(address gauge) external onlyOwner {
        _addToWhitelist(gauge);
    }

    function _removeFromWhitelist(address gauge) internal {
        gaugesNum -= 1;
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

    function getVoteEscrowAccountAddress(address user) public view responsible returns (address) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } address(
            tvm.hash(_buildInitData(_buildVoteEscrowAccountParams(user)))
        );
    }

    function _buildVoteEscrowAccountParams(address user) internal view returns (TvmCell) {
        TvmBuilder builder;
        builder.store(user);
        return builder.toCell();
    }

    function _buildInitData(TvmCell _initialData) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Platform,
            varInit: {
                root: address(this),
                platformType: PlatformTypes.VoteEscrowAccount,
                initialData: _initialData,
                platformCode: platformCode
            },
            pubkey: 0,
            code: platformCode
        });
    }


    function deployVoteEscrowAccount(address user) internal returns (address) {
        TvmBuilder constructor_params;

        constructor_params.store(ve_account_version); // 32
        constructor_params.store(ve_account_version); // 32

        return new Platform{
            stateInit: _buildInitData(_buildVoteEscrowAccountParams(user)),
            value: Gas.VE_ACCOUNT_DEPLOY_VALUE
        }(veAccountCode, constructor_params.toCell(), user);
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
