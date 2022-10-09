import {VoteEscrow} from "../utils/wrappers/vote_ecsrow";
import {Account} from 'locklift/everscale-standalone-client';
import {Token} from "../utils/wrappers/token";
import {Gauge} from "../utils/wrappers/gauge";
import {Contract, getRandomNonce, toNano, zeroAddress} from "locklift";
import {GaugeFactoryAbi} from "../../build/factorySource";
import {setupGauge, setupGaugeFactory, setupVoteEscrow} from "../utils/common";
import {TokenWallet} from "../utils/wrappers/token_wallet";

const { expect } = require('chai');
const { setupTokenRoot, deployUser, deployUsers } = require("../utils/common");


describe("Upgrade gauge scenarios", async function() {
    this.timeout(3000000);

    let user1: Account;
    let user2: Account;
    let user3: Account;

    let owner: Account;

    let vote_escrow: VoteEscrow;

    let gauge_factory: Contract<GaugeFactoryAbi>;
    let gauge: Gauge;
    let deposit_token: Token;
    let qube_root: Token;

    let user1_deposit_wallet: TokenWallet;
    let user2_deposit_wallet: TokenWallet;
    let user3_deposit_wallet: TokenWallet;

    let owner_qube_wallet: TokenWallet;

    describe('Setup contracts', async function() {
        it('Deploy users', async function() {
            [user1, user2, user3] = await deployUsers(3, 20);
            owner = await deployUser(35);
        });

        it('Deploy token', async function() {
            deposit_token = await setupTokenRoot('TEST', 'TEST', owner);
            qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
        });

        it('Deploy token wallets + mint', async function() {
            owner_qube_wallet = await qube_root.mint(1000000000, owner);

            user1_deposit_wallet = await deposit_token.mint(1000000, user1);
            user2_deposit_wallet = await deposit_token.mint(1000000, user2);
            user3_deposit_wallet = await deposit_token.mint(1000000, user3);
        });

        it('Deploy Vote Escrow', async function () {
            vote_escrow = await setupVoteEscrow({
                owner, qube: qube_root
            });
        });

        it('Deploy gauge factory', async function() {
            gauge_factory = await setupGaugeFactory({
                _owner: owner, _qube: qube_root, _voteEscrow: vote_escrow, _qubeVestingRatio:0, _qubeVestingPeriod:0
            });
        });
    });

    describe('Testing upgrade logic', async function() {
        const deposit_amount = 1000;

        it('Deploy gauge', async function() {
           gauge = gauge = await setupGauge({
               owner,
               gauge_factory,
               deposit_root: deposit_token,
               max_lock_time: 100,
               reward_roots: [],
               vesting_periods: [],
               vesting_ratios: [],
               withdraw_lock_period: 0,
               qube_vesting_ratio: 0,
               qube_vesting_period: 0,
               call_id: getRandomNonce()
           });
        });

        it('Deploy gauge accounts for users', async function() {
            const acc1 = await gauge.gaugeAccount(user1.address);
            await locklift.tracing.trace(
                gauge.deposit(user1_deposit_wallet, deposit_amount, 0, false, 0),
                {
                    allowedCodes: {
                        contracts: {[acc1.address.toString()]: {compute: [null]}}
                    }
                }
            );
            const event = await gauge.getEvent('GaugeAccountDeploy');
            expect(event.user.toString()).to.be.eq(user1.address.toString());

            const acc2 = await gauge.gaugeAccount(user2.address);
            await locklift.tracing.trace(
                gauge.deposit(user2_deposit_wallet, deposit_amount, 0, false, 0),
                {
                    allowedCodes: {
                        contracts: {[acc2.address.toString()]: {compute: [null]}}
                    }
                }
            );
            const event2 = await gauge.getEvent('GaugeAccountDeploy');
            expect(event2.user.toString()).to.be.eq(user2.address.toString());
        });

        it('Upgrade Gauge Factory', async function() {
           const codes = await gauge_factory.methods.getCodes().call();
           expect(codes._factory_version).to.be.eq('0');

           const new_code = await locklift.factory.getContractArtifacts('GaugeFactory');

           await locklift.tracing.trace(gauge_factory.methods.upgrade(
               {new_code: new_code.code, meta: {call_id: 0, nonce: 1, send_gas_to: owner.address}}
           ).send({from: owner.address, amount: toNano(10)}));
        });

        it('Install new gauge/account codes to factory', async function() {
            const codes = await gauge_factory.methods.getCodes().call();
            expect(codes._gauge_version).to.be.eq('1');
            expect(codes._gauge_account_version).to.be.eq('1');

            const new_gauge_code = await locklift.factory.getContractArtifacts('TestGauge');
            const new_acc_code = await locklift.factory.getContractArtifacts('TestGaugeAccount');

            await locklift.tracing.trace(gauge_factory.methods.installNewGaugeCode({
                gauge_code: new_gauge_code.code, meta: {call_id: 0, nonce: 0, send_gas_to: owner.address}
            }).send({from: owner.address, amount: toNano(2)}));

            await locklift.tracing.trace(gauge_factory.methods.installNewGaugeAccountCode({
                gauge_account_code: new_acc_code.code, meta: {call_id: 0, nonce: 0, send_gas_to: owner.address}
            }).send({from: owner.address, amount: toNano(2)}));

            const codes_new = await gauge_factory.methods.getCodes().call();
            expect(codes_new._gauge_version).to.be.eq('2');
            expect(codes_new._gauge_account_version).to.be.eq('2');
        });

        it('Admin upgrade pool', async function() {
            await locklift.tracing.trace(gauge_factory.methods.upgradeGauges(
               {gauges: [gauge.address], meta: {call_id: 0, nonce: 1, send_gas_to: owner.address}}
               ).send({from: owner.address, amount: toNano(3)})
            );

            gauge.contract = await locklift.factory.getDeployedContract('TestGauge', gauge.address);
            const event = await gauge.getEvent('Upgrade');

            expect(event.new_version).to.be.eq('2');
            expect(event.old_version).to.be.eq('1');
        });

        it('Pool owner request gauge upgrade', async function() {
            const new_gauge_code = await locklift.factory.getContractArtifacts('TestGauge');

            // 1st install new code so that gauge could be upgraded
            await locklift.tracing.trace(gauge_factory.methods.installNewGaugeCode({
                gauge_code: new_gauge_code.code, meta: {call_id: 0, nonce: 1, send_gas_to: owner.address}
            }).send({from: owner.address, amount: toNano(2)}));

            const codes_new = await gauge_factory.methods.getCodes().call();
            expect(codes_new._gauge_version).to.be.eq('3');

            await locklift.tracing.trace(gauge.contract.methods.requestUpgradeGauge({
                meta: {call_id: 0, nonce: 0, send_gas_to: owner.address}
            }).send({from: owner.address, amount: toNano(3)}));

            const event = await gauge.getEvent('Upgrade');

            expect(event.new_version).to.be.eq('3');
            expect(event.old_version).to.be.eq('2');
        });

        it('Admin updated account code in gauge', async function() {
           await locklift.tracing.trace(gauge_factory.methods.updateGaugeAccountsCode({
               gauges: [gauge.address], meta: {call_id: 0, nonce: 0, send_gas_to: owner.address}
           }).send({from: owner.address, amount: toNano(3)}));

            const event = await gauge.getEvent('GaugeAccountCodeUpdated');
            expect(event.new_version).to.be.eq('2');
        });

        it('Pool owner request account code update', async function() {
            const new_gauge_code = await locklift.factory.getContractArtifacts('TestGaugeAccount');

            // 1st install new code so that gauge could be upgraded
            await locklift.tracing.trace(gauge_factory.methods.installNewGaugeAccountCode({
            gauge_account_code: new_gauge_code.code, meta: {call_id: 0, nonce: 0, send_gas_to: owner.address}
            }).send({from: owner.address, amount: toNano(2)}));

            const codes_new = await gauge_factory.methods.getCodes().call();
            expect(codes_new._gauge_account_version).to.be.eq('3');

            await locklift.tracing.trace(gauge.contract.methods.requestUpdateGaugeAccountCode({
                meta: {call_id: 0, nonce: 0, send_gas_to: owner.address}
            }).send({from: owner.address, amount: toNano(3)}));

            const event = await gauge.getEvent('GaugeAccountCodeUpdated');
            expect(event.new_version).to.be.eq('3');
        });

        it('User upgrade his account', async function() {
           await locklift.tracing.trace(gauge.contract.methods.upgradeGaugeAccount({
               meta: {call_id: 0, nonce: 0, send_gas_to: user1.address}
           }).send({from: user1.address, amount: toNano(2)}));

           const event = await gauge.getEvent('GaugeAccountUpgrade');
           expect(event.new_version).to.be.eq('3');
           expect(event.user.toString()).to.be.eq(user1.address.toString());
        });

        it('Fabric owner force upgrade user account', async function() {
            await locklift.tracing.trace(gauge_factory.methods.forceUpgradeGaugeAccounts({
                gauge: gauge.address, users: [user2.address] ,meta: {call_id: 0, nonce: 0, send_gas_to: owner.address}
            }).send({from: owner.address, amount: toNano(3)}));

            const event = await gauge.getEvent('GaugeAccountUpgrade');
            expect(event.new_version).to.be.eq('3');
            expect(event.user.toString()).to.be.eq(user2.address.toString());
        });

        it('New user deploy account', async function() {
            const acc3 = await gauge.gaugeAccount(user3.address);
            await locklift.tracing.trace(
                gauge.deposit(user3_deposit_wallet, deposit_amount, 0, false, 0),
                {
                    allowedCodes: {
                        contracts: {[acc3.address.toString()]: {compute: [null]}}
                    }
                }
            );
            const event = await gauge.getEvent('GaugeAccountDeploy');
            expect(event.user.toString()).to.be.eq(user3.address.toString());
        });
    });
});
