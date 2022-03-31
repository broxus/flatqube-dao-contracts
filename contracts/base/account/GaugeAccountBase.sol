pragma ton-solidity ^0.57.1;

import "./GaugeAccountVesting.sol";
pragma AbiHeader expire;


contract GaugeAccountBase is GaugeAccountVesting {
    // should be called in onCodeUpgrade on platform initialization
    function _init(uint8 reward_tokens_count, uint32 _vestingPeriod, uint32 _vestingRatio) internal {
        require (farmPool == msg.sender, NOT_FARM_POOL);
        for (uint i = 0; i < reward_tokens_count; i++) {
            rewardDebt.push(0);
            entitled.push(0);
            pool_debt.push(0);
            vestingTime.push(0);
        }
        vestingPeriod = _vestingPeriod;
        vestingRatio = _vestingRatio;
    }

    function _reserve() internal pure returns (uint128) {
        return math.max(address(this).balance - msg.value, CONTRACT_MIN_BALANCE);
    }

        // TODO: up
    function getDetails() external responsible view override returns (GaugeAccountDetails) {
        return { value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS }GaugeAccountDetails(
            pool_debt, entitled, vestingTime, amount, rewardDebt, farmPool, user, current_version
        );
    }

    // user_amount and user_reward_debt should be fetched from GaugeAccount at first
    function pendingReward(
        uint256[] _accRewardPerShare,
        uint32 poolLastRewardTime,
        uint32 farmEndTime
    ) external view returns (uint128[] _entitled, uint128[] _vested, uint128[] _pool_debt, uint32[] _vesting_time) {
        (
        _entitled,
        _vested,
        _vesting_time
        ) = _computeVesting(amount, rewardDebt, _accRewardPerShare, poolLastRewardTime, farmEndTime);

        return (_entitled, _vested, pool_debt, _vesting_time);
    }

    function increasePoolDebt(uint128[] _pool_debt, address send_gas_to, uint32 code_version) external override {
        require(msg.sender == farmPool, NOT_FARM_POOL);
        tvm.rawReserve(_reserve(), 0);

        for (uint i = 0; i < _pool_debt.length; i++) {
            pool_debt[i] += _pool_debt[i];
        }

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function processDeposit(
        uint64 nonce,
        uint128 _amount,
        uint256 _qubRewardPerShare,
        uint256[] _accRewardPerShare,
        uint32 poolLastRewardTime,
        uint32[] farmEndTime,
        uint32 code_version
    ) external override {
        require(msg.sender == farmPool, NOT_FARM_POOL);
        tvm.rawReserve(_reserve(), 0);

        uint128 prevAmount = amount;
        uint128[] prevRewardDebt = rewardDebt;

        amount += _amount;
        for (uint i = 0; i < rewardDebt.length; i++) {
            uint256 _reward = amount * _accRewardPerShare[i];
            rewardDebt[i] = uint128(_reward / SCALING_FACTOR);
        }

        (
        uint128[] _entitled,
        uint128[] _vested,
        uint32[] _vestingTime
        ) = _computeVesting(prevAmount, prevRewardDebt, _accRewardPerShare, poolLastRewardTime, farmEndTime);
        entitled = _entitled;
        vestingTime = _vestingTime;
        lastRewardTime = poolLastRewardTime;

        for (uint i = 0; i < _vested.length; i++) {
            _vested[i] += pool_debt[i];
            pool_debt[i] = 0;
        }

        IGauge(msg.sender).finishDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(nonce, _vested);
    }

    function _withdraw(uint128 _amount, uint256[] _accRewardPerShare, uint32 poolLastRewardTime, uint32 farmEndTime, address send_gas_to, uint32 nonce) internal {
        // bad input. User does not have enough staked balance. At least we can return some gas
        if (_amount > amount) {
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

        uint128 prevAmount = amount;
        uint128[] prevRewardDebt = rewardDebt;

        amount -= _amount;
        for (uint i = 0; i < _accRewardPerShare.length; i++) {
            uint256 _reward = amount * _accRewardPerShare[i];
            rewardDebt[i] = uint128(_reward / SCALING_FACTOR);
        }

        (
        uint128[] _entitled,
        uint128[] _vested,
        uint32[] _vestingTime
        ) = _computeVesting(prevAmount, prevRewardDebt, _accRewardPerShare, poolLastRewardTime, farmEndTime);
        entitled = _entitled;
        vestingTime = _vestingTime;
        lastRewardTime = poolLastRewardTime;

        for (uint i = 0; i < _vested.length; i++) {
            _vested[i] += pool_debt[i];
            pool_debt[i] = 0;
        }

        IGauge(msg.sender).finishWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, _amount, _vested, send_gas_to, nonce);
    }

    function processWithdraw(
        uint128 _amount,
        uint256[] _accRewardPerShare,
        uint32 poolLastRewardTime,
        uint32 farmEndTime,
        address send_gas_to,
        uint32 nonce,
        uint32 code_version
    ) public override {
        require (msg.sender == farmPool, NOT_FARM_POOL);
        tvm.rawReserve(_reserve(), 0);

        _withdraw(_amount, _accRewardPerShare, poolLastRewardTime, farmEndTime, send_gas_to, nonce);
    }

    function processClaimReward(uint256[] _accRewardPerShare, uint32 poolLastRewardTime, uint32 farmEndTime, address send_gas_to, uint32 nonce, uint32 code_version) external override {
        require (msg.sender == farmPool, NOT_FARM_POOL);
        tvm.rawReserve(_reserve(), 0);

        _withdraw(0, _accRewardPerShare, poolLastRewardTime, farmEndTime, send_gas_to, nonce);
    }

    function processSafeWithdraw(address send_gas_to, uint32 code_version) external override {
        require (msg.sender == farmPool, NOT_FARM_POOL);
        tvm.rawReserve(_reserve(), 0);

        uint128 prevAmount = amount;
        amount = 0;
        for (uint i = 0; i < rewardDebt.length; i++) {
            rewardDebt[i] = 0;
        }
        IGauge(msg.sender).finishSafeWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, prevAmount, send_gas_to);
    }
}
