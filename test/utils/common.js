const logger = require("mocha-logger");
const {expect} = require("chai");
const BigNumber = require('bignumber.js');
const Token = require("./wrappers/token");
const VoteEscrow = require('./wrappers/vote_ecsrow');
const {Dimensions, zeroAddress, Address} = require("locklift");
const {getRandomNonce} = require("locklift/build/utils");
const {toNano} = locklift.utils;


async function sleep(ms) {
    ms = ms === undefined ? 1000 : ms;
    return new Promise(resolve => setTimeout(resolve, ms));
}


const checkTokenBalance = async function(token_wallet, expected_bal) {
    const balance = await token_wallet.balance();
    expect(balance.toFixed(0)).to.be.eq(expected_bal.toFixed(0));
}


// allow sending N internal messages via batch method
const runTargets = async function(wallet, targets, methods, params_list, values) {
    let bodies = await Promise.all(targets.map(async function(target, idx) {
        const method = methods[idx];
        const params = params_list[idx];
        return await target.methods[method](params).encodeInternal();
    }));

    return await locklift.tracing.trace(wallet.accountContract.methods.sendTransactions({
        dest: targets.map((contract) => contract.address.toString()),
        value: values,
        bounce: new Array(targets.length).fill(true),
        flags: new Array(targets.length).fill(0),
        payload: bodies,
    }).sendExternal({publicKey: wallet.publicKey}));
}


const deployUsers = async function(count, initial_balance) {
    let signers = await Promise.all([...Array(count).keys()].map(async (i) => await locklift.keystore.getSigner(i.toString())));
    signers = signers.slice(0, count);

    let signers_map = {};
    signers.map((signer) => {
        signers_map[`0x${signer.publicKey}`.toLowerCase()] = signer;
    })

    const TestWallet = await locklift.factory.getContractArtifacts('TestWallet');
    const {contract: factory, tx} = await locklift.factory.deployContract({
        contract: 'TestFactory',
        initParams: { wallet_code: TestWallet.code, _randomNonce: getRandomNonce() },
        publicKey: signers[0].publicKey,
        constructorParams: {},
        value: toNano(count * initial_balance + 5)
    });

    const pubkeys = signers.map((signer) => { return `0x${signer.publicKey}` });
    const values = Array(count).fill(toNano(initial_balance));

    const chunkSize = 60;
    for (let i = 0; i < count; i += chunkSize) {
        const _pubkeys = pubkeys.slice(i, i + chunkSize);
        const _values = values.slice(i, i + chunkSize);
        console.log(i, chunkSize)
        await locklift.tracing.trace(factory.methods.deployUsers({pubkeys: _pubkeys, values: _values}).sendExternal({publicKey: signers[0].publicKey}));
    }

    // await sleep(1000);
    const {wallets} = await factory.methods.wallets({}).call();
    const wallets_map = wallets.reduce((map, elem) => {
        const pubkey = elem[0];
        map[signers_map[pubkey].publicKey] = elem[1];
        return map;
    }, {});

    let accountsFactory = locklift.factory.getAccountsFactory('TestWallet');
    return await Promise.all(Object.entries(wallets_map).map(async function([pubkey, addr]) {
        return accountsFactory.getAccount(addr, pubkey);
    }));
}


const deployUser = async function(initial_balance=100) {
    const signer = await locklift.keystore.getSigner('0');
    let accountsFactory = locklift.factory.getAccountsFactory('TestWallet');

    const {account: _user, tx} = await locklift.tracing.trace(accountsFactory.deployNewAccount({
        publicKey: signer.publicKey,
        value: locklift.utils.toNano(initial_balance).toString(),
        initParams: {
            _randomNonce: locklift.utils.getRandomNonce(),
        },
        constructorParams: {
            owner_pubkey: `0x${signer.publicKey}`
        },
    }));

    const userBalance = await locklift.provider.getBalance(_user.address);
    expect(Number(userBalance)).to.be.above(0, 'Bad user balance');

    logger.log(`User address: ${_user.address.toString()}`);
    return _user;
}


const setupTokenRoot = async function(token_name, token_symbol, owner) {
    const signer = await locklift.keystore.getSigner('0');

    const TokenWallet = await locklift.factory.getContractArtifacts('TokenWallet');
    const {contract: _root, tx} = await locklift.tracing.trace(locklift.factory.deployContract({
        contract: 'TokenRoot',
        initParams: {
            name_: token_name,
            symbol_: token_symbol,
            decimals_: 9,
            rootOwner_: owner.address,
            walletCode_: TokenWallet.code,
            randomNonce_: locklift.utils.getRandomNonce(),
            deployer_: zeroAddress
        },
        publicKey: signer.publicKey,
        constructorParams: {
            initialSupplyTo: zeroAddress,
            initialSupply: 0,
            deployWalletValue: 0,
            mintDisabled: false,
            burnByRootDisabled: false,
            burnPaused: false,
            remainingGasTo: owner.address
        },
        value: locklift.utils.toNano(2)
    }));

    logger.log(`Token root address: ${_root.address.toString()}`);

    expect(Number(await locklift.provider.getBalance(_root.address))).to.be.above(0, 'Root balance empty');
    return new Token(_root, owner);
}


const setupVoteEscrow = async function({
    owner,
    qube,
    dao=zeroAddress,
    start_time=null,
    min_lock=1,
    max_lock=100,
    distribution_scheme=[8000, 1000, 1000],
    distribution=[1000000, 1000000, 1000000, 1000000, 1000000, 1000000],
    epoch_time=10,
    time_before_voting=4,
    voting_time=5,
    gauge_min_votes_ratio=200,
    gauge_max_votes_ratio=3000,
    gauge_max_downtime=2,
    max_gauges_per_vote=15,
    whitelist_price=1000000
}) {
    const VoteEscrowContract = await locklift.factory.getContractArtifacts('VoteEscrow');
    const Platform = await locklift.factory.getContractArtifacts('Platform');
    const VoteEscrowAccount = await locklift.factory.getContractArtifacts('VoteEscrowAccount');

    const signer = await locklift.keystore.getSigner('0');
    const {contract: deployer, tx} = await locklift.factory.deployContract({
        contract: 'VoteEscrowDeployer',
        initParams: {
            _randomNonce: locklift.utils.getRandomNonce(),
            PlatformCode: Platform.code,
            veAccountCode: VoteEscrowAccount.code,
        },
        publicKey: signer.publicKey,
        constructorParams: {},
        value: locklift.utils.toNano(20),
    });

    logger.log(`Deployed Vote Escrow deployer`);
    await locklift.tracing.trace(deployer.methods.installVoteEscrowCode({code: VoteEscrowContract.code}).sendExternal({publicKey: signer.publicKey}));

    if (start_time === null) {
        start_time = Math.floor(Date.now() / 1000 + 5);
    }
    logger.log(`Set Vote Escrow code`);
    const tx2 = await locklift.tracing.trace(deployer.methods.deployVoteEscrow({
        owner: owner.address,
        qube: qube.address,
        dao,
        start_time,
        min_lock,
        max_lock,
        distribution_scheme,
        distribution,
        epoch_time,
        time_before_voting,
        voting_time,
        gauge_min_votes_ratio,
        gauge_max_votes_ratio,
        gauge_max_downtime,
        max_gauges_per_vote,
        whitelist_price
    }).sendExternal({publicKey: signer.publicKey}));

    const ve_addr = tx2.output._vote_escrow;
    const ve = await VoteEscrow.from_addr(ve_addr, owner);
    logger.log(`Deployed and configured Vote Escrow: ${ve_addr.toString()}`);

    await ve.acceptOwnership(owner);
    logger.log(`Accepted ownership`);

    return ve;
}


module.exports = {
    setupTokenRoot,
    setupVoteEscrow,
    deployUser,
    deployUsers,
    runTargets,
    sleep,
    checkTokenBalance
}