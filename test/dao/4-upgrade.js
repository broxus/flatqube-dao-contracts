const logger = require('mocha-logger');
const { expect } = require('chai');
const { getRandomNonce } = locklift.utils;
var should = require('chai').should();
const VoteEscrow = require("../utils/wrappers/vote_ecsrow");
const { setupTokenRoot, setupVoteEscrow, deployUser, deployUsers, sleep } = require("../utils/common");


describe("Main Vote Escrow scenarios", async function() {
    this.timeout(3000000);

    let user1;
    let user2;
    let user3;

    let owner;

    let vote_escrow;
    let ve_account1;
    let ve_account2;
    let ve_account3;

    let qube_root;
    let owner_qube_wallet;

    describe('Setup contracts', async function() {
        it('Deploy users', async function() {
            [user1, user2, user3] = await deployUsers(3, 100);
            owner = await deployUser(1000);
        });

        it('Deploy token', async function() {
            qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
        });

        it('Deploy token wallets + mint', async function() {
            await qube_root.mint(1000000, user1);
            await qube_root.mint(1000000, user2);
            await qube_root.mint(1000000, user3);
        });

        it('Deploy Vote Escrow', async function() {
            vote_escrow = await setupVoteEscrow({
                owner, qube: qube_root
            });
        })
    });

    describe('Testing upgrade logic', async function() {
        it('Deploy ve accounts for users', async function() {
           await vote_escrow.deployVeAccount(user1);
           await vote_escrow.deployVeAccount(user2);
        });

        it('Upgrade Vote Escrow', async function() {
            const codes_0 = await vote_escrow.getCodes();
            expect(codes_0._ve_version.toString()).to.be.eq('0');

            const new_contract = await locklift.factory.getContract('TestVoteEscrow');
            await vote_escrow.upgrade(new_contract.code);
            new_contract.setAddress(vote_escrow.address);
            vote_escrow = new VoteEscrow(new_contract, owner);

            const event = await vote_escrow.getEvent('Upgrade');
            expect(event.old_version.toString()).to.be.eq('0');
            expect(event.new_version.toString()).to.be.eq('1');

            const codes_1 = await vote_escrow.getCodes();
            expect(codes_1._ve_version.toString()).to.be.eq('1');
        });

        it('Update ve account code', async function() {
            const new_code = await locklift.factory.getContract('TestVoteEscrowAccount');
            await vote_escrow.installOrUpdateVeAccountCode(new_code.code);
            const event = await vote_escrow.getEvent('VeAccountCodeUpdate');

            expect(event.old_version.toString()).to.be.eq('1');
            expect(event.new_version.toString()).to.be.eq('2');

            const codes = await vote_escrow.getCodes();
            expect(codes._ve_acc_version.toString()).to.be.eq('2');
        });

        it('User upgrade his ve account', async function() {
            await vote_escrow.upgradeVeAccount(user1, 1);
            const event = await vote_escrow.getEvent('VoteEscrowAccountUpgrade');

            expect(event.call_id.toString()).to.be.eq('1');
            expect(event.user.toString()).to.be.eq(user1.address);
            expect(event.old_version.toString()).to.be.eq('1');
            expect(event.new_version.toString()).to.be.eq('2');
        });

        it('Admin upgrade user ve account', async function() {
            await vote_escrow.forceUpgradeVeAccounts([user2]);

            const event = await vote_escrow.getEvent('VoteEscrowAccountUpgrade');
            expect(event.call_id.toString()).to.be.eq('0'); // defaults to 0 when called by admin
            expect(event.user.toString()).to.be.eq(user2.address);
            expect(event.old_version.toString()).to.be.eq('1');
            expect(event.new_version.toString()).to.be.eq('2');
        });

        it('New user deploy account after code update', async function() {
            await vote_escrow.deployVeAccount(user3);
        });
    });
});
