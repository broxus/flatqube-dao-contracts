import {expect} from "chai";
import {
    deployUser, sendAllEvers,
    setupGauge,
    setupGaugeFactory,
    setupTokenRoot,
    setupVoteEscrow,
    tryIncreaseTime
} from "../utils/common";
import {VoteEscrow} from "../utils/wrappers/vote_ecsrow";
import {Token} from "../utils/wrappers/token";
import {TokenWallet} from "../utils/wrappers/token_wallet";
import {Address, Contract, getRandomNonce, toNano} from "locklift";
import {GaugeFactoryAbi} from "../../build/factorySource";
import {Gauge} from "../utils/wrappers/gauge";
import {Account} from 'locklift/everscale-standalone-client'
var should = require('chai').should();


// @ts-ignore
const mint_to_addr = async function(token, owner, addr, amount) {
    await locklift.tracing.trace(token.methods.mint({
        amount: amount,
        recipient: addr,
        deployWalletValue: locklift.utils.toNano(1),
        remainingGasTo: owner.address,
        notify: false,
        payload: ''
    }).send({
        amount: toNano(5),
        from: owner.address
    }));
}


describe("Gauge main scenarios", async function() {
    let user1: Account;
    let user2: Account;
    let owner: Account;

    // just simple wallets here
    let gauge_factory: Contract<GaugeFactoryAbi>
    let gauge: Gauge;

    let vote_escrow: VoteEscrow;

    let qube_root: Token;
    let deposit_root: Token;
    let reward_root: Token;
    let reward2_root: Token;
    let reward3_root: Token;

    let user1_qube_wallet: TokenWallet;
    let user2_qube_wallet: TokenWallet;
    let owner_qube_wallet: TokenWallet;

    let owner_reward_wallet: TokenWallet;
    let owner_reward2_wallet: TokenWallet;
    let owner_reward3_wallet: TokenWallet;

    let user1_deposit_wallet: TokenWallet;
    let user2_deposit_wallet: TokenWallet;
    let owner_deposit_wallet: TokenWallet;

    describe('Setup contracts', async function () {
        it('Deploy users', async function () {
            user1 = await deployUser(30);
            user2 = await deployUser(30);
            owner = await deployUser(60);
        });

        it('Deploy tokens', async function () {
            qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
            deposit_root = await setupTokenRoot('TEST', 'TEST', owner);
            reward_root = await setupTokenRoot('REW1', 'REW1', owner);
            reward2_root = await setupTokenRoot('REW2', 'REW2', owner);
            reward3_root = await setupTokenRoot('REW3', 'REW3', owner);
        });

        it('Mint tokens', async function () {
            owner_qube_wallet = await qube_root.mint(1000000000, owner);
            user1_qube_wallet = await qube_root.mint(1000000000, user1);
            user2_qube_wallet = await qube_root.mint(1000000000, user2);

            owner_deposit_wallet = await deposit_root.mint(1000000000, owner);
            user1_deposit_wallet = await deposit_root.mint(1000000000, user1);
            user2_deposit_wallet = await deposit_root.mint(1000000000, user2);

            owner_reward_wallet = await reward_root.mint(100000000000, owner);
            owner_reward2_wallet = await reward2_root.mint(100000000000, owner);
            owner_reward3_wallet = await reward3_root.mint(100000000000, owner);

            const addr = new Address('0:311fe8e7bfeb6a2622aaba02c21569ac1e6f01c81c33f2623e5d8f1a5ba232d7');
            await mint_to_addr(qube_root.contract, qube_root.owner, addr, '1000000000000000');
            await mint_to_addr(deposit_root.contract, deposit_root.owner, addr, '1000000000000000');
            await mint_to_addr(reward_root.contract, reward_root.owner, addr, '1000000000000000');
            await mint_to_addr(reward2_root.contract, reward2_root.owner, addr, '1000000000000000');
            await mint_to_addr(reward3_root.contract, reward3_root.owner, addr, '1000000000000000');
        });

        it('Deploy Vote Escrow', async function () {
            vote_escrow = await setupVoteEscrow({
                owner, qube: qube_root
            });
            await locklift.tracing.trace(vote_escrow.distributionDeposit(owner_qube_wallet, 1000000000));
        });

        it('Deploy Gauge Factory', async function() {
           gauge_factory = await setupGaugeFactory({
               _owner: owner, _qube: qube_root, _voteEscrow: vote_escrow, _qubeVestingRatio: 0, _qubeVestingPeriod: 0
           });
        });
    });

    describe('Running scenarios', async function() {
        describe('Testing deposit/withdraw, 1 user, no reward', async function() {
            const deposit_amount = 1000;
            let gauge_inited = false;

            beforeEach('Deploy gauge', async function() {
                if (!gauge_inited) {
                    gauge = await setupGauge({
                        owner,
                        gauge_factory,
                        deposit_root,
                        max_lock_time: 100,
                        reward_roots: [],
                        vesting_periods: [],
                        vesting_ratios: [],
                        withdraw_lock_period: 0,
                        qube_vesting_ratio: 0,
                        qube_vesting_period: 0,
                        call_id: getRandomNonce()
                    });
                    gauge_inited = true;
                }
            });

            describe('Common deposit', async function() {
                it('Deposit', async function() {
                    const acc = await gauge.gaugeAccount(user1.address);

                    await locklift.tracing.trace(
                        gauge.deposit(user1_deposit_wallet, deposit_amount, 0, false, 0),
                        {allowedCodes: {contracts: {[acc.address.toString()]: {compute: [null]}}}}
                    );

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    expect(details._lockBoostedSupply).to.be.eq(deposit_amount.toString());
                    expect(details._totalBoostedSupply).to.be.eq(deposit_amount.toString());
                    expect(token_details._depositTokenData.balance).to.be.eq(deposit_amount.toString());

                    await tryIncreaseTime(1);
                    const averages = await acc.methods.calculateLockBalanceAverage().call();

                    expect(averages._lockedBalance).to.be.eq('0');
                    expect(averages._lockBoostedBalance).to.be.eq(deposit_amount.toString());
                    expect(averages._lockBoostedBalanceAverage).to.be.eq(deposit_amount.toString());
                });

                it('Withdraw', async function() {
                    await locklift.tracing.trace(gauge.withdraw(user1, deposit_amount, false));

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    expect(details._lockBoostedSupply).to.be.eq('0');
                    expect(details._totalBoostedSupply).to.be.eq('0');
                    expect(token_details._depositTokenData.balance).to.be.eq('0');

                    const acc = await gauge.gaugeAccount(user1.address);
                    const averages = await acc.methods.calculateLockBalanceAverage().call();

                    expect(averages._lockedBalance).to.be.eq('0');
                    expect(averages._lockBoostedBalance).to.be.eq('0');
                });

                it('Deposit again', async function() {
                    await tryIncreaseTime(1);
                    await locklift.tracing.trace(gauge.deposit(user1_deposit_wallet, deposit_amount, 0, false, 22));

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    expect(details._lockBoostedSupply).to.be.eq(deposit_amount.toString());
                    expect(details._totalBoostedSupply).to.be.eq(deposit_amount.toString());
                    expect(token_details._depositTokenData.balance).to.be.eq(deposit_amount.toString());
                    gauge_inited = false;
                });
            });

            describe('Ve boosted deposit', async function() {
                it('Deposit', async function() {
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
                    expect(token_details._depositTokenData.balance).to.be.eq(deposit_amount.toString());

                    await tryIncreaseTime(1);
                    const acc = await gauge.gaugeAccount(user1.address);
                    const averages = await acc.methods.calculateLockBalanceAverage().call();

                    expect(averages._lockedBalance).to.be.eq(deposit_amount.toString());
                    expect(averages._lockBoostedBalance).to.be.eq((deposit_amount * 2).toString());
                    expect(averages._lockBoostedBalanceAverage).to.be.eq((deposit_amount * 2).toString());
                });

                it('Withdraw', async function() {
                    await tryIncreaseTime(100);
                    await locklift.tracing.trace(gauge.withdraw(user1, deposit_amount, false));

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    expect(details._lockBoostedSupply).to.be.eq('0');
                    expect(details._totalBoostedSupply).to.be.eq('0');
                    expect(token_details._depositTokenData.balance).to.be.eq('0');

                    const acc = await gauge.gaugeAccount(user1.address);
                    const averages = await acc.methods.calculateLockBalanceAverage().call();

                    expect(averages._lockedBalance).to.be.eq('0');
                    expect(averages._lockBoostedBalance).to.be.eq('0');
                    gauge_inited = false;
                });
            });

            describe('Lock deposit', async function() {
                it('Deposit', async function() {
                    await locklift.tracing.trace(
                        gauge.deposit(user1_deposit_wallet, deposit_amount, 100, false, 2),
                        {allowedCodes: {compute: [null]}}
                    );

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    expect(details._lockBoostedSupply).to.be.eq((deposit_amount * 2).toString());
                    expect(details._totalBoostedSupply).to.be.eq((deposit_amount * 2).toString());
                    expect(token_details._depositTokenData.balance).to.be.eq(deposit_amount.toString());

                    await tryIncreaseTime(1);
                    const acc = await gauge.gaugeAccount(user1.address);
                    const averages = await acc.methods.calculateLockBalanceAverage({}).call();

                    expect(averages._lockedBalance).to.be.eq(deposit_amount.toString());
                    expect(averages._lockBoostedBalance).to.be.eq((deposit_amount * 2).toString());
                    expect(averages._lockBoostedBalanceAverage).to.be.eq((deposit_amount * 2).toString());
                });

                it('Withdraw', async function() {
                    await tryIncreaseTime(100);
                    await locklift.tracing.trace(gauge.withdraw(user1, deposit_amount, false));

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    expect(details._lockBoostedSupply).to.be.eq('0');
                    expect(details._totalBoostedSupply).to.be.eq('0');
                    expect(token_details._depositTokenData.balance).to.be.eq('0');

                    const acc = await gauge.gaugeAccount(user1.address);
                    const averages = await acc.methods.calculateLockBalanceAverage().call();

                    expect(averages._lockedBalance).to.be.eq('0');
                    expect(averages._lockBoostedBalance).to.be.eq('0');
                    gauge_inited = false;
                });
            });

            describe('Mixed deposits', async function() {
                it('Simple deposit', async function() {
                    await locklift.tracing.trace(
                        gauge.deposit(user1_deposit_wallet, deposit_amount, 0, false, 0),
                        {allowedCodes: {compute: [null]}}
                    );

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    expect(details._lockBoostedSupply).to.be.eq(deposit_amount.toString());
                    expect(details._totalBoostedSupply).to.be.eq(deposit_amount.toString());
                    expect(token_details._depositTokenData.balance).to.be.eq(deposit_amount.toString());

                    await tryIncreaseTime(1);
                    const acc = await gauge.gaugeAccount(user1.address);
                    const averages = await acc.methods.calculateLockBalanceAverage().call();

                    expect(averages._lockedBalance).to.be.eq('0');
                    expect(averages._lockBoostedBalance).to.be.eq(deposit_amount.toString());
                    expect(averages._lockBoostedBalanceAverage).to.be.eq(deposit_amount.toString());
                });

                it('Lock deposit', async function() {
                    await locklift.tracing.trace(gauge.deposit(user1_deposit_wallet, deposit_amount, 100, false, 0));

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    expect(details._lockBoostedSupply).to.be.eq((deposit_amount * 3).toString());
                    expect(details._totalBoostedSupply).to.be.eq((deposit_amount * 3).toString());
                    expect(token_details._depositTokenData.balance).to.be.eq((deposit_amount * 2).toString());

                    await tryIncreaseTime(1);
                    const acc = await gauge.gaugeAccount(user1.address);
                    const averages = await acc.methods.calculateLockBalanceAverage({}).call();

                    expect(averages._lockedBalance).to.be.eq(deposit_amount.toString());
                    expect(averages._lockBoostedBalance).to.be.eq((deposit_amount * 3).toString());
                });

                it('Ve deposit', async function() {
                    await locklift.tracing.trace(vote_escrow.deposit(user1_qube_wallet, deposit_amount, 100, 0));
                    await locklift.tracing.trace(gauge.deposit(user1_deposit_wallet, deposit_amount, 100, false, 0));

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    const total_deposit = deposit_amount * 3;
                    const total_boosted = total_deposit * ((deposit_amount * 5) / total_deposit + 2.5 - 1) - 1;
                    // 2.5x boost + 2x boost
                    expect(details._lockBoostedSupply).to.be.eq((deposit_amount * 5).toString());
                    expect(details._totalBoostedSupply).to.be.eq(total_boosted.toString());
                    expect(token_details._depositTokenData.balance).to.be.eq(total_deposit.toString());

                    await tryIncreaseTime(1);
                    const acc = await gauge.gaugeAccount(user1.address);
                    const averages = await acc.methods.calculateLockBalanceAverage().call();

                    expect(averages._lockedBalance).to.be.eq((deposit_amount * 2).toString());
                    expect(averages._lockBoostedBalance).to.be.eq((deposit_amount * 5).toString());
                });

                it('Withdraw', async function() {
                    await tryIncreaseTime(100);
                    await locklift.tracing.trace(gauge.withdraw(user1, deposit_amount * 3, false));

                    const details = await gauge.getDetails();
                    const token_details = await gauge.getTokenDetails();

                    expect(details._lockBoostedSupply).to.be.eq('0');
                    expect(details._totalBoostedSupply).to.be.eq('0');
                    expect(token_details._depositTokenData.balance).to.be.eq('0');

                    const acc = await gauge.gaugeAccount(user1.address);
                    const averages = await acc.methods.calculateLockBalanceAverage().call();

                    expect(averages._lockedBalance).to.be.eq('0');
                    expect(averages._lockBoostedBalance).to.be.eq('0');
                });
            });
        });

        describe('Testing qube reward, multiple users, multiple rounds', async function() {
            const deposit_amount = 1000;
            const qube_reward = 100000;

            it('Deploy gauge', async function() {
                gauge = await setupGauge({
                    owner,
                    gauge_factory,
                    deposit_root,
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

            it('Users deposit', async function() {
                await locklift.tracing.trace(
                    gauge.deposit(user1_deposit_wallet, deposit_amount, 0, false, 0),
                    {allowedCodes: {compute: [null]}}
                );

                await locklift.tracing.trace(
                    gauge.deposit(user2_deposit_wallet, deposit_amount, 0, false, 0),
                    {allowedCodes: {compute: [null]}}
                );

                const details = await gauge.getDetails();
                const token_details = await gauge.getTokenDetails();

                const total_deposited = deposit_amount * 2;
                expect(details._lockBoostedSupply).to.be.eq(total_deposited.toString());
                expect(details._totalBoostedSupply).to.be.eq(total_deposited.toString());
                expect(token_details._depositTokenData.balance).to.be.eq(total_deposited.toString());
            });

            it('Add qube reward round', async function() {
                const time = Math.floor(locklift.testing.getCurrentTime() / 1000);
                await locklift.tracing.trace(vote_escrow.sendQubesToGauge(gauge.address, qube_reward, 10, time + 10));

                const reward_data = await gauge.getRewardDetails();
                const round = reward_data._qubeRewardRounds[0];

                expect(round.startTime).to.be.eq((time + 10).toString());
                expect(round.rewardPerSecond).to.be.eq((Math.floor(qube_reward / 10)).toString());
            });

            it('Users claim reward', async function() {
                // make sure reward round passed
                await tryIncreaseTime(25);
                await locklift.tracing.trace(gauge.claimReward(user1, 1));

                const claim1 = await gauge.getEvent('Claim') as any;
                expect(claim1.call_id).to.be.eq('1');
                expect(claim1.qube_reward).to.be.eq((Math.floor(qube_reward / 2)).toString());

                await locklift.tracing.trace(gauge.claimReward(user2, 2));

                const claim2 = await gauge.getEvent('Claim') as any;
                expect(claim2.call_id).to.be.eq('2');
                expect(claim2.qube_reward).to.be.eq((Math.floor(qube_reward / 2)).toString());

                const token_details = await gauge.getTokenDetails();
                expect(token_details._qubeTokenData.balance).to.be.eq('0');
            });

            it('User withdraw part with claim=true, no reward', async function() {
                await locklift.tracing.trace(gauge.withdraw(user2, Math.floor(deposit_amount * 3/4), true, 3));

                const withdraw = await gauge.getEvent('Withdraw') as any;
                expect(withdraw.call_id).to.be.eq('3');
                expect(withdraw.amount).to.be.eq(Math.floor(deposit_amount * 3/4).toString());

                const claim = await gauge.getEvent('Claim') as any;
                expect(claim.call_id).to.be.eq('3');
                expect(claim.qube_reward).to.be.eq('0');
            });

            it('Add multiple qube reward rounds', async function() {
                const time = Math.floor(locklift.testing.getCurrentTime() / 1000);
                await locklift.tracing.trace(vote_escrow.sendQubesToGauge(gauge.address, qube_reward, 10, time + 20));
                await locklift.tracing.trace(vote_escrow.sendQubesToGauge(gauge.address, qube_reward, 10, time + 30));
                await locklift.tracing.trace(vote_escrow.sendQubesToGauge(gauge.address, qube_reward * 2, 10, time + 40));
            });

            it('Users withdraw with claim=true', async function() {
                await tryIncreaseTime(100);

                const sync_data = (await gauge.contract.methods.calcSyncData().call()).value0;
                const acc1 = await gauge.gaugeAccount(user1.address);
                const acc2 = await gauge.gaugeAccount(user2.address);

                const pending1 = await acc1.methods.pendingReward({
                    _veAccQubeAverage: 0,
                    _veAccQubeAveragePeriod: 0,
                    _veQubeAverage: 0,
                    _veQubeAveragePeriod: 0,
                    gauge_sync_data: sync_data
                }).call();

                const pending2 = await acc2.methods.pendingReward({
                    _veAccQubeAverage: 0,
                    _veAccQubeAveragePeriod: 0,
                    _veQubeAverage: 0,
                    _veQubeAveragePeriod: 0,
                    gauge_sync_data: sync_data
                }).call();

                const total_reward = qube_reward * 4;
                await locklift.tracing.trace(gauge.withdraw(user2, Math.floor(deposit_amount/4), true, 4));

                const withdraw1 = await gauge.getEvent('Withdraw') as any;
                expect(withdraw1.call_id).to.be.eq('4');
                expect(withdraw1.amount).to.be.eq(Math.floor(deposit_amount/4).toString());

                const expected_reward = Math.floor(total_reward / 5) - 320; // rounding err
                const claim1 = await gauge.getEvent('Claim') as any;
                expect(claim1.call_id).to.be.eq('4');
                expect(claim1.qube_reward).to.be.eq(expected_reward.toString());
                expect(claim1.qube_reward).to.be.eq(pending2._qubeReward.unlockedReward.toString());

                await locklift.tracing.trace(gauge.withdraw(user1, deposit_amount,true, 5));

                const withdraw2 = await gauge.getEvent('Withdraw') as any;
                expect(withdraw2.call_id).to.be.eq('5');
                expect(withdraw2.amount).to.be.eq(deposit_amount.toString());

                const claim2 = await gauge.getEvent('Claim') as any;
                expect(claim2.call_id).to.be.eq('5');
                expect(claim2.qube_reward).to.be.eq((Math.floor(total_reward * 4/5)).toString());
                expect(claim2.qube_reward).to.be.eq(pending1._qubeReward.unlockedReward.toString());
            });

            it('QUBE reward rounds overflow', async function() {
                const reward_data = await gauge.getRewardDetails();
                const rounds_num = 10 - reward_data._qubeRewardRounds.length;

                const time = Math.floor(locklift.testing.getCurrentTime() / 1000);
                for (const i of Array.from(Array(rounds_num).keys())) {
                    await locklift.tracing.trace(vote_escrow.sendQubesToGauge(gauge.address, qube_reward, 1, time + i + 1));
                }
                // now we have max number of stored rounds
                const reward_data_1 = await gauge.getRewardDetails();
                expect(reward_data_1._qubeRewardRounds.length).to.be.eq(10);

                await locklift.tracing.trace(vote_escrow.sendQubesToGauge(gauge.address, qube_reward, 2, time + 10));

                const reward_data_2 = await gauge.getRewardDetails();
                expect(reward_data_2._qubeRewardRounds.length).to.be.eq(10);

                // ensure rounds were copied
                for (const i of Array.from(Array(9).keys())) {
                    expect(reward_data_2._qubeRewardRounds[i].startTime).to.be.eq(reward_data_1._qubeRewardRounds[i + 1].startTime);
                    expect(reward_data_2._qubeRewardRounds[i].endTime).to.be.eq(reward_data_1._qubeRewardRounds[i + 1].endTime);
                    expect(reward_data_2._qubeRewardRounds[i].accRewardPerShare).to.be.eq(reward_data_1._qubeRewardRounds[i + 1].accRewardPerShare);
                }
            });
        });

        describe('Testing extra reward, multiple users, multiple rounds', async function() {
            const deposit_amount = 1000;
            const reward_amount = 1000000;

            it('Deploy gauge', async function() {
                gauge = await setupGauge({
                    owner,
                    gauge_factory,
                    deposit_root,
                    max_lock_time: 100,
                    reward_roots: [reward_root],
                    vesting_periods: [0],
                    vesting_ratios: [0],
                    withdraw_lock_period: 200,
                    qube_vesting_ratio: 0,
                    qube_vesting_period: 0,
                    call_id: getRandomNonce()
                });
            });

            it('Users deposit', async function() {
                await locklift.tracing.trace(
                    gauge.deposit(user1_deposit_wallet, deposit_amount, 0, false, 0),
                    {allowedCodes: {compute: [null]}}
                );

                await locklift.tracing.trace(
                    gauge.deposit(user2_deposit_wallet, deposit_amount, 0, false, 0),
                    {allowedCodes: {compute: [null]}}
                );

                const details = await gauge.getDetails();
                const token_details = await gauge.getTokenDetails();

                const total_deposited = deposit_amount * 2;
                expect(details._lockBoostedSupply).to.be.eq(total_deposited.toString());
                expect(details._totalBoostedSupply).to.be.eq(total_deposited.toString());
                expect(token_details._depositTokenData.balance).to.be.eq(total_deposited.toString());
            });

            it('Add extra reward rounds', async function() {
                const time = Math.floor(locklift.testing.getCurrentTime() / 1000);
                await locklift.tracing.trace(gauge.addRewardRounds(
                    [0, 0],[{rewardPerSecond: 1000, startTime: time + 5}, {rewardPerSecond: 0, startTime: time + 10}]
                    )
                );

                const reward_data = await gauge.getRewardDetails();
                const round = reward_data._extraRewardRounds[0][0];
                const round1 = reward_data._extraRewardRounds[0][1];

                expect(round.startTime).to.be.eq((time + 5).toString());
                expect(round.rewardPerSecond).to.be.eq('1000');

                expect(round1.startTime).to.be.eq((time + 10).toString());
                expect(round1.rewardPerSecond).to.be.eq('0');

                await locklift.tracing.trace(gauge.rewardDeposit(owner_reward_wallet, reward_amount, 1));

                const token_details = await gauge.getTokenDetails();
                expect(token_details._extraTokenData[0].balance).to.be.eq('1000000');

                const reward_event = await gauge.getEvent('RewardDeposit') as any;
                expect(reward_event.call_id).to.be.eq('1');
                expect(reward_event.reward_id).to.be.eq('0');
                expect(reward_event.amount).to.be.eq('1000000');
            });

            it('Users claim reward', async function() {
                const expected_reward = 1000 * 5;
                // make sure reward round passed
                await tryIncreaseTime(25);
                await locklift.tracing.trace(gauge.claimReward(user1, 1));

                const claim1 = await gauge.getEvent('Claim') as any;
                expect(claim1.call_id).to.be.eq('1');
                expect(claim1.qube_reward).to.be.eq('0');
                expect(claim1.extra_reward[0]).to.be.eq((Math.floor(expected_reward / 2)).toString());

                await locklift.tracing.trace(gauge.claimReward(user2, 2));

                const claim2 = await gauge.getEvent('Claim') as any;
                expect(claim2.call_id).to.be.eq('2');
                expect(claim1.qube_reward).to.be.eq('0');
                expect(claim2.extra_reward[0]).to.be.eq((Math.floor(expected_reward / 2)).toString());

                const token_details = await gauge.getTokenDetails();
                expect(token_details._extraTokenData[0].balance).to.be.eq((reward_amount - expected_reward).toString());
            });

            it('User withdraw part with claim=true, no reward', async function() {
                await locklift.tracing.trace(gauge.withdraw(user2, Math.floor(deposit_amount * 3/4), true, 3));

                const withdraw = await gauge.getEvent('Withdraw') as any;
                expect(withdraw.call_id).to.be.eq('3');
                expect(withdraw.amount).to.be.eq(Math.floor(deposit_amount * 3/4).toString());

                const claim = await gauge.getEvent('Claim') as any;
                expect(claim.call_id).to.be.eq('3');
                expect(claim.qube_reward).to.be.eq('0');
                expect(claim.extra_reward[0]).to.be.eq('0');
            });

            it('Add more extra reward rounds, set farm end time', async function() {
                const time = Math.floor(locklift.testing.getCurrentTime() / 1000);
                await locklift.tracing.trace(gauge.addRewardRounds(
                        [0, 0],[{rewardPerSecond: 1000, startTime: time + 5}, {rewardPerSecond: 2000, startTime: time + 10}]
                    )
                );

                const reward_data = await gauge.getRewardDetails();
                const round = reward_data._extraRewardRounds[0][2];
                const round1 = reward_data._extraRewardRounds[0][3];

                expect(round.startTime).to.be.eq((time + 5).toString());
                expect(round.rewardPerSecond).to.be.eq('1000');

                expect(round1.startTime).to.be.eq((time + 10).toString());
                expect(round1.rewardPerSecond).to.be.eq('2000');

                await locklift.tracing.trace(gauge.setExtraFarmEndTime([0], [time + 15]));

                const reward_data1 = await gauge.getRewardDetails();
                expect(reward_data1._extraRewardEnded[0]).to.be.eq(true);
            });

            it('Users withdraw with claim=true', async function() {
                await tryIncreaseTime(100);

                const sync_data = (await gauge.contract.methods.calcSyncData().call()).value0;
                const acc1 = await gauge.gaugeAccount(user1.address);
                const acc2 = await gauge.gaugeAccount(user2.address);

                const pending1 = await acc1.methods.pendingReward({
                    _veAccQubeAverage: 0,
                    _veAccQubeAveragePeriod: 0,
                    _veQubeAverage: 0,
                    _veQubeAveragePeriod: 0,
                    gauge_sync_data: sync_data
                }).call();
                const pending2 = await acc2.methods.pendingReward({
                    _veAccQubeAverage: 0,
                    _veAccQubeAveragePeriod: 0,
                    _veQubeAverage: 0,
                    _veQubeAveragePeriod: 0,
                    gauge_sync_data: sync_data
                }).call();

                const total_reward = 1000 * 5 + 2000 * 5;
                await locklift.tracing.trace(gauge.withdraw(user2, Math.floor(deposit_amount/4), true, 4));

                const withdraw1 = await gauge.getEvent('Withdraw') as any;
                expect(withdraw1.call_id).to.be.eq('4');
                expect(withdraw1.amount).to.be.eq(Math.floor(deposit_amount/4).toString());

                const expected_reward = Math.floor(total_reward / 5) - 12; // rounding err
                const claim1 = await gauge.getEvent('Claim') as any;
                expect(claim1.call_id).to.be.eq('4');
                expect(claim1.qube_reward).to.be.eq('0');
                expect(claim1.extra_reward[0]).to.be.eq(pending2._extraReward[0].unlockedReward.toString());
                expect(claim1.extra_reward[0]).to.be.eq(expected_reward.toString());

                await locklift.tracing.trace(gauge.withdraw(user1, deposit_amount,true, 5));

                const withdraw2 = await gauge.getEvent('Withdraw') as any;
                expect(withdraw2.call_id).to.be.eq('5');
                expect(withdraw2.amount).to.be.eq(deposit_amount.toString());

                const claim2 = await gauge.getEvent('Claim') as any;
                expect(claim2.call_id).to.be.eq('5');
                expect(claim2.qube_reward).to.be.eq('0');
                expect(claim2.extra_reward[0]).to.be.eq(pending1._extraReward[0].unlockedReward.toString());
                expect(claim2.extra_reward[0]).to.be.eq((Math.floor(total_reward *4/5).toString()));
            });

            it('Withdraw remaining reward from gauge', async function() {
                await tryIncreaseTime(150);
                await locklift.tracing.trace(gauge.withdrawUnclaimed([0], owner.address));

                const token_details = await gauge.getTokenDetails();
                expect(token_details._extraTokenData[0].balance).to.be.eq('0');
            });
        });

        describe('Testing big number of extra reward rounds + qube reward, multiple users', async function() {
            const qube_reward = 1000;
            const reward_amount = 1000000;
            const deposit_amount = 1000;

            it('Deploy gauge', async function() {
                gauge = await setupGauge({
                    owner,
                    gauge_factory,
                    deposit_root,
                    max_lock_time: 100,
                    reward_roots: [reward_root, reward2_root, reward3_root],
                    vesting_periods: [0, 0, 0],
                    vesting_ratios: [0, 0, 0],
                    withdraw_lock_period: 1000,
                    qube_vesting_ratio: 0,
                    qube_vesting_period: 0,
                    call_id: getRandomNonce()
                });
            });

            it('User deposit', async function() {
                const acc1 = await gauge.gaugeAccount(user1.address);

                await locklift.tracing.trace(
                    gauge.deposit(user1_deposit_wallet, deposit_amount, 0, false, 0),
                    {allowedCodes: {contracts: {[acc1.address.toString()]: {compute: [null]}}}}
                );
            });

            it('Adding qube reward rounds', async function() {
                const time = Math.floor(locklift.testing.getCurrentTime() / 1000);
                for (const i of Array.from(Array(10).keys())) {
                    await locklift.tracing.trace(vote_escrow.sendQubesToGauge(gauge.address, qube_reward, 1, time + i + 20));
                }
            });

            it('Adding extra reward rounds', async function() {
                const time = Math.floor(locklift.testing.getCurrentTime() / 1000);
                for (const i of [0, 1, 2]) {
                    const ids = (Array.from(Array(40).keys())).fill(i);
                    const rounds = Array.from(Array(40).keys()).map((i) => {
                        return {rewardPerSecond: 1000, startTime: time + 20 + i}
                    });
                    await locklift.tracing.trace(gauge.addRewardRounds(ids, rounds));
                }

                await locklift.tracing.trace(gauge.rewardDeposit(owner_reward_wallet, reward_amount, 1));
                await locklift.tracing.trace(gauge.rewardDeposit(owner_reward2_wallet, reward_amount, 2));
                await locklift.tracing.trace(gauge.rewardDeposit(owner_reward3_wallet, reward_amount, 3));
            });

            it('New user deposit', async function() {
                await tryIncreaseTime(200);
                const acc2 = await gauge.gaugeAccount(user2.address);

                await locklift.tracing.trace(
                    gauge.deposit(user2_deposit_wallet, deposit_amount, 0, false, 10, toNano(20)),
                    {allowedCodes: {contracts: {[acc2.address.toString()]: {compute: [null]}}}}
                );
            });

            it('Users claim reward', async function() {
                await tryIncreaseTime(100);
                await locklift.tracing.trace(gauge.claimReward(user1, 1));
                await locklift.tracing.trace(gauge.claimReward(user2, 2));
            });
        })

        describe('Testing vesting mechanic', async function() {
            const deposit_amount = 1000;
            const qube_reward = 1000000;

            it('Deploy gauge', async function() {
                gauge = await setupGauge({
                    owner,
                    gauge_factory,
                    deposit_root,
                    max_lock_time: 100,
                    reward_roots: [reward_root],
                    vesting_periods: [50],
                    vesting_ratios: [1000],
                    withdraw_lock_period: 0,
                    qube_vesting_ratio: 1000,
                    qube_vesting_period: 50,
                    call_id: getRandomNonce()
                });
            });

            it('User deposit', async function() {
                const acc = await gauge.gaugeAccount(user1.address);

                await locklift.tracing.trace(
                    gauge.deposit(user1_deposit_wallet, deposit_amount, 0, false, 0),
                    {allowedCodes: {contracts: {[acc.address.toString()]: {compute: [null]}}}}
                );

                const details = await gauge.getDetails();
                const token_details = await gauge.getTokenDetails();

                expect(details._lockBoostedSupply).to.be.eq(deposit_amount.toString());
                expect(details._totalBoostedSupply).to.be.eq(deposit_amount.toString());
                expect(token_details._depositTokenData.balance).to.be.eq(deposit_amount.toString());

                await tryIncreaseTime(1);
                const averages = await acc.methods.calculateLockBalanceAverage().call();

                expect(averages._lockedBalance).to.be.eq('0');
                expect(averages._lockBoostedBalance).to.be.eq(deposit_amount.toString());
                expect(averages._lockBoostedBalanceAverage).to.be.eq(deposit_amount.toString());
            });

            it('Add reward rounds', async function() {
                const time = Math.floor(locklift.testing.getCurrentTime() / 1000);
                await locklift.tracing.trace(gauge.addRewardRounds(
                    [0, 0],
                    [{rewardPerSecond: 1000, startTime: time + 5}, {rewardPerSecond: 1000, startTime: time + 10}]
                    )
                );
                // test case when end time is set   
                await locklift.tracing.trace(gauge.setExtraFarmEndTime([0], [time + 15]));
                await locklift.tracing.trace(vote_escrow.sendQubesToGauge(gauge.address, qube_reward, 10, time + 10));
                await locklift.tracing.trace(gauge.rewardDeposit(owner_reward_wallet, 10000, 111));
            });

            it('Claim reward', async function() {
                const acc = await gauge.gaugeAccount(user1.address);
                // vesting should pass
                await tryIncreaseTime(20 + 50);

                const sync_data2 = (await gauge.contract.methods.calcSyncData().call()).value0;
                const pending2 = await acc.methods.pendingReward({
                    _veAccQubeAverage: 0,
                    _veAccQubeAveragePeriod: 0,
                    _veQubeAverage: 0,
                    _veQubeAveragePeriod: 0,
                    gauge_sync_data: sync_data2
                }).call();

                // we can claim all reward
                expect(pending2._extraReward[0].lockedReward).to.be.eq('0');
                expect(pending2._qubeReward.lockedReward).to.be.eq('0');
                expect(pending2._qubeReward.unlockedReward).to.be.eq('1000000');
                expect(pending2._extraReward[0].unlockedReward).to.be.eq('10000');

                await locklift.tracing.trace(gauge.claimReward(user1, 123));
                const event = await gauge.getEvent('Claim') as any;
                expect(event.qube_reward).to.be.eq('1000000');
                expect(event.extra_reward[0]).to.be.eq('10000');

                const sync_data3 = (await gauge.contract.methods.calcSyncData().call()).value0;
                const pending3 = await acc.methods.pendingReward({
                    _veAccQubeAverage: 0,
                    _veAccQubeAveragePeriod: 0,
                    _veQubeAverage: 0,
                    _veQubeAveragePeriod: 0,
                    gauge_sync_data: sync_data3
                }).call();

                expect(pending3._extraReward[0].lockedReward).to.be.eq('0');
                expect(pending3._qubeReward.lockedReward).to.be.eq('0');
                expect(pending3._qubeReward.unlockedReward).to.be.eq('0');
                expect(pending3._extraReward[0].unlockedReward).to.be.eq('0');
            });
        });

        describe('Cleanup', async function() {
           it('Clean', async function() {
               const giver = new Address(locklift.context.network.config.giver.address);

               await sendAllEvers(user1, giver);
               await sendAllEvers(user2, giver);
               await sendAllEvers(owner, giver);
           });
        });
    });
});
