pragma ton-solidity ^0.58.2;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "./interfaces/IFactory.sol";
import './interfaces/IGauge.sol';
import "./Gauge.sol";
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


contract GaugeFactory is IFactory {
    event NewGauge(
        address gauge,
        address gauge_owner,
        address tokenRoot,
        IGauge.RewardRound[] extraRewardRounds,
        address[] rewardTokenRoot,
        uint32 qubeVestingPeriod,
        uint32 qubeVestingRatio,
        uint32[] vestingPeriod,
        uint32[] vestingRatio,
        uint32 withdrawAllLockPeriod
    );

    event GaugeCodeUpdated(uint32 prev_version, uint32 new_version);
    event GaugeAccountCodeUpdated(uint32 prev_version, uint32 new_version);
    event FactoryUpdated(uint32 prev_version, uint32 new_version);
    event NewOwner(address prev_owner, address new_owner);
    event NewPendingOwner(address pending_owner);

    uint32 public factory_version;
    uint32 public gauge_version;
    uint32 public gauge_account_version;

    uint64 public gauges_count = 0;
    address public owner;
    address public pending_owner;

    address public QUBE;

    TvmCell public static GaugeAccountCode;
    TvmCell public static GaugeCode;
    TvmCell public static PlatformCode;
//
//    // factory deployment seed
    uint128 public static nonce;

    uint8 constant WRONG_PUBKEY = 1001;
    uint8 constant NOT_OWNER = 1002;
    uint8 constant NOT_GAUGE = 1003;
    uint8 constant LOW_MSG_VALUE = 1004;
    uint8 constant BAD_GAUGE_CONFIG = 1005;
    uint128 constant GAUGE_DEPLOY_VALUE = 5 ton;
    uint128 constant GAUGE_UPGRADE_VALUE = 1 ton;
    uint128 constant CONTRACT_MIN_BALANCE = 1 ton;

    constructor(address _owner, address _qube) public {
        require (tvm.pubkey() != 0, WRONG_PUBKEY);
        require (tvm.pubkey() == msg.pubkey(), WRONG_PUBKEY);
        tvm.accept();

        owner = _owner;
        QUBE = _qube;
    }


    modifier onlyOwner() {
        require(msg.sender == owner, NOT_OWNER);
        _;
    }

    function _reserve() internal pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }

    function transferOwnership(address new_owner, address send_gas_to) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        emit NewPendingOwner(new_owner);
        pending_owner = new_owner;
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function acceptOwnership(address send_gas_to) external {
        require (msg.sender == pending_owner, NOT_OWNER);
        tvm.rawReserve(_reserve(), 0);

        emit NewOwner(owner, pending_owner);
        owner = pending_owner;
        pending_owner = address.makeAddrNone();
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function installNewGaugeCode(TvmCell gauge_code, address send_gas_to) external onlyOwner {
        require (msg.value >= GAUGE_UPGRADE_VALUE, LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        GaugeCode = gauge_code;
        gauge_version++;
        emit GaugeCodeUpdated(gauge_version - 1, gauge_version);
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function installNewGaugeAccountCode(TvmCell gauge_account_code, address send_gas_to) external onlyOwner {
        require (msg.value >= GAUGE_UPGRADE_VALUE, LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        GaugeAccountCode = gauge_account_code;
        gauge_account_version++;
        emit GaugeAccountCodeUpdated(gauge_account_version - 1, gauge_account_version);
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function upgradeGauges(address[] gauges, address send_gas_to) external onlyOwner {
        require (msg.value >= GAUGE_UPGRADE_VALUE * (gauges.length + 1), LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        for (uint i = 0; i < gauges.length; i++) {
            IGauge(gauges[i]).upgrade{value: GAUGE_UPGRADE_VALUE, flag: MsgFlag.SENDER_PAYS_FEES}(
                GaugeCode, gauge_version, send_gas_to
            );
        }
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function updateGaugesAccountCode(address[] gauges, address send_gas_to) external onlyOwner {
        require (msg.value >= GAUGE_UPGRADE_VALUE * (gauges.length + 1), LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        for (uint i = 0; i < gauges.length; i++) {
            IGauge(gauges[i]).updateGaugeAccountCode{value: GAUGE_UPGRADE_VALUE, flag: MsgFlag.SENDER_PAYS_FEES}(
                GaugeAccountCode, gauge_account_version, send_gas_to
            );
        }
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function forceUpgradeGaugeAccount(address gauge, address user, address send_gas_to) external onlyOwner {
        require (msg.value >= GAUGE_UPGRADE_VALUE, LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IGauge(gauge).forceUpgradeGaugeAccount{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, send_gas_to);
    }

    function processUpgradeGaugeRequest(address send_gas_to) external override {
        require (msg.value >= GAUGE_UPGRADE_VALUE, LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IGauge(msg.sender).upgrade{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            GaugeCode, gauge_version, send_gas_to
        );
    }

    function processUpdateGaugeAccountCodeRequest(address send_gas_to) external override {
        require (msg.value >= GAUGE_UPGRADE_VALUE, LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        IGauge(msg.sender).updateGaugeAccountCode{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            GaugeAccountCode, gauge_account_version, send_gas_to
        );
    }

    function deployGauge(
        address gauge_owner,
        address depositTokenRoot,
        uint32 qubeVestingPeriod,
        uint32 qubeVestingRatio,
        IGauge.RewardRound[] extraRewardRounds
        address[] rewardTokenRoot,
        uint32[] vestingPeriod,
        uint32[] vestingRatio,
        uint32 withdrawAllLockPeriod
    ) external onlyOwner {
        tvm.rawReserve(_reserve(), 0);
        require (msg.value >= GAUGE_DEPLOY_VALUE, LOW_MSG_VALUE);
        require (rewardTokenRoot.length >= 1, BAD_GAUGE_CONFIG);
        // qube should always be part of reward
        require (rewardTokenRoot[0] == QUBE, BAD_GAUGE_CONFIG);

        TvmCell stateInit = tvm.buildStateInit({
            contr: Gauge,
            varInit: {
                gaugeAccountCode: GaugeAccountCode,
                platformCode: PlatformCode,
                deploy_nonce: gauges_count,
                factory: address(this),
                gauge_account_version: gauge_account_version,
                gauge_version: gauge_version
            },
            pubkey: tvm.pubkey(),
            code: GaugeCode
        });
        gauges_count += 1;

        address gauge = new Gauge{
            stateInit: stateInit,
            value: 0,
            wid: address(this).wid,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(
            gauge_owner, QUBE, depositTokenRoot,
            extraRewardRounds, rewardTokenRoot, qubeVestingPeriod,
            qubeVestingRatio, vestingPeriod, vestingRatio, withdrawAllLockPeriod
        );
    }

    function onGaugeDeploy(
        uint64 gauge_deploy_nonce,
        address gauge_owner,
        address depositTokenRoot,
        IGauge.RewardRound[] extraRewardRounds
        address[] rewardTokenRoot,
        uint32 qubeVestingPeriod,
        uint32 qubeVestingRatio,
        uint32[] vestingPeriod,
        uint32[] vestingRatio,
        uint32 withdrawAllLockPeriod
    ) external override {
        TvmCell stateInit = tvm.buildStateInit({
            contr: Gauge,
            varInit: {
                gaugeAccountCode: GaugeAccountCode,
                platformCode: PlatformCode,
                deploy_nonce: gauge_deploy_nonce,
                factory: address(this),
                gauge_account_version: gauge_account_version,
                gauge_version: gauge_version
            },
            pubkey: tvm.pubkey(),
            code: GaugeCode
        });
        address gauge_address = address(tvm.hash(stateInit));
        require (msg.sender == gauge_address, NOT_GAUGE);

        tvm.rawReserve(_reserve(), 0);

        emit NewGauge(
            gauge_address, gauge_owner, depositTokenRoot,
            extraRewardRounds, rewardTokenRoot, qubeVestingPeriod,
            qubeVestingRatio, vestingPeriod, vestingRatio, withdrawAllLockPeriod
        );
    }

    function upgrade(TvmCell new_code, address send_gas_to) public onlyOwner {
        require (msg.value >= GAUGE_UPGRADE_VALUE, LOW_MSG_VALUE);

        TvmCell data = abi.encode(
            owner,
            pending_owner,
            gauges_count,
            nonce,
            gauge_version,
            gauge_account_version,
            factory_version,
            GaugeAccountCode,
            GaugeCode,
            PlatformCode
        );

        tvm.setcode(new_code);
        tvm.setCurrentCode(new_code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell data) internal {}
}