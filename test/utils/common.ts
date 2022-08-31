import {Token} from "./wrappers/token";
import {VoteEscrow} from "./wrappers/vote_ecsrow";
import {VoteEscrowAccount} from "./wrappers/ve_account";
import {FactorySource, GaugeFactoryAbi} from "../../build/factorySource";
import {Address, Contract, zeroAddress, getRandomNonce, toNano, WalletTypes} from "locklift";
import {Gauge} from "./wrappers/gauge";
import {Account} from "everscale-standalone-client/nodejs";
const logger = require("mocha-logger");
const {expect} = require("chai");


export async function sleep(ms = 1000) {
    return new Promise(resolve => setTimeout(resolve, ms));
}


export async function tryIncreaseTime(seconds: number) {
    // @ts-ignore
    if (locklift.testing.isEnabled) {
        await locklift.testing.increaseTime(seconds);
    } else {
        await sleep(seconds * 1000);
    }
}


export const sendAllEvers = async function(from: Account, to: Address) {
    const walletContract = await locklift.factory.getDeployedContract("TestWallet", from.address);
    return await locklift.tracing.trace(walletContract.methods.sendTransaction({
        dest: to,
        value: 0,
        bounce: false,
        flags: 128,
        payload: '',
        // @ts-ignore
    }).sendExternal({publicKey: from.publicKey}));
}


// allow sending N internal messages via batch method
export const runTargets = async function (
    wallet: Account,
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

    const walletContract = await locklift.factory.getDeployedContract("TestWallet", wallet.address);

    return await locklift.tracing.trace(walletContract.methods.sendTransactions({
        dest: targets.map((contract) => contract.address),
        value: values,
        bounce: new Array(targets.length).fill(true),
        flags: new Array(targets.length).fill(0),
        payload: bodies,
    // @ts-ignore
    }).sendExternal({publicKey: wallet.publicKey}));
}


export const deployUsers = async function (count: number, initial_balance: number) {
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
        value: toNano(count * initial_balance + 10)
    });

    const pubkeys = signers.map((signer) => {
        return `0x${signer?.publicKey}`
    });
    const values = Array(count).fill(toNano(initial_balance));

    const chunkSize = 60;
    for (let i = 0; i < count; i += chunkSize) {
        const _pubkeys = pubkeys.slice(i, i + chunkSize);
        const _values = values.slice(i, i + chunkSize);
        await locklift.tracing.trace(factory.methods.deployUsers({
            pubkeys: _pubkeys,
            values: _values
        }).sendExternal({publicKey: signers[0]?.publicKey as string}));
    }

    // await sleep(1000);
    const {wallets} = await factory.methods.wallets({}).call();
    return await Promise.all(wallets.map(async (wallet) => {
        return await locklift.factory.accounts.addExistingAccount({
            publicKey: wallet[0].slice(2),
            type: WalletTypes.Custom,
            address: wallet[1],
        });
    }));
}


export const deployUser = async function (initial_balance = 100): Promise<Account> {
    const signer = await locklift.keystore.getSigner('0');

    const {account: _user, tx} = await locklift.factory.accounts.addNewAccount({
        type: WalletTypes.Custom,
        contract: "TestWallet",
        //Value which will send to the new account from a giver
        value: toNano(initial_balance),
        publicKey: signer?.publicKey as string,
        initParams: {
            _randomNonce: getRandomNonce()
        },
        constructorParams: {
            owner_pubkey: `0x${signer?.publicKey}`
        }
    });

    logger.log(`User address: ${_user.address.toString()}`);
    return _user;
}


export const setupTokenRoot = async function (token_name: string, token_symbol: string, owner: Account) {
    const signer = await locklift.keystore.getSigner('0');
    const TokenPlatform = await locklift.factory.getContractArtifacts('TokenWalletPlatform');

    const TokenWallet = await locklift.factory.getContractArtifacts('TokenWalletUpgradeable');
    const {contract: _root, tx} = await locklift.tracing.trace(locklift.factory.deployContract({
        contract: 'TokenRootUpgradeable',
        initParams: {
            name_: token_name,
            symbol_: token_symbol,
            decimals_: 9,
            rootOwner_: owner.address,
            walletCode_: TokenWallet.code,
            randomNonce_: locklift.utils.getRandomNonce(),
            deployer_: zeroAddress,
            platformCode_: TokenPlatform.code
        },
        publicKey: signer?.publicKey as string,
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


export const setupGaugeFactory = async function({
    _owner,
    _qube,
    _voteEscrow,
    _qubeVestingRatio=0,
    _qubeVestingPeriod=0
}: {_owner: Account, _qube: Token, _voteEscrow: VoteEscrow, _qubeVestingRatio: number, _qubeVestingPeriod: number}
): Promise<Contract<FactorySource["GaugeFactory"]>> {
    const Gauge = await locklift.factory.getContractArtifacts('Gauge');
    const GaugeAccount = await locklift.factory.getContractArtifacts('GaugeAccount');
    const Platform = await locklift.factory.getContractArtifacts('Platform');

    const signer = await locklift.keystore.getSigner('0');
    const {contract: factory, tx} = await locklift.factory.deployContract({
        contract: 'GaugeFactory',
        initParams: {
            nonce: getRandomNonce(),
            PlatformCode: Platform.code
        },
        publicKey: signer?.publicKey as string,
        constructorParams: {
            _owner: _owner.address,
            _qube: _qube.address,
            _vote_escrow: _voteEscrow.address,
            _qube_vesting_period: _qubeVestingPeriod,
            _qube_vesting_ratio: _qubeVestingRatio
        },
        value: locklift.utils.toNano(5),
    });
    logger.log(`Deployed gauge factory: ${factory.address}`);

    await locklift.tracing.trace(factory.methods.installNewGaugeCode({
        gauge_code: Gauge.code, meta: {call_id: 0, nonce: 0, send_gas_to: _owner.address}
    }).send({
        amount: toNano(2),
        from: _owner.address
    }));
    logger.log('Installed gauge code');

    await locklift.tracing.trace(factory.methods.installNewGaugeAccountCode({
        gauge_account_code: GaugeAccount.code, meta: {call_id: 0, nonce: 0, send_gas_to: _owner.address}
    }).send({
        amount: toNano(2),
        from: _owner.address
    }));
    logger.log('Installed gauge account code');
    return factory;
}


export const setupGauge = async function ({
    owner,
    gauge_factory,
    deposit_root,
    max_lock_time=100,
    reward_roots=[],
    vesting_periods=[],
    vesting_ratios=[],
    withdraw_lock_period=0,
    qube_vesting_ratio=0,
    qube_vesting_period=0,
    call_id=0
}: {
    owner: Account,
    gauge_factory: Contract<GaugeFactoryAbi>,
    deposit_root: Token,
    reward_roots: Token[],
    max_lock_time: number,
    vesting_periods: number[],
    vesting_ratios: number[],
    withdraw_lock_period: number,
    qube_vesting_ratio: number,
    qube_vesting_period: number,
    call_id: number
}): Promise<Gauge> {
    // @ts-ignore
    await locklift.tracing.trace(gauge_factory.methods.deployGaugeByOwner({
        gauge_owner: owner.address,
        depositTokenRoot: deposit_root.address,
        maxBoost: 2000,
        maxLockTime: max_lock_time,
        rewardTokenRoots: reward_roots.map(i => i.address),
        vestingPeriods: vesting_periods,
        vestingRatios: vesting_ratios,
        withdrawAllLockPeriod: withdraw_lock_period,
        qubeVestingPeriod: qube_vesting_period,
        qubeVestingRatio: qube_vesting_ratio,
        call_id: call_id
    }).send({
        // @ts-ignore
        amount: toNano(8),
        from: owner.address
    }));

    const event = (await gauge_factory.getPastEvents({
        filter: (event) => event.event === 'NewGauge' && event.data.call_id === call_id.toString()
    })).events[0].data;
    // @ts-ignore
    return await Gauge.from_addr(event.gauge as Address, owner);
}


export const setupVoteEscrow = async function ({
    // @ts-ignore
    owner,
    // @ts-ignore
    qube,
    dao = zeroAddress,
    start_offset = 5,
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
    const VoteEscrowContract = await locklift.factory.getContractArtifacts('TestVoteEscrow');
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
        value: locklift.utils.toNano(6.5),
    });

    logger.log(`Deployed Test Vote Escrow deployer`);
    await locklift.tracing.trace(deployer.methods.installVoteEscrowCode({code: VoteEscrowContract.code}).sendExternal({publicKey: signer?.publicKey as string}));

    logger.log(`Set Test Vote Escrow code`);
    const tx2 = await locklift.tracing.trace(deployer.methods.deployTestVoteEscrow({
        owner: owner.address,
        qube: qube.address,
        dao,
        start_offset,
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
    }).sendExternal({publicKey: signer?.publicKey as string}));

    const ve_addr = tx2?.output?._vote_escrow;
    const ve = await VoteEscrow.from_addr(ve_addr as Address, owner);
    logger.log(`Deployed and configured Vote Escrow: ${ve_addr?.toString()}`);

    await ve.acceptOwnership(owner);
    logger.log(`Accepted ownership`);

    return ve;
}
