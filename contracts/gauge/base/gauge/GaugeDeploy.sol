pragma ever-solidity ^0.62.0;


import "./GaugeUpgradable.sol";


abstract contract GaugeDeploy is GaugeUpgradable {
    function setupTokens(
        address _depositTokenRoot,
        address _qubeTokenRoot,
        address[] _extraRewardTokenRoot
    ) external onlyFactory override {
        // qube is reserved as a main reward!
        require (_depositTokenRoot != _qubeTokenRoot, Errors.BAD_DEPOSIT_TOKEN);
        for (uint i = 0; i < _extraRewardTokenRoot.length; i++) {
            require (_extraRewardTokenRoot[i] != _qubeTokenRoot, Errors.BAD_REWARD_TOKENS_INPUT);
        }

        depositTokenData.tokenRoot = _depositTokenRoot;
        qubeTokenData.tokenRoot = _qubeTokenRoot;
        extraRewardEnded = new bool[](_extraRewardTokenRoot.length);
        extraRewardRounds = new RewardRound[][](_extraRewardTokenRoot.length);
        for (uint i = 0; i < _extraRewardTokenRoot.length; i++) {
            extraTokenData.push(TokenData(_extraRewardTokenRoot[i], address.makeAddrNone(), 0));
        }

        _setUpTokenWallets();
    }

    function setupVesting(
        uint32 _qubeVestingPeriod,
        uint32 _qubeVestingRatio,
        uint32[] _extraVestingPeriods,
        uint32[] _extraVestingRatios,
        uint32 _withdrawAllLockPeriod,
        uint32 call_id
    ) external onlyFactory override {
        // all arrays should have the same dimension
        require (
            extraTokenData.length == _extraVestingPeriods.length &&
            _extraVestingPeriods.length == _extraVestingRatios.length,
            Errors.BAD_INPUT
        );
        // vesting params check
        require (_qubeVestingRatio <= 1000, Errors.BAD_VESTING_SETUP);
        require ((_qubeVestingPeriod == 0 && _qubeVestingRatio == 0) || (_qubeVestingPeriod > 0 && _qubeVestingRatio > 0), Errors.BAD_VESTING_SETUP);
        for (uint i = 0; i < _extraVestingPeriods.length; i++) {
            require (_extraVestingRatios[i] <= 1000, Errors.BAD_VESTING_SETUP);
            require (
                (_extraVestingPeriods[i] == 0 && _extraVestingRatios[i] == 0) ||
                (_extraVestingPeriods[i] > 0 && _extraVestingRatios[i] > 0),
                Errors.BAD_VESTING_SETUP
            );
        }

        qubeVestingPeriod = _qubeVestingPeriod;
        qubeVestingRatio = _qubeVestingRatio;
        extraVestingPeriods = _extraVestingPeriods;
        extraVestingRatios = _extraVestingRatios;
        withdrawAllLockPeriod = _withdrawAllLockPeriod;

        IGaugeFactory(factory).onGaugeDeploy{value: 0, flag: MsgFlag.REMAINING_GAS }(deploy_nonce, call_id);
    }

    /*
        @notice Creates token wallet for configured root token, initialize arrays and send callback to factory
    */
    function _setUpTokenWallets() internal view {
        // Deploy vault's token wallet
        ITokenRoot(depositTokenData.tokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: IGauge.receiveTokenWalletAddress }(
            address(this), // owner
            Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
        );

        // deploy qube wallet
        ITokenRoot(qubeTokenData.tokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: IGauge.receiveTokenWalletAddress }(
            address(this), // owner
            Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
        );

        for (uint i = 0; i < extraTokenData.length; i++) {
            ITokenRoot(extraTokenData[i].tokenRoot).deployWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE, callback: IGauge.receiveTokenWalletAddress}(
                address(this), // owner address
                Gas.TOKEN_WALLET_DEPLOY_VALUE / 2 // deploy grams
            );
        }
    }

    /*
        @notice Store vault's token wallet address
        @dev Only root can call with correct params
        @param wallet Gauge's token wallet
    */
    function receiveTokenWalletAddress(address wallet) external override {
        tvm.rawReserve(_reserve(), 0);

        if (msg.sender == depositTokenData.tokenRoot) {
            depositTokenData.tokenWallet = wallet;
        } else if (msg.sender == qubeTokenData.tokenRoot) {
            qubeTokenData.tokenWallet = wallet;
        } else {
            for (uint i = 0; i < extraTokenData.length; i++) {
                if (msg.sender == extraTokenData[i].tokenRoot) {
                    extraTokenData[i].tokenWallet = wallet;
                }
            }
        }
    }
}
