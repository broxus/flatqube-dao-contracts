import {TokenWallet} from "./wrappers/token_wallet";
import {Token} from "./wrappers/token";
import {VoteEscrow} from "./wrappers/vote_ecsrow";
import {VoteEscrowAccount} from "./wrappers/ve_account";
import {Account} from "locklift/build/factory";
import {FactorySource} from "../../build/factorySource";
import {Address, Contract, zeroAddress} from "locklift";

const logger = require("mocha-logger");
const {expect} = require("chai");

const {getRandomNonce} = require("locklift/build/utils");
const {toNano} = locklift.utils;


declare type AccountType = Account<FactorySource["TestWallet"]>;


async function sleep(ms = 1000) {
    return new Promise(resolve => setTimeout(resolve, ms));
}


// allow sending N internal messages via batch method
const runTargets = async function (
    wallet: AccountType,
    targets: Contract<any>[],
    methods: string[],
    params_list: Object[],
    values: any[]
) {
    let bodies = await Promise.all(targets.map(async function (target, idx) {
        const method = methods[idx];
        const params = params_list[idx];
        // @ts-ignore
        return await target.methods[method](params).encodeInternal();
    }));

    return await locklift.tracing.trace(wallet.accountContract.methods.sendTransactions({
        dest: targets.map((contract) => contract.address),
        value: values,
        bounce: new Array(targets.length).fill(true),
        flags: new Array(targets.length).fill(0),
        payload: bodies,
    }).sendExternal({publicKey: wallet.publicKey}));
}


const deployUsers = async function (count: number, initial_balance: number) {
    // @ts-ignore
    let signers = await Promise.all([...Array(count).keys()].map(async (i) => await locklift.keystore.getSigner(i.toString())));
    signers = signers.slice(0, count);

    let signers_map = {};
    signers.map((signer) => {
        // @ts-ignore
        signers_map[`0x${signer.publicKey}`.toLowerCase()] = signer;
    })

    const TestWallet = await locklift.factory.getContractArtifacts('TestWallet');
    const {contract: factory, tx} = await locklift.factory.deployContract({
        contract: 'TestFactory',
        initParams: {wallet_code: TestWallet.code, _randomNonce: getRandomNonce()},
        publicKey: signers[0]?.publicKey as string,
        constructorParams: {},
        value: toNano(count * initial_balance + 5)
    });

    const pubkeys = signers.map((signer) => {
        return `0x${signer?.publicKey}`
    });
    const values = Array(count).fill(toNano(initial_balance));

    const chunkSize = 60;
    for (let i = 0; i < count; i += chunkSize) {
        const _pubkeys = pubkeys.slice(i, i + chunkSize);
        const _values = values.slice(i, i + chunkSize);
        console.log(i, chunkSize)
        await locklift.tracing.trace(factory.methods.deployUsers({
            pubkeys: _pubkeys,
            values: _values
        }).sendExternal({publicKey: signers[0]?.publicKey as string}));
    }

    // await sleep(1000);
    const {wallets} = await factory.methods.wallets({}).call();
    const wallets_map: { [id: string]: Address } = wallets.reduce((map, elem) => {
        const pubkey = elem[0];
        // @ts-ignore
        map[signers_map[pubkey].publicKey] = elem[1];
        return map;
    }, {});

    let accountsFactory = locklift.factory.getAccountsFactory('TestWallet');
    return await Promise.all(Object.entries(wallets_map).map(async function ([pubkey, addr]) {
        return accountsFactory.getAccount(addr, pubkey);
    }));
}


const deployUser = async function (initial_balance = 100) {
    const signer = await locklift.keystore.getSigner('0');
    let accountsFactory = locklift.factory.getAccountsFactory('TestWallet');

    const {account: _user, tx} = await locklift.tracing.trace(accountsFactory.deployNewAccount({
        publicKey: signer?.publicKey as string,
        value: locklift.utils.toNano(initial_balance).toString(),
        initParams: {
            _randomNonce: locklift.utils.getRandomNonce(),
        },
        constructorParams: {
            owner_pubkey: `0x${signer?.publicKey}`
        },
    }));

    const userBalance = await locklift.provider.getBalance(_user.address);
    expect(Number(userBalance)).to.be.above(0, 'Bad user balance');

    logger.log(`User address: ${_user.address.toString()}`);
    return _user;
}


const setupTokenRoot = async function (token_name: string, token_symbol: string, owner: AccountType) {
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
            deployer_: new Address(zeroAddress)
        },
        publicKey: signer?.publicKey as string,
        constructorParams: {
            initialSupplyTo: new Address(zeroAddress),
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


const setupVoteEscrow = async function ({
        // @ts-ignore
        owner,
        // @ts-ignore
        qube,
        dao = new Address(zeroAddress),
        start_time = Math.floor(Date.now() / 1000 + 5),
        min_lock = 1,
        max_lock = 100,
        distribution_scheme = [8000, 1000, 1000],
        distribution = [1000000, 1000000, 1000000, 1000000, 1000000, 1000000],
        epoch_time = 10,
        time_before_voting = 4,
        voting_time = 5,
        gauge_min_votes_ratio = 200,
        gauge_max_votes_ratio = 3000,
        gauge_max_downtime = 2,
        max_gauges_per_vote = 15,
        whitelist_price = 1000000
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
        publicKey: signer?.publicKey as string,
        constructorParams: {},
        value: locklift.utils.toNano(20),
    });

    logger.log(`Deployed Vote Escrow deployer`);
    await locklift.tracing.trace(deployer.methods.installVoteEscrowCode({code: VoteEscrowContract.code}).sendExternal({publicKey: signer?.publicKey as string}));

    logger.log(`Set Vote Escrow code`);
    const tx2 = await deployer.methods.deployVoteEscrow({
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
    }).sendExternal({publicKey: signer?.publicKey as string});

    const ve_addr = tx2?.output?._vote_escrow;
    const ve = await VoteEscrow.from_addr(ve_addr as Address, owner);
    logger.log(`Deployed and configured Vote Escrow: ${ve_addr?.toString()}`);

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
    sleep
}