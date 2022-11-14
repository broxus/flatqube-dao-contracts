import {expect} from "chai";
import {
    deployUser,
    runTargets,
    setupGauge,
    setupGaugeFactory,
    setupTokenRoot,
    setupVoteEscrow,
    tryIncreaseTime
} from "../utils/common";
import {VoteEscrow} from "../utils/wrappers/vote_ecsrow";
import {Token} from "../utils/wrappers/token";
import {TokenWallet} from "../utils/wrappers/token_wallet";
import {Contract, getRandomNonce, toNano} from "locklift";
import {GaugeFactoryAbi} from "../../build/factorySource";
import {Gauge} from "../utils/wrappers/gauge";
import {Account} from 'locklift/everscale-client';

const logger = require('mocha-logger');

var should = require('chai').should();


describe("Gauge main scenarios", async function() {
    let user: Account;
    let owner: Account;

    // just simple wallets here
    let gauge_factory: Contract<GaugeFactoryAbi>
    let gauge: Gauge;

    let vote_escrow: VoteEscrow;

    let qube_root: Token;
    let deposit_root: Token;
    let reward_root: Token;

    const count = 250;
    const packs_num = 10;

    let owner_qube_wallet: TokenWallet;

    let owner_reward_wallet: TokenWallet;

    let user_deposit_wallet: TokenWallet;
    let owner_deposit_wallet: TokenWallet;

    describe('Setup contracts', async function () {
        it('Deploy users', async function () {
            user = await deployUser(100000000);
            owner = await deployUser(100000000);
        });

        it('Deploy tokens', async function () {
            qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
            deposit_root = await setupTokenRoot('TEST', 'TEST', owner);
        });

        it('Mint tokens', async function () {
            user_deposit_wallet = await deposit_root.mint(1000000000, user);
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
        const deposit_amount = 1000;

        it('Deploy gauge', async function() {
            gauge = await setupGauge({
                owner,
                gauge_factory,
                deposit_root,
                max_lock_time: 1000,
                reward_roots: [],
                vesting_periods: [],
                vesting_ratios: [],
                withdraw_lock_period: 0,
                qube_vesting_ratio: 0,
                qube_vesting_period: 0,
                call_id: getRandomNonce()
            });
        });

        it(`Made ${count * packs_num} deposits`, async function() {
            // processing requires some time, so we must be sure it will not unlock until all deposits are processed
            const lock_time = 1000;
            logger.log(`Locking for ${lock_time} seconds`);

            const deposit_payload = await gauge.depositPayload(user.address, lock_time, false, 0);
            const params = {
                amount: deposit_amount,
                recipient: gauge.address,
                deployWalletValue: 0,
                remainingGasTo: user.address,
                notify: true,
                payload: deposit_payload
            };

            let time_passed = 0;
            const acc = await gauge.gaugeAccount(user.address);

            // await locklift.tracing.trace(gauge.deposit(user_deposit_wallet, deposit_amount, 1000, false, 1), {allowedCodes: {compute: [null]}});

            for (const i of Array.from(Array(packs_num).keys())) {
                logger.log(`Sending pack #${i + 1} with ${count} deposits`)
                const from = Date.now();
                await locklift.tracing.trace(runTargets(
                    user,
                    Array(count).fill(user_deposit_wallet.contract),
                    Array(count).fill('transfer'),
                    Array(count).fill(params),
                    Array(count).fill(toNano(100))
                ), {allowedCodes: {contracts: {[acc.address.toString()]: {compute: [null]}}}});
                const to = Date.now();
                logger.log(`Pack processed in ${Math.floor((to - from) / 1000)}`);
                time_passed += Math.floor((to - from) / 1000);

                const acc_details = await acc.methods.calculateLockBalanceAverage({}).call();
                const details = await acc.methods.getDetails({answerId: 0}).call();

                console.log(details);
                console.log(acc_details);
            }

            logger.log(`${time_passed} seconds passed overall`);

            let bal_expected = deposit_amount * count * packs_num;

            const acc_details = await acc.methods.calculateLockBalanceAverage({}).call();

            expect(acc_details._balance).to.be.eq(bal_expected.toString());
            expect(acc_details._lockBoostedBalance).to.be.eq((bal_expected * 2).toString());
        });

        it('Making 1 more deposit, unlocking old ones', async function() {
            logger.log(`Sleeping until all deposits are unlocked...`)
            await tryIncreaseTime(1000);

            await locklift.tracing.trace(gauge.deposit(user_deposit_wallet, deposit_amount, 0, false, 0));

            const acc = await gauge.gaugeAccount(user.address);
            const detail = await acc.methods.getDetails({answerId: 0}).call();

            let bal_expected = deposit_amount * count * packs_num;

            expect(detail._balance).to.be.eq(bal_expected.toString());
            expect(detail._lockedBalance).to.be.eq('0');
        })

        it('Making withdraw', async function() {
            let withdraw_amount = deposit_amount * count * packs_num;
            await locklift.tracing.trace(gauge.withdraw(user, withdraw_amount, false, 2));

            const event = await vote_escrow.getEvent('Withdraw') as any;

            expect(event.call_id).to.be.eq('2');
            expect(event.amount).to.be.eq(withdraw_amount.toString());

            const acc = await gauge.gaugeAccount(user.address);
            const detail = await acc.methods.getDetails({answerId: 0}).call();

            expect(detail._balance).to.be.eq('0');
            expect(detail._lockedBalance).to.be.eq('0');
        });
    });
});
