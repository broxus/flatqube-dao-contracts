const logger = require("mocha-logger");
const {expect} = require("chai");
const BigNumber = require('bignumber.js');
const Token = require("./wrappers/token");
const VoteEscrow = require('./wrappers/vote_ecsrow');
const {
    convertCrystal
} = locklift.utils;


async function sleep(ms) {
    ms = ms === undefined ? 1000 : ms;
    return new Promise(resolve => setTimeout(resolve, ms));
}


const checkTokenBalance = async function(token_wallet, expected_bal) {
    const balance = await token_wallet.balance();
    expect(balance.toFixed(0)).to.be.eq(expected_bal.toFixed(0));
}


// allow sending N internal messages via batch method
const runTargets = async function(wallet, targets, methods, params_list, values, allowed_codes) {
    let bodies = await Promise.all(targets.map(async function(target, idx) {
        const method = methods[idx];
        const params = params_list[idx];

        const message = await locklift.ton.client.abi.encode_message_body({
            address: target.address,
            abi: {
                type: "Contract",
                value: target.abi,
            },
            call_set: {
                function_name: method,
                input: params,
            },
            signer: {
                type: 'None',
            },
            is_internal: true,
        });

        return message.body;
    }));

    return wallet.run({
        method: 'sendTransactions',
        params: {
            dest: targets.map((contract) => contract.address),
            value: values,
            bounce: new Array(targets.length).fill(true),
            flags: new Array(targets.length).fill(0),
            payload: bodies,
        },
        tracing_allowed_codes: allowed_codes
    });
}


const deployUsers = async function(count, initial_balance) {
    let keys = await locklift.keys.getKeyPairs();
    keys = keys.slice(0, count);

    let keys_map = {};
    keys.map((pair) => {
        keys_map[`0x${pair.public}`] = pair;
    })

    const TestWallet = await locklift.factory.getAccount('TestWallet');
    const TestFactory = await locklift.factory.getAccount('TestFactory');

    const factory = await locklift.giver.deployContract({
        contract: TestFactory,
        constructorParams: {},
        initParams: {
            wallet_code: TestWallet.code
        }
    }, convertCrystal(count * initial_balance + 100, 'nano'));

    const pubkeys = keys.map((pair) => { return (new BigNumber(pair.public, 16)).toFixed(0) });
    const values = Array(count).fill(convertCrystal(initial_balance, 'nano'))

    const chunkSize = 60;
    for (let i = 0; i < count; i += chunkSize) {
        const _pubkeys = pubkeys.slice(i, i + chunkSize);
        const _values = values.slice(i, i + chunkSize);

        await factory.run({
            method: 'deployUsers',
            params: {
                pubkeys: _pubkeys,
                values: _values
            }
        });
    }

    const wallets = await factory.call({method: 'wallets'});
    return await Promise.all(Object.entries(wallets).map(async function([pubkey, addr]) {
        const pair = keys_map[pubkey];
        const wallet = await locklift.factory.getAccount('TestWallet');
        wallet.setAddress(addr);
        wallet.setKeyPair(pair);
        return wallet;
    }));
}


const deployUser = async function(initial_balance=100) {
    const [keyPair] = await locklift.keys.getKeyPairs();
    const Account = await locklift.factory.getAccount('TestWallet');
    const _user = await locklift.giver.deployContract({
        contract: Account,
        constructorParams: {
            owner_pubkey: (new BigNumber(keyPair.public, 16)).toFixed(0)
        },
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


const setupVoteEscrow = async function({
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
    gauge_max_votes_ratio=3000,
    gauge_max_downtime=2,
    max_gauges_per_vote=15,
    whitelist_price=1000000
}) {
    const VoteEscrowContract = await locklift.factory.getContract('VoteEscrow');
    const VoteEscrowDeployer = await locklift.factory.getContract('VoteEscrowDeployer');
    const Platform = await locklift.factory.getContract('Platform');
    const VoteEscrowAccount = await locklift.factory.getContract('VoteEscrowAccount');

    const [keyPair] = await locklift.keys.getKeyPairs();

    const deployer = await locklift.giver.deployContract({
        contract: VoteEscrowDeployer,
        constructorParams: {},
        initParams: {
            PlatformCode: Platform.code,
            veAccountCode: VoteEscrowAccount.code
        },
        keyPair
    }, convertCrystal(25, 'nano'));
    deployer.setKeyPair(keyPair);
    logger.log(`Deployed Vote Escrow deployer`);
    await deployer.run({
        method: 'installVoteEscrowCode',
        params: {
            code: VoteEscrowContract.code
        }
    });
    if (start_time === null) {
        start_time = Math.floor(Date.now() / 1000 + 5);
    }
    logger.log(`Set Vote Escrow code`);
    const tx = await deployer.run({
       method: 'deployVoteEscrow',
       params: {
           owner: owner.address,
           qube: qube.address,
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
       }
    });

    const ve_addr = tx.decoded.output._vote_escrow;
    const ve = await VoteEscrow.from_addr(ve_addr, owner);
    logger.log(`Deployed and configured Vote Escrow: ${ve_addr}`);

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