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
    let gauges = [];
    let voters = [];

    let big_gauge;

    let current_epoch = 1;
    const pack_size = 35;
    const gauges_per_vote = 15;
    const gauges_count = pack_size * 10;
    const voters_count = Math.ceil(gauges_count / gauges_per_vote); // every voter vote for 15 gauges
    const whitelist_price = 1000000;

    const lock_time = 1000;
    const gauge_deposit = 1000;
    const big_gauge_deposit = 1000000;

    let vote_escrow;

    let qube_root;
    let user_qube_wallet;
    let owner_qube_wallet;
    let voters_qube_wallets = [];

    describe('Setup contracts', async function() {
        it('Deploy users', async function() {
            user = await deployUser(10000000);
            owner = await deployUser(10000000);

            voters = await deployUsers(voters_count, 100);
            gauges = await deployUsers(gauges_count, 100);
            big_gauge = await deployUser(100);
        });

        it('Deploy token', async function() {
            qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
        });

        it('Deploy token wallets + mint', async function() {
            owner_qube_wallet = await qube_root.mint(100000000000, owner);
            user_qube_wallet = await qube_root.mint(100000000000, user);

            await qube_root.deployWallet(big_gauge);

            const chunkSize = 30;
            for (let i = 0; i < gauges_count; i += chunkSize) {
                const _gauges = gauges.slice(i, i + chunkSize);

                await Promise.all(_gauges.map(async (gauge) => {
                    await qube_root.deployWallet(gauge);
                }));
            }

            for (const voter of voters) {
                voters_qube_wallets.push(await qube_root.mint(100000000000, voter));
            }
        });

        it('Deploy Vote Escrow', async function() {
            vote_escrow = await setupVoteEscrow({
                owner, qube:qube_root, whitelist_price: whitelist_price,
                gauge_min_votes_ratio: 0, max_lock: lock_time, voting_time: 10, epoch_time: 20
            });

            const details = await vote_escrow.getCurrentEpochDetails();
            expect(details._currentEpoch.toString()).to.be.eq(current_epoch.toString());
        })
    });

    describe("Checking huge number of gauges on voting works correctly", async function() {
        let total_votes = 0;

        it('Making deposits', async function() {
            await vote_escrow.deposit(user_qube_wallet, big_gauge_deposit, lock_time, 0,  false);

            const mid = Math.floor(voters_count / 2);
            await Promise.all(voters_qube_wallets.slice(0, mid).map(async (qube_wallet, index) => {
                await vote_escrow.deposit(qube_wallet, gauge_deposit, lock_time, index,  false);
            }))

            await Promise.all(voters_qube_wallets.slice(mid).map(async (qube_wallet, index) => {
                await vote_escrow.deposit(qube_wallet, gauge_deposit, lock_time, index,  false);
            }))

            await vote_escrow.checkQubeBalance(gauge_deposit * voters_qube_wallets.length + big_gauge_deposit);
        });

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

            await vote_escrow.whitelistDeposit(owner_qube_wallet, whitelist_price, big_gauge.address);

            const details = await vote_escrow.votingDetails();
            expect(details._gaugesNum.toString()).to.be.eq((gauges_count + 1).toString());
        });

        it('Send QUBEs for distribution', async function() {
            const supply = 6000000;
            await vote_escrow.distributionDeposit(owner_qube_wallet, supply, '1');
            const event = await vote_escrow.getEvent('DistributionSupplyIncrease');

            expect(event.call_id.toString()).to.be.eq('1');
            expect(event.amount.toString()).to.be.eq(supply.toString());

            const details = await vote_escrow.details();
            expect(details._distributionSupply.toString()).to.be.eq(supply.toString());
        });

        it('Voting', async function() {
            await sleep(4000);

            // we have max lock for all deposits => ve ball == deposit
            const vote = Math.floor(gauge_deposit / gauges_per_vote);

            await Promise.all(voters.map(async (voter, idx) => {
                const gauges_to_vote = gauges.slice(idx * gauges_per_vote, idx * gauges_per_vote + gauges_per_vote);
                let votes = {};
                gauges_to_vote.map((gauge) => {
                    votes[gauge.address] = vote;
                    total_votes += vote;
                });
                await vote_escrow.vote(voter, votes);
            }));

            let votes_big = {};
            votes_big[big_gauge.address] = big_gauge_deposit.toString();
            await vote_escrow.vote(user, votes_big);
            total_votes += big_gauge_deposit;

            const details = await vote_escrow.getCurrentEpochDetails();
            expect(details._currentVotingTotalVotes.toString()).to.be.eq(total_votes.toString());

            const votes = await vote_escrow.currentVotingVotes();
            expect(Object.keys(votes).length.toString()).to.be.eq((gauges_count + 1).toString());
            for (const [key, val] of Object.entries(votes)) {
                if (key === big_gauge.address) {
                    expect(val).to.be.eq(big_gauge_deposit.toString());
                } else {
                    expect(val).to.be.eq(vote.toString());
                }
            }
            expect(details._currentVotingTotalVotes.toString()).to.be.eq((vote * gauges_count + big_gauge_deposit).toString());
        });

        it('End voting', async function() {
            await sleep(10 * 1000);
            await vote_escrow.endVoting(1);

            const vote = Math.floor(gauge_deposit / gauges_per_vote);

            const voting_end = await vote_escrow.getEvent('VotingEnd');
            const epoch_distribution = await vote_escrow.getEvent('EpochDistribution');

            const max_votes = Math.floor(total_votes * 0.3); // by default 30% is max
            const valid_votes = vote * gauges_count;
            const exceeded_votes = big_gauge_deposit - max_votes;
            const gauge_votes = Math.floor(vote + (vote / valid_votes) * exceeded_votes);

            expect(Object.keys(voting_end.votes).length.toString()).to.be.eq((gauges_count + 1).toString());
            for (const [key, val] of Object.entries(voting_end.votes)) {
                if (key === big_gauge.address) {
                    expect(val).to.be.eq(max_votes.toString());
                } else {
                    expect(val).to.be.eq(gauge_votes.toString());
                }
            }

            const expected_distribution_1 = Math.floor((gauge_votes / total_votes) * 800000);
            const expected_distribution_2 = Math.floor((max_votes / total_votes) * 800000);

            expect(Object.keys(epoch_distribution.farming_distribution).length.toString()).to.be.eq((gauges_count + 1).toString());
            for (const [key, val] of Object.entries(epoch_distribution.farming_distribution)) {
                if (key === big_gauge.address) {
                    expect(val).to.be.eq(expected_distribution_2.toString());
                } else {
                    expect(val).to.be.eq(expected_distribution_1.toString());
                }
            }
        });
    });
});
