import {expect} from "chai";
import {AccountType, deployUser, setupTokenRoot, setupVoteEscrow, sleep} from "../utils/common";
import {VoteEscrow} from "../utils/wrappers/vote_ecsrow";
import {VoteEscrowAccount} from "../utils/wrappers/ve_account";
import {Token} from "../utils/wrappers/token";
import {TokenWallet} from "../utils/wrappers/token_wallet";
import {setupGaugeFactory} from "../utils/common";
import {Contract, Address} from "locklift";
import {GaugeAbi, GaugeFactoryAbi} from "../../build/factorySource";
import {toNano} from "locklift/build/utils";
import {Gauge} from "../utils/wrappers/gauge";

var should = require('chai').should();
const {getRandomNonce} = locklift.utils;


describe("Gauge main scenario (no extra rewards, no vesting)", async function() {
    let user1: AccountType;
    let user2: AccountType;
    let owner: AccountType;

    // just simple wallets here
    let gauge_factory: Contract<GaugeFactoryAbi>
    let gauge: Gauge;

    let vote_escrow: VoteEscrow;

    let qube_root: Token;
    let deposit_root: Token;

    let user1_qube_wallet: TokenWallet;
    let user2_qube_wallet: TokenWallet;
    let owner_qube_wallet: TokenWallet;

    let user1_deposit_wallet: TokenWallet;
    let user2_deposit_wallet: TokenWallet;
    let owner_deposit_wallet: TokenWallet;

    describe('Setup contracts', async function () {
        it('Deploy users', async function () {
            user1 = await deployUser(20);
            user2 = await deployUser(20);
            owner = await deployUser(40);
        });

        it('Deploy tokens', async function () {
            qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
            deposit_root = await setupTokenRoot('TEST', 'TEST', owner);
        });

        it('Mint tokens', async function () {
            owner_qube_wallet = await qube_root.mint(1000000000, owner);
            user1_qube_wallet = await qube_root.mint(1000000000, user1);
            user2_qube_wallet = await qube_root.mint(1000000000, user2);

            owner_deposit_wallet = await deposit_root.mint(1000000000, owner);
            user1_deposit_wallet = await deposit_root.mint(1000000000, user1);
            user2_deposit_wallet = await deposit_root.mint(1000000000, user2);
        });

        it('Deploy Vote Escrow', async function () {
            vote_escrow = await setupVoteEscrow({
                owner, qube: qube_root
            });
        });

        it('Deploy Gauge Factory', async function() {
           gauge_factory = await setupGaugeFactory({
               _owner: owner, _qube: qube_root, _voteEscrow: vote_escrow, _qubeVestingRatio: 0, _qubeVestingPeriod: 0
           });
        });
    });

    describe('Running scenarios', async function() {
        describe('Testing simple deposits', async function() {
            const deposit_amount = 1000;

            beforeEach('Deploy gauge', async function() {
                await locklift.tracing.trace(owner.runTarget(
                    {
                        contract: gauge_factory,
                        value: toNano(5)
                    },
                    (gf) => gf.methods.deployGauge({
                        gauge_owner: owner.address,
                        depositTokenRoot: deposit_root.address,
                        maxBoost: 2000,
                        maxLockTime: 100,
                        rewardTokenRoots: [],
                        vestingPeriods: [],
                        vestingRatios: [],
                        withdrawAllLockPeriod: 0,
                        call_id: 1
                    })
                ));
                const event = (await gauge_factory.getPastEvents({filter: (event) => event.event === 'NewGauge'})).events[0].data;
                // @ts-ignore
                gauge = await Gauge.from_addr(event.gauge as Address, owner);
            })

           it('Simple deposit', async function() {
                await locklift.tracing.trace(
                    gauge.deposit(user1_deposit_wallet, deposit_amount, 0, false, 0),
                    {allowedCodes: {compute: [null]}}
                );

                const details = await gauge.getDetails();
                const token_details = await gauge.getTokenDetails();

                expect(details._lockBoostedSupply).to.be.eq(deposit_amount.toString());
                expect(details._totalBoostedSupply).to.be.eq(deposit_amount.toString());
                expect(token_details._depositTokenData.tokenBalance).to.be.eq(deposit_amount.toString());
           });

            it('Lock deposit', async function() {
                await locklift.tracing.trace(
                    gauge.deposit(user1_deposit_wallet, deposit_amount, 100, false, 0),
                    {allowedCodes: {compute: [null]}}
                );

                const details = await gauge.getDetails();
                const token_details = await gauge.getTokenDetails();

                expect(details._lockBoostedSupply).to.be.eq((deposit_amount * 2).toString());
                expect(details._totalBoostedSupply).to.be.eq((deposit_amount * 2).toString());
                expect(token_details._depositTokenData.tokenBalance).to.be.eq(deposit_amount.toString());
            });

            it('Ve boosted deposit', async function() {
                await locklift.tracing.trace(
                    vote_escrow.deposit(user1_qube_wallet, deposit_amount, 100, 0),
                    {allowedCodes: {compute: [null]}}
                );

                await locklift.tracing.trace(
                    gauge.deposit(user1_deposit_wallet, deposit_amount, 100, false, 0),
                    {allowedCodes: {compute: [null]}}
                );

                const details = await gauge.getDetails();
                const token_details = await gauge.getTokenDetails();

                // 2.5x boost + 2x boost
                expect(details._lockBoostedSupply).to.be.eq((deposit_amount * 2).toString());
                expect(details._totalBoostedSupply).to.be.eq((deposit_amount * 3.5).toString());
                expect(token_details._depositTokenData.tokenBalance).to.be.eq(deposit_amount.toString());
            });
        });
    });
});