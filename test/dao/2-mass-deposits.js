const logger = require('mocha-logger');
const { expect } = require('chai');
var should = require('chai').should();

const BigNumber = require('bignumber.js');
const { convertCrystal, getRandomNonce } = locklift.utils;


const { setupTokenRoot, setupVoteEscrow, deployUser, sleep, runTargets} = require("../utils/common");


describe("Vote Escrow mass deposits scenario", async function() {
    this.timeout(3000000);

    let user;
    let owner;

    let current_epoch = 1;
    let count = 151;

    const deposit_amount = 1000;

    let vote_escrow;
    let ve_account;

    let qube_root;
    let user_qube_wallet;
    let owner_qube_wallet;
    let vote_escrow_qube_wallet;

    describe('Setup contracts', async function() {
        it('Deploy users', async function() {
            user = await deployUser(10000);
            owner = await deployUser(10000);
        });

        it('Deploy token', async function() {
            qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
        });

        it('Deploy token wallets + mint', async function() {
            owner_qube_wallet = await qube_root.mint(1000000000, owner);
            user_qube_wallet = await qube_root.mint(1000000000, user);
        });

        it('Deploy Vote Escrow', async function() {
            vote_escrow = await setupVoteEscrow(owner, qube_root);
            vote_escrow_qube_wallet = await vote_escrow.tokenWallet();

            const details = await vote_escrow.getCurrentEpochDetails();
            expect(details._currentEpoch.toString()).to.be.eq(current_epoch.toString());
        })
    });

    describe('Checking N deposits works correctly', async function() {
        it(`Making ${count} deposits`, async function() {
            // processing requires some time, so we must be sure it will not unlock until all deposits are processed
            // 1 deposit processing takes ~0.25 sec
            const lock_time = Math.floor(count * 0.25);
            logger.log(`Locking for ${lock_time}`);
            // make 1st deposit manually to initialize vote escrow account
            await vote_escrow.deposit(user_qube_wallet, deposit_amount, lock_time, 1, {compute: [null]});
            count -= 1;

            const deposit_payload = await vote_escrow.depositPayload(user, lock_time);
            const params = {
                amount: deposit_amount,
                recipient: vote_escrow.address,
                deployWalletValue: 0,
                remainingGasTo: user.address,
                notify: true,
                payload: deposit_payload
            };

            await runTargets(
                user,
                Array(count).fill(user_qube_wallet.contract),
                Array(count).fill('transfer'),
                Array(count).fill(params),
                Array(count).fill(convertCrystal(5, 'nano'))
            );

            count += 1;
            let ve_expected = await vote_escrow.calculateVeMint(deposit_amount, lock_time);
            ve_expected = ve_expected * count;

            ve_account = await vote_escrow.voteEscrowAccount(user.address);
            const acc_balance = await ve_account.calculateVeAverage();
            const acc_details = await ve_account.getDetails();
            const ve_details = await vote_escrow.details();

            // ve acc check
            expect(acc_balance._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            expect(acc_details._qubeBalance.toString()).to.be.eq((count * deposit_amount).toString());
            expect(acc_details._unlockedQubes.toString()).to.be.eq('0');

            expect(ve_details._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            expect(ve_details._qubeBalance.toString()).to.be.eq((count * deposit_amount).toString());
        });

        it('Making 1 more deposit, unlocking old ones', async function() {
            const lock_time = Math.floor(count * 0.25);
            // sleep to make sure all deposits are unlocked
            await sleep(lock_time * deposit_amount);

            const acc_balance = await ve_account.calculateVeAverage();
            expect(acc_balance._veQubeBalance.toString()).to.be.eq('0');

            await vote_escrow.deposit(user_qube_wallet, deposit_amount, 100, 2);
            const ve_expected = await vote_escrow.calculateVeMint(deposit_amount, 100);

            const acc_balance_1 = await ve_account.calculateVeAverage();
            const acc_details_1 = await ve_account.getDetails();
            const ve_details = await vote_escrow.details();

            // only ve qubes from new deposit
            expect(acc_balance_1._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            // + deposit_amount to qube balance
            expect(acc_details_1._qubeBalance.toString()).to.be.eq((count * deposit_amount + deposit_amount).toString());
            // all old qubes are unlocked
            expect(acc_details_1._unlockedQubes.toString()).to.be.eq((count * deposit_amount).toString());

            // all old ve qubes are burned
            expect(ve_details._veQubeBalance.toString()).to.be.eq(ve_expected.toString());
            expect(ve_details._qubeBalance.toString()).to.be.eq((count * deposit_amount + deposit_amount).toString());
        })

        it('Making withdraw', async function() {
            await vote_escrow.withdraw(user, 1);
            const event = await vote_escrow.getEvent('Withdraw');

            expect(event.call_id.toString()).to.be.eq('1');
            expect(event.amount.toString()).to.be.eq((count * deposit_amount).toString());

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
