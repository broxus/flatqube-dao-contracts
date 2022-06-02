const logger = require('mocha-logger');
const { expect, version} = require('chai');
const BigNumber = require('bignumber.js');
const {
    convertCrystal
} = locklift.utils;


const { setupTokenRoot, setupVoteEscrow, deployUser } = require("../utils/common");


describe("Main Vote Escrow scenarios", async function() {
    this.timeout(3000000);

    let user;
    let owner;

    let vote_escrow;
    let ve_account;

    let qube_root;
    let user_qube_wallet;
    let owner_qube_wallet;
    let vote_escrow_qube_wallet;

    describe('Setup contracts', async function() {
        it('Deploy users', async function() {
            user = await deployUser();
            owner = await deployUser();
        })

        it('Deploy token', async function() {
           qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
        });

        it('Deploy token wallets + mint', async function() {
            owner_qube_wallet = await qube_root.mint(1000000000, owner);
            user_qube_wallet = await qube_root.mint(1000000000, user);
        });

        it('Deploy Vote Escrow', async function() {
            vote_escrow = await setupVoteEscrow(owner, qube_root);
        })
    });

    describe('Running scenarios', async function() {
        describe('Making deposits', async function() {
            it('1st deposit', async function() {
                const lock_time = 100;
                await vote_escrow.deposit(user_qube_wallet, 1000, lock_time, 1, {compute: [null]});
                const event = await vote_escrow.getEvent('Deposit');
                const ve_expected = await vote_escrow.calculateVeMint(1000, lock_time);

                expect(event.call_id.toString()).to.be.eq('1');
                expect(event.amount.toString()).to.be.eq('1000');
                expect(event.lock_time.toString()).to.be.eq('100');
                expect(event.ve_amount.toString()).to.be.eq(ve_expected.toString());

                ve_account = await vote_escrow.voteEscrowAccount(user);
                const details = await ve_account.getDetails();
                expect(details._qubeBalance.toString()).to.be.eq('1000');
                expect(details._veQubeBalance.toString()).to.be.eq('1000');
            });

            it('2nd deposit', async function() {
                const lock_time = 90;
                await vote_escrow.deposit(user_qube_wallet, 1000, lock_time, 2);
                const event = await vote_escrow.getEvent('Deposit');
                const ve_expected = await vote_escrow.calculateVeMint(1000, lock_time);

                expect(event.call_id.toString()).to.be.eq('2');
                expect(event.amount.toString()).to.be.eq('1000');
                expect(event.lock_time.toString()).to.be.eq(lock_time.toString());
                expect(event.ve_amount.toString()).to.be.eq(ve_expected.toString());

                const details = await ve_account.getDetails();
                expect(details._qubeBalance.toString()).to.be.eq('2000');
                expect(details._veQubeBalance.toString()).to.be.eq('1900');
            });
        });


    });
});
