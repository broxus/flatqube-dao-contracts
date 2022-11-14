import {VoteEscrow} from "../utils/wrappers/vote_ecsrow";
import {Account} from 'locklift/everscale-client';
import {Token} from "../utils/wrappers/token";

const { expect } = require('chai');
const { setupTokenRoot, setupVoteEscrow, deployUser, deployUsers } = require("../utils/common");


describe("Upgrade Vote Escrow scenarios", async function() {
    this.timeout(3000000);

    let user1: Account;
    let user2: Account;
    let user3: Account;

    let owner: Account;

    let vote_escrow: VoteEscrow;
    let qube_root: Token;

    describe('Setup contracts', async function() {
        it('Deploy users', async function() {
            [user1, user2, user3] = await deployUsers(3, 100);
            owner = await deployUser(1000);
        });

        it('Deploy token', async function() {
            qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
        });

        it('Deploy Vote Escrow', async function() {
            vote_escrow = await setupVoteEscrow({
                owner, qube: qube_root
            });
        })
    });

    describe('Testing upgrade logic', async function() {
        it('Deploy ve accounts for users', async function() {
            try {
                await vote_escrow.deployVeAccount(user1.address);
            } catch (e) {
                console.log(e);
            }
           await vote_escrow.deployVeAccount(user2.address);
        });

        it('Upgrade Vote Escrow', async function() {
            const codes_0 = await vote_escrow.getCodes();
            expect(codes_0._voteEscrowVersion.toString()).to.be.eq('0');

            const new_code = await locklift.factory.getContractArtifacts('TestVoteEscrow');
            await vote_escrow.upgrade(new_code.code);

            const new_contract = await locklift.factory.getDeployedContract('TestVoteEscrow', vote_escrow.address);
            vote_escrow = new VoteEscrow(new_contract, owner);

            const event = await vote_escrow.getEvent('Upgrade') as any;
            expect(event.old_version.toString()).to.be.eq('0');
            expect(event.new_version.toString()).to.be.eq('1');

            const codes_1 = await vote_escrow.getCodes();
            expect(codes_1._voteEscrowVersion.toString()).to.be.eq('1');
        });

        it('Update ve account code', async function() {
            const new_code = await locklift.factory.getContractArtifacts('TestVoteEscrowAccount');
            await locklift.tracing.trace(vote_escrow.installOrUpdateVeAccountCode(new_code.code));
            const event = await vote_escrow.getEvent('VeAccountCodeUpdate') as any;

            expect(event.old_version.toString()).to.be.eq('1');
            expect(event.new_version.toString()).to.be.eq('2');

            const codes = await vote_escrow.getCodes();
            expect(codes._voteEscrowAccountVersion.toString()).to.be.eq('2');
        });

        it('User upgrade his ve account', async function() {
            await vote_escrow.upgradeVeAccount(user1, 1);
            const event = await vote_escrow.getEvent('VoteEscrowAccountUpgrade') as any;

            expect(event.call_id).to.be.eq('1');
            expect(event.user.toString()).to.be.eq(user1.address.toString());
            expect(event.old_version).to.be.eq('1');
            expect(event.new_version).to.be.eq('2');
        });

        it('Admin upgrade user ve account', async function() {
            await vote_escrow.forceUpgradeVeAccounts([user2.address]);

            const event = await vote_escrow.getEvent('VoteEscrowAccountUpgrade') as any;
            expect(event.call_id).to.be.eq('0'); // defaults to 0 when called by admin
            expect(event.user.toString()).to.be.eq(user2.address.toString());
            expect(event.old_version).to.be.eq('1');
            expect(event.new_version).to.be.eq('2');
        });

        it('New user deploy account after code update', async function() {
            await vote_escrow.deployVeAccount(user3.address);
        });
    });
});
