const logger = require('mocha-logger');
const { expect } = require('chai');
var should = require('chai').should();

const BigNumber = require('bignumber.js');
const { convertCrystal, getRandomNonce } = locklift.utils;


const { setupTokenRoot, setupVoteEscrow, deployUser, deployUsers, sleep, runTargets} = require("../utils/common");


describe("Vote Escrow mass deposits scenario", async function() {
    this.timeout(3000000);

    let user;
    let owner;
    let gauges;

    let current_epoch = 1;
    const gauges_count = 105;
    const whitelist_price = 1000000;

    let vote_escrow;
    let ve_account;

    let qube_root;
    let user_qube_wallet;
    let owner_qube_wallet;
    let vote_escrow_qube_wallet;

    describe('Setup contracts', async function() {
        it('Deploy users', async function() {
            user = await deployUser(10000000);
            owner = await deployUser(10000000);

            gauges = await deployUsers(gauges_count, 100);
        });

        it('Deploy token', async function() {
            qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
        });

        it('Deploy token wallets + mint', async function() {
            owner_qube_wallet = await qube_root.mint(100000000000, owner);
            user_qube_wallet = await qube_root.mint(100000000000, user);
        });

        it('Deploy Vote Escrow', async function() {
            vote_escrow = await setupVoteEscrow({
                owner, qube:qube_root, whitelist_price: whitelist_price
            });
            vote_escrow_qube_wallet = await vote_escrow.tokenWallet();

            const details = await vote_escrow.getCurrentEpochDetails();
            expect(details._currentEpoch.toString()).to.be.eq(current_epoch.toString());
        })
    });

    describe("Checking huge number of gauges on voting works correctly", async function() {
        it(`Whitelisting ${gauges_count} gauges`, async function() {
            let params = [];
            for (const gauge of gauges) {
                const w_payload = await vote_escrow.whitelistDepositPayload(gauge.address);
                params.push({
                    amount: whitelist_price,
                    recipient: vote_escrow.address,
                    deployWalletValue: 0,
                    remainingGasTo: user.address,
                    notify: true,
                    payload: w_payload
                });
            }

            const chunkSize = 70;
            for (let i = 0; i < gauges_count; i += chunkSize) {
                const _params = params.slice(i, i + chunkSize);

                await runTargets(
                    user,
                    Array(_params.length).fill(user_qube_wallet.contract),
                    Array(_params.length).fill('transfer'),
                    _params,
                    Array(_params.length).fill(convertCrystal(50, 'nano'))
                );
            }

            const details = await vote_escrow.votingDetails();
            expect(details._gaugesNum.toString()).to.be.eq(gauges_count.toString());
        });
    });

    describe.skip('Checking huge number of deposits works correctly', async function() {
        it(`Made ${count * packs_num} deposits`, async function() {
            // processing requires some time, so we must be sure it will not unlock until all deposits are processed
            const lock_time = 700;
            logger.log(`Locking for ${lock_time} seconds`);

            const deposit_payload = await vote_escrow.depositPayload(user, lock_time);
            const params = {
                amount: deposit_amount,
                recipient: vote_escrow.address,
                deployWalletValue: 0,
                remainingGasTo: user.address,
                notify: true,
                payload: deposit_payload
            };

            let time_passed = 0;

            for (const i of Array.from(Array(packs_num).keys())) {
                logger.log(`Sending pack #${i + 1} with ${count} deposits`)
                const from = Date.now();
                await runTargets(
                    user,
                    Array(count).fill(user_qube_wallet.contract),
                    Array(count).fill('transfer'),
                    Array(count).fill(params),
                    Array(count).fill(convertCrystal(50, 'nano')),
                    {compute: [null]}
                );
                const to = Date.now();
                logger.log(`Pack processed in ${Math.floor((to - from) / 1000)}`);
                time_passed += Math.floor((to - from) / 1000);
            }

            logger.log(`${time_passed} seconds passed overall`);

            let ve_expected = await vote_escrow.calculateVeMint(deposit_amount, lock_time);
            ve_expected = ve_expected * count * packs_num;

            ve_account = await vote_escrow.voteEscrowAccount(user.address);
            const acc_balance = await ve_account.calculateVeAverage();
            const acc_details = await ve_account.getDetails();
            const ve_details = await vote_escrow.details();

            // ve acc check
            expect(acc_balance._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            expect(acc_details._qubeBalance.toString()).to.be.eq((count * deposit_amount * packs_num).toString());
            expect(acc_details._unlockedQubes.toString()).to.be.eq('0');

            expect(ve_details._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            expect(ve_details._qubeBalance.toString()).to.be.eq((count * deposit_amount * packs_num).toString());
        });

        it('Making 1 more deposit, unlocking old ones', async function() {
            logger.log(`Sleeping until all deposits are unlocked...`)

            while (true) {
                const acc_balance = await ve_account.calculateVeAverage();
                if (acc_balance._veQubeBalance.toString() === '0') {
                    break;
                }
                logger.log(`VeQube balance - ${acc_balance._veQubeBalance.toString()}, sleeping...`);
                await sleep(100 * 1000);
            }

            await vote_escrow.deposit(user_qube_wallet, deposit_amount, 100, 2);
            const ve_expected = await vote_escrow.calculateVeMint(deposit_amount, 100);

            const acc_balance_1 = await ve_account.calculateVeAverage();
            const acc_details_1 = await ve_account.getDetails();
            const ve_details = await vote_escrow.details();

            // only ve qubes from new deposit
            expect(acc_balance_1._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            // + deposit_amount to qube balance
            expect(acc_details_1._qubeBalance.toString()).to.be.eq((count * deposit_amount * packs_num + deposit_amount).toString());
            // all old qubes are unlocked
            expect(acc_details_1._unlockedQubes.toString()).to.be.eq((count * deposit_amount * packs_num).toString());

            // all old ve qubes are burned
            expect(ve_details._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            expect(ve_details._qubeBalance.toString()).to.be.eq((count * deposit_amount * packs_num + deposit_amount).toString());
        })

        it('Making withdraw', async function() {
            await vote_escrow.withdraw(user, 1);
            const event = await vote_escrow.getEvent('Withdraw');

            expect(event.call_id.toString()).to.be.eq('1');
            expect(event.amount.toString()).to.be.eq((count * deposit_amount * packs_num).toString());

            const ve_expected = await vote_escrow.calculateVeMint(deposit_amount, 100);
            // ve qubes only for new deposit
            const acc_balance = await ve_account.calculateVeAverage();
            const acc_details = await ve_account.getDetails();
            const ve_details = await vote_escrow.details();

            // only ve qubes from new deposit
            expect(acc_balance._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            // + deposit_amount to qube balance
            expect(acc_details._qubeBalance.toString()).to.be.eq(deposit_amount.toString());
            // all unlocked qubes qre withdrawn
            expect(acc_details._unlockedQubes.toString()).to.be.eq('0');

            // only last deposit is alive
            expect(ve_details._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            expect(ve_details._qubeBalance.toString()).to.be.eq(deposit_amount.toString());
        });
    });
});
