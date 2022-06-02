const logger = require("mocha-logger");
const {expect} = require("chai");
const Token = require("./wrappers/token");
const VoteEscrow = require('./wrappers/vote_ecsrow');
const {
    convertCrystal
} = locklift.utils;


const deployUser = async function(initial_balance=100) {
    const [keyPair] = await locklift.keys.getKeyPairs();
    const Account = await locklift.factory.getAccount('Wallet');
    const _user = await locklift.giver.deployContract({
        contract: Account,
        constructorParams: {},
        initParams: {
            _randomNonce: locklift.utils.getRandomNonce()
        },
        keyPair,
    }, convertCrystal(initial_balance, 'nano'));
    _user.setKeyPair(keyPair);

    const userBalance = await locklift.ton.getBalance(_user.address);
    expect(userBalance.toNumber()).to.be.above(0, 'Bad user balance');

    logger.log(`User address: ${_user.address}`);
    return _user;
}


const setupTokenRoot = async function(token_name, token_symbol, owner) {
    const RootToken = await locklift.factory.getContract(
        'TokenRoot',
        'node_modules/broxus-ton-tokens-contracts/build'
    );

    const TokenWallet = await locklift.factory.getContract(
        'TokenWallet',
        'node_modules/broxus-ton-tokens-contracts/build'
    );

    const [keyPair] = await locklift.keys.getKeyPairs();

    const _root = await locklift.giver.deployContract({
        contract: RootToken,
        constructorParams: {
            initialSupplyTo: locklift.utils.zeroAddress,
            initialSupply: 0,
            deployWalletValue: 0,
            mintDisabled: false,
            burnByRootDisabled: false,
            burnPaused: false,
            remainingGasTo: owner.address
        },
        initParams: {
            name_: token_name,
            symbol_: token_symbol,
            decimals_: 9,
            rootOwner_: owner.address,
            walletCode_: TokenWallet.code,
            randomNonce_: locklift.utils.getRandomNonce(),
            deployer_: locklift.utils.zeroAddress
        },
        keyPair,
    });
    _root.setKeyPair(keyPair);

    logger.log(`Token root address: ${_root.address}`);

    expect((await locklift.ton.getBalance(_root.address)).toNumber()).to.be.above(0, 'Root balance empty');
    return new Token(_root, owner);
}


const setupVoteEscrow = async function(
    owner,
    qube,
    start_time=null,
    min_lock=1,
    max_lock=100,
    distribution_scheme=[8000, 1000, 1000],
    distribution=[1000000, 1000000, 1000000, 1000000, 1000000, 1000000],
    epoch_time=10,
    time_before_voting=4,
    voting_time=5,
    gauge_min_votes_ratio=200,
    gauge_max_votes_ratio=5000,
    gauge_max_downtime=2,
    max_gauges_per_vote=10,
    whitelist_price=1000000
) {
    const VoteEscrowContract = await locklift.factory.getContract('VoteEscrow');
    const [keyPair] = await locklift.keys.getKeyPairs();

    const ve_contract = await locklift.giver.deployContract({
        contract: VoteEscrowContract,
        constructorParams: {
            _owner: owner.address,
            _qube: qube.address
        },
        initParams: {
            deploy_nonce: locklift.utils.getRandomNonce()
        },
        keyPair
    });
    logger.log(`Vote Escrow address: ${ve_contract.address}`);
    const ve = new VoteEscrow(ve_contract, owner);

    const VeAccount = await locklift.factory.getContract('VoteEscrowAccount');
    await ve.installPlatformCode();
    logger.log(`Installed platform code`);

    await ve.installOrUpdateVeAccountCode(VeAccount.code);
    logger.log(`Installed ve account code`);

    await ve.setVotingParams(
        epoch_time,
        time_before_voting,
        voting_time,
        gauge_min_votes_ratio,
        gauge_max_votes_ratio,
        gauge_max_downtime,
        max_gauges_per_vote
    );
    logger.log('Set voting params');

    await ve.setDistributionScheme(distribution_scheme);
    logger.log('Set distribution scheme');

    await ve.setDistribution(distribution);
    logger.log('Set distribution');

    await ve.setQubeLockTimeLimits(min_lock, max_lock);
    logger.log('Set qube lock time limits');

    await ve.setWhitelistPrice(whitelist_price);
    logger.log(`Set whitelist price`);

    if (start_time === null) {
        start_time = Math.floor(Date.now() / 1000 + 5);
    }
    await ve.initialize(start_time);
    logger.log('Initialized');

    return ve;
}


module.exports = {
    setupTokenRoot,
    setupVoteEscrow,
    deployUser
}