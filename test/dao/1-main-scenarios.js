const logger = require('mocha-logger');
const { expect } = require('chai');
const { getRandomNonce } = locklift.utils;
var should = require('chai').should();
const { setupTokenRoot, setupVoteEscrow, deployUser, sleep } = require("../utils/common");


describe("Main Vote Escrow scenarios", async function() {
    this.timeout(3000000);

    let user;
    let owner;

    let current_epoch = 1;

    // just simple wallets here
    let gauges = [];
    let gauge_wallets = {};

    let vote_escrow;
    let ve_account;

    let qube_root;
    let user_qube_wallet;
    let owner_qube_wallet;

    describe('Setup contracts', async function() {
        it('Deploy users', async function() {
            user = await deployUser();
            owner = await deployUser(1000);
            for (const i of [1,2,3,4]) {
                const account = await deployUser();
                account.name = `Gauge ${i}`
                gauges.push(account);
            }
        });

        it('Deploy token', async function() {
           qube_root = await setupTokenRoot('QUBE', 'QUBE', owner);
        });

        it('Deploy token wallets + mint', async function() {
            owner_qube_wallet = await qube_root.mint(1000000000, owner);
            user_qube_wallet = await qube_root.mint(1000000000, user);

            await Promise.all(gauges.map(async (gauge) => {
                const wallet = await qube_root.deployWallet(gauge);
                wallet.name = `${gauge.name} Token Wallet`;
                gauge_wallets[gauge] = wallet;
            }));
        });

        it('Deploy Vote Escrow', async function() {
            vote_escrow = await setupVoteEscrow({
                owner, qube: qube_root
            });

            const details = await vote_escrow.getCurrentEpochDetails();
            expect(details._currentEpoch.toString()).to.be.eq(current_epoch.toString());
        })
    });

    describe('Running scenarios', async function() {
        describe('Making deposits & whitelisting gauges & send distribution QUBEs', async function() {
            it('Making 1st deposit', async function() {
                const lock_time = 100;
                const tx = await vote_escrow.deposit(user_qube_wallet, 1000, lock_time, 1, false);
                await locklift.tracing.trace(tx, {allowedCodes: {compute: [null]}});

                const event = await vote_escrow.getEvent('Deposit');
                const ve_expected = await vote_escrow.calculateVeMint(1000, lock_time);

                expect(event.call_id.toString()).to.be.eq('1');
                expect(event.amount.toString()).to.be.eq('1000');
                expect(event.lock_time.toString()).to.be.eq('100');
                expect(event.ve_amount.toString()).to.be.eq(ve_expected.toString());

                ve_account = await vote_escrow.voteEscrowAccount(user);
                await vote_escrow.checkQubeBalance(1000);

                await sleep(1000);
                const ve_details = await ve_account.calculateVeAverage();
                expect(ve_details._veQubeBalance).to.be.eq('1000');
                expect(ve_details._veQubeAverage).to.be.eq('1000');
            });

            it('Making 2nd deposit', async function() {
                const lock_time = 90;
                await locklift.tracing.trace(vote_escrow.deposit(user_qube_wallet, 1000, lock_time, 2));
                const event = await vote_escrow.getEvent('Deposit');
                const ve_expected = await vote_escrow.calculateVeMint(1000, lock_time);

                expect(event.call_id).to.be.eq('2');
                expect(event.amount).to.be.eq('1000');
                expect(event.lock_time).to.be.eq(lock_time.toString());
                expect(event.ve_amount).to.be.eq(ve_expected.toString());

                await vote_escrow.checkQubeBalance(2000);
                const details = await ve_account.getDetails();
                expect(details._activeDeposits).to.be.eq('2');

                const ve_details = await ve_account.calculateVeAverage();
                expect(ve_details._veQubeBalance).to.be.eq('1900');
            });

            it('Whitelisting gauges', async function() {
                let payments = 0;

                for (const gauge of gauges) {
                    const price = 1000000;
                    const random_id = getRandomNonce();
                    await locklift.tracing.trace(vote_escrow.whitelistDeposit(owner_qube_wallet, price, gauge.address, random_id));
                    const details = await vote_escrow.details();
                    const event = await vote_escrow.getEvent('GaugeWhitelist');
                    payments += price;

                    expect(event.call_id).to.be.eq(random_id.toString());
                    expect(event.gauge.toString()).to.be.eq(gauge.address.toString());

                    expect(details._whitelistPayments.toString()).to.be.eq(payments.toString());
                }

                const whitelisted = await vote_escrow.gaugeWhitelist();
                for (const gauge of gauges) {
                    expect(whitelisted[gauge.address]).to.be.true;
                }

                const expected_bal = 2000 + 1000000 * 4;
                const voting_details = await vote_escrow.votingDetails();
                await vote_escrow.checkQubeBalance(expected_bal);

                expect(voting_details._gaugesNum).to.be.eq('4');
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
        });

        describe('Case #1 - all gauges get equal votes', async function() {
            it('Voting', async function() {
                const ve_balances = await ve_account.calculateVeAverage();

                let votes = {};
                for (const gauge of gauges) {
                    votes[gauge.address.toString()] = Math.floor(ve_balances._veQubeBalance / 4);
                }

                let votes_flat = [];
                for (const [addr, val] of Object.entries(votes)) {
                    votes_flat.push([addr.toString(), val]);
                }
                // sleep a bit so that voting time starts
                await sleep(4000);
                await vote_escrow.vote(user, votes_flat, 1);

                const start_event = await vote_escrow.getEvent('VotingStart');
                const vote_event = await vote_escrow.getEvent('Vote');

                expect(start_event.call_id).to.be.eq('1');
                expect(vote_event.call_id).to.be.eq('1');

                const epoch = await vote_escrow.getCurrentEpochDetails();
                expect(epoch._currentVotingTotalVotes).to.be.eq(ve_balances._veQubeBalance);

                const all_votes = await vote_escrow.currentVotingVotes();
                for (const gauge of gauges) {
                    expect(all_votes[gauge.address.toString()].toString()).to.be.eq(votes[gauge.address.toString()].toString());
                }
            });

            it('End voting', async function() {
                await sleep(5000);

                const details = await vote_escrow.details();
                let supply = details._distributionSupply;

                await vote_escrow.endVoting(1);
                current_epoch += 1;

                const ve_balances = await ve_account.calculateVeAverage();

                const voting_end = await vote_escrow.getEvent('VotingEnd');
                const epoch_distribution = await vote_escrow.getEvent('EpochDistribution');

                const votes_map = vote_escrow.arr_to_map(voting_end.votes);

                expect(voting_end.call_id).to.be.eq('1');
                expect(voting_end.new_epoch).to.be.eq(current_epoch.toString());
                expect(voting_end.treasury_votes).to.be.eq('0');
                expect(voting_end.total_votes).to.be.eq(ve_balances._veQubeBalance);
                for (const gauge of gauges) {
                    const expected = ve_balances._veQubeBalance / 4;
                    expect(votes_map[gauge.address.toString()]).to.be.eq(expected.toString());
                }

                expect(epoch_distribution.call_id).to.be.eq('1');
                expect(epoch_distribution.epoch_num).to.be.eq(current_epoch.toString());

                const distribution_map = vote_escrow.arr_to_map(epoch_distribution.farming_distribution);

                const expected_distribution = 200000;
                for (const gauge of gauges) {
                    expect(distribution_map[gauge.address]).to.be.eq(expected_distribution.toFixed(0));
                }

                // team and treasury are the same in default setup
                const expected_team = 100000;
                expect(epoch_distribution.team_tokens).to.be.eq(expected_team.toFixed(0));
                expect(epoch_distribution.treasury_tokens).to.be.eq(expected_team.toFixed(0));

                const expected_supply = supply - 100000 * 2 - 200000 * 4;

                const details_new = await vote_escrow.details();
                let new_supply = details_new._distributionSupply;

                expect(new_supply.toString()).to.be.eq(expected_supply.toString());
            });
        });

        describe('Case #2 - excess, low and valid vote counts', async function() {
            let votes = {};
            let total_votes;

            it('Voting', async function() {
                const ve_balances = await ve_account.calculateVeAverage();

                // default max for 1 gauge is 30%, min is 2%
                votes[gauges[0].address] = Math.floor(ve_balances._veQubeBalance * 0.54); // 54% => 30%
                votes[gauges[1].address] = Math.floor(ve_balances._veQubeBalance * 0.35); // 35% => 30%
                votes[gauges[2].address] = Math.floor(ve_balances._veQubeBalance * 0.1); // 10% => 30% (+20%: 24% + 5% + 1% - 10% overflow)
                votes[gauges[3].address] = Math.floor(ve_balances._veQubeBalance * 0.01); // 1% => 0%

                total_votes = Object.values(votes).reduce((prev,next) => prev + next, 0);
                // sleep a bit so that voting time starts

                let votes_flat = [];
                for (const [addr, val] of Object.entries(votes)) {
                    votes_flat.push([addr.toString(), val]);
                }

                await sleep(4000);
                await vote_escrow.vote(user, votes_flat, 2);

                const start_event = await vote_escrow.getEvent('VotingStart');
                const vote_event = await vote_escrow.getEvent('Vote');

                expect(start_event.call_id).to.be.eq('2');
                expect(vote_event.call_id).to.be.eq('2');

                const epoch = await vote_escrow.getCurrentEpochDetails();
                expect(epoch._currentVotingTotalVotes).to.be.eq(total_votes.toString());

                const all_votes = await vote_escrow.currentVotingVotes();
                for (const gauge of gauges) {
                    expect(all_votes[gauge.address].toString()).to.be.eq(votes[gauge.address].toString());
                }
            });

            it('End voting', async function() {
                await sleep(5000);

                const details = await vote_escrow.details();
                let supply = details._distributionSupply;

                await vote_escrow.endVoting(2);
                current_epoch += 1;

                const downtime = await vote_escrow.getGaugeDowntime(gauges[3].address);
                expect(downtime.toString()).to.be.eq('1');

                const voting_end = await vote_escrow.getEvent('VotingEnd');
                const epoch_distribution = await vote_escrow.getEvent('EpochDistribution');

                const max_votes = Math.floor(total_votes * 0.3); // by default 30% is max
                let exceeded_votes = Math.floor(total_votes * 0.3); // 24% + 5% + 1%

                let treasury_votes = (votes[gauges[2].address] + exceeded_votes) - max_votes;
                let treasury_bonus = Math.floor(treasury_votes * Math.floor(1000000 * 0.8) / total_votes);

                const votes_map = vote_escrow.arr_to_map(voting_end.votes);

                expect(votes_map[gauges[0].address]).to.be.eq(max_votes.toString());
                expect(votes_map[gauges[1].address]).to.be.eq(max_votes.toString());
                expect(votes_map[gauges[2].address]).to.be.eq(max_votes.toString());
                should.not.exist(votes_map[gauges[3].address]);

                expect(voting_end.call_id).to.be.eq('2');
                expect(voting_end.new_epoch).to.be.eq(current_epoch.toString());
                expect(voting_end.total_votes).to.be.eq(total_votes.toString());
                expect(voting_end.treasury_votes).to.be.eq(treasury_votes.toString());

                expect(epoch_distribution.call_id).to.be.eq('2');
                expect(epoch_distribution.epoch_num).to.be.eq(current_epoch.toString());

                const distribution_map = vote_escrow.arr_to_map(epoch_distribution.farming_distribution);

                const share = max_votes / total_votes;
                const max_distribution = Math.floor(Math.floor(1000000 * 0.8) * share)
                expect(distribution_map[gauges[0].address]).to.be.eq(max_distribution.toFixed(0));
                expect(distribution_map[gauges[1].address]).to.be.eq(max_distribution.toFixed(0));
                expect(distribution_map[gauges[2].address]).to.be.eq(max_distribution.toFixed(0));
                should.not.exist(distribution_map[gauges[3].address]);

                const expected_team = 100000;
                const expected_treasury = 100000 + treasury_bonus;
                expect(epoch_distribution.team_tokens).to.be.eq(expected_team.toFixed(0));
                expect(epoch_distribution.treasury_tokens).to.be.eq(expected_treasury.toFixed(0));

                const expected_supply = supply - max_distribution * 3 - expected_team - expected_treasury;

                const details_new = await vote_escrow.details();
                let new_supply = details_new._distributionSupply;

                expect(new_supply).to.be.eq(expected_supply.toString());
            });
        });

        describe('Case #3 - gauge removed from whitelist because of downtime', async function() {
            let votes = {};
            let total_votes;

            // just copying previous round logic
            it('Voting', async function() {
                const ve_balances = await ve_account.calculateVeAverage();

                // default max for 1 gauge is 30%, min is 2%
                votes[gauges[0].address] = Math.floor(ve_balances._veQubeBalance * 0.54); // 54% => 30%
                votes[gauges[1].address] = Math.floor(ve_balances._veQubeBalance * 0.35); // 35% => 30%
                votes[gauges[2].address] = Math.floor(ve_balances._veQubeBalance * 0.1); // 10% => 30% (+20%: 24% + 5% + 1% - 10% overflow)
                votes[gauges[3].address] = Math.floor(ve_balances._veQubeBalance * 0.01); // 1% => 0%

                let votes_flat = [];
                for (const [addr, val] of Object.entries(votes)) {
                    votes_flat.push([addr.toString(), val]);
                }

                total_votes = Object.values(votes).reduce((prev,next) => prev + next, 0);
                // sleep a bit so that voting time starts
                await sleep(4000);
                await vote_escrow.vote(user, votes_flat, 3);

                const start_event = await vote_escrow.getEvent('VotingStart');
                const vote_event = await vote_escrow.getEvent('Vote');

                expect(start_event.call_id).to.be.eq('3');
                expect(vote_event.call_id).to.be.eq('3');

                const epoch = await vote_escrow.getCurrentEpochDetails();
                expect(epoch._currentVotingTotalVotes).to.be.eq(total_votes.toString());

                const all_votes = await vote_escrow.currentVotingVotes();
                for (const gauge of gauges) {
                    expect(all_votes[gauge.address.toString()].toString()).to.be.eq(votes[gauge.address.toString()].toString());
                }
            });

            it('End voting', async function() {
                await sleep(5000);

                const details = await vote_escrow.details();
                let supply = details._distributionSupply;

                await vote_escrow.endVoting(3);
                current_epoch += 1;

                const downtime = await vote_escrow.getGaugeDowntime(gauges[3]);
                expect(downtime).to.be.eq('0');

                const whitelisted = await vote_escrow.isGaugeWhitelisted(gauges[3]);
                expect(whitelisted).to.be.false;

                const voting_end = await vote_escrow.getEvent('VotingEnd');
                const epoch_distribution = await vote_escrow.getEvent('EpochDistribution');
                const gauge_removal = await vote_escrow.getEvent('GaugeRemoveWhitelist');

                expect(gauge_removal.call_id).to.be.eq('3');
                expect(gauge_removal.gauge.toString()).to.be.eq(gauges[3].address.toString());

                const max_votes = Math.floor(total_votes * 0.3); // by default 30% is max
                let exceeded_votes = Math.floor(total_votes * 0.3); // 24% + 5% + 1%

                let treasury_votes = (votes[gauges[2].address] + exceeded_votes) - max_votes;
                let treasury_bonus = Math.floor(treasury_votes * Math.floor(1000000 * 0.8) / total_votes);

                const votes_map = vote_escrow.arr_to_map(voting_end.votes);

                expect(votes_map[gauges[0].address]).to.be.eq(max_votes.toString());
                expect(votes_map[gauges[1].address]).to.be.eq(max_votes.toString());
                expect(votes_map[gauges[2].address]).to.be.eq(max_votes.toString());
                should.not.exist(votes_map[gauges[3].address]);

                expect(voting_end.call_id).to.be.eq('3');
                expect(voting_end.new_epoch).to.be.eq(current_epoch.toString());
                expect(voting_end.total_votes).to.be.eq(total_votes.toString());
                expect(voting_end.treasury_votes).to.be.eq(treasury_votes.toString());

                expect(epoch_distribution.call_id).to.be.eq('3');
                expect(epoch_distribution.epoch_num).to.be.eq(current_epoch.toString());

                const share = max_votes / total_votes;
                const max_distribution = Math.floor(Math.floor(1000000 * 0.8) * share)
                const distribution_map = vote_escrow.arr_to_map(epoch_distribution.farming_distribution);

                expect(distribution_map[gauges[0].address]).to.be.eq(max_distribution.toFixed(0));
                expect(distribution_map[gauges[1].address]).to.be.eq(max_distribution.toFixed(0));
                expect(distribution_map[gauges[2].address]).to.be.eq(max_distribution.toFixed(0));
                should.not.exist(distribution_map[gauges[3].address]);

                const expected_team = 100000;
                const expected_treasury = 100000 + treasury_bonus;
                expect(epoch_distribution.team_tokens).to.be.eq(expected_team.toFixed(0));
                expect(epoch_distribution.treasury_tokens).to.be.eq(expected_treasury.toFixed(0));

                const expected_supply = supply - max_distribution * 3 - expected_team - expected_treasury;

                const details_new = await vote_escrow.details();
                let new_supply = details_new._distributionSupply;

                expect(new_supply).to.be.eq(expected_supply.toString());
            });
        });

        describe('Case #4 - all votes are low/excess', async function() {
            let votes = {};
            let total_votes;

            it('Voting', async function() {
                const ve_balances = await ve_account.calculateVeAverage();

                // default max for 1 gauge is 30%, min is 2%
                votes[gauges[0].address] = Math.floor(ve_balances._veQubeBalance * 0.50); // 50% => 30%
                votes[gauges[1].address] = Math.floor(ve_balances._veQubeBalance * 0.49); // 49% => 30%
                votes[gauges[2].address] = Math.floor(ve_balances._veQubeBalance * 0.01); // 1% => 0%

                total_votes = Object.values(votes).reduce((prev,next) => prev + next, 0);

                let votes_flat = [];
                for (const [addr, val] of Object.entries(votes)) {
                    votes_flat.push([addr.toString(), val]);
                }
                // sleep a bit so that voting time starts
                await sleep(4000);
                await vote_escrow.vote(user, votes_flat, 4);

                const start_event = await vote_escrow.getEvent('VotingStart');
                const vote_event = await vote_escrow.getEvent('Vote');

                expect(start_event.call_id.toString()).to.be.eq('4');
                expect(vote_event.call_id.toString()).to.be.eq('4');

                const epoch = await vote_escrow.getCurrentEpochDetails();
                expect(epoch._currentVotingTotalVotes.toString()).to.be.eq(total_votes.toString());

                const all_votes = await vote_escrow.currentVotingVotes();
                expect(all_votes[gauges[0].address].toString()).to.be.eq(votes[gauges[0].address].toString());
                expect(all_votes[gauges[1].address].toString()).to.be.eq(votes[gauges[1].address].toString());
                expect(all_votes[gauges[2].address].toString()).to.be.eq(votes[gauges[2].address].toString());
            });

            it('End voting', async function() {
                await sleep(5000);

                const details = await vote_escrow.details();
                let supply = details._distributionSupply;

                await vote_escrow.endVoting(4);
                current_epoch += 1;

                const voting_end = await vote_escrow.getEvent('VotingEnd');
                const epoch_distribution = await vote_escrow.getEvent('EpochDistribution');

                const exceeded_votes = Math.floor(total_votes * 0.4);
                const max_votes = Math.floor(total_votes * 0.3); // by default 30% is max

                let treasury_bonus = Math.floor(exceeded_votes * Math.floor(1000000 * 0.8) / total_votes);

                const votes_map = vote_escrow.arr_to_map(voting_end.votes);

                expect(votes_map[gauges[0].address].toString()).to.be.eq(max_votes.toString());
                expect(votes_map[gauges[1].address].toString()).to.be.eq(max_votes.toString());
                should.not.exist(votes_map[gauges[2].address]);
                should.not.exist(votes_map[gauges[3].address]);

                expect(voting_end.call_id).to.be.eq('4');
                expect(voting_end.new_epoch).to.be.eq(current_epoch.toString());
                expect(voting_end.total_votes).to.be.eq(total_votes.toString());
                expect(voting_end.treasury_votes).to.be.eq(exceeded_votes.toString());

                expect(epoch_distribution.call_id).to.be.eq('4');
                expect(epoch_distribution.epoch_num).to.be.eq(current_epoch.toString());

                const share = max_votes / total_votes;
                const max_distribution = Math.floor(Math.floor(1000000 * 0.8) * share);
                const distribution_map = vote_escrow.arr_to_map(epoch_distribution.farming_distribution);

                expect(distribution_map[gauges[0].address]).to.be.eq(max_distribution.toFixed(0));
                expect(distribution_map[gauges[1].address]).to.be.eq(max_distribution.toFixed(0));
                should.not.exist(distribution_map[gauges[2].address]);
                should.not.exist(distribution_map[gauges[3].address]);

                const expected_team = 100000;
                const expected_treasury = 100000 + treasury_bonus;
                expect(epoch_distribution.team_tokens).to.be.eq(expected_team.toFixed(0));
                expect(epoch_distribution.treasury_tokens).to.be.eq(expected_treasury.toFixed(0));

                const expected_supply = supply - max_distribution * 2 - expected_team - expected_treasury;

                const details_new = await vote_escrow.details();
                let new_supply = details_new._distributionSupply;

                expect(new_supply).to.be.eq(expected_supply.toString());
            });

        });

        describe('Case #5 - no one voted', async function() {
            it('Start voting', async function() {
                // sleep a bit so that voting time starts
                await sleep(4000);
                await vote_escrow.startVoting(5);

                const start_event = await vote_escrow.getEvent('VotingStart');
                expect(start_event.call_id).to.be.eq('5');
            });

            it('End voting', async function() {
                await sleep(5000);

                const details = await vote_escrow.details();
                let supply = details._distributionSupply;

                await vote_escrow.endVoting(5);
                current_epoch += 1;

                const voting_end = await vote_escrow.getEvent('VotingEnd');
                const epoch_distribution = await vote_escrow.getEvent('EpochDistribution');

                let treasury_bonus = Math.floor(1000000 * 0.8);

                expect(voting_end.call_id).to.be.eq('5');
                expect(voting_end.new_epoch).to.be.eq(current_epoch.toString());
                expect(voting_end.total_votes).to.be.eq('0');
                expect(voting_end.treasury_votes).to.be.eq('0');

                expect(epoch_distribution.call_id).to.be.eq('5');
                expect(epoch_distribution.epoch_num).to.be.eq(current_epoch.toString());

                const expected_team = 100000;
                const expected_treasury = 100000 + treasury_bonus;
                expect(epoch_distribution.team_tokens).to.be.eq(expected_team.toFixed(0));
                expect(epoch_distribution.treasury_tokens).to.be.eq(expected_treasury.toFixed(0));

                const expected_supply = supply - expected_team - expected_treasury;

                const details_new = await vote_escrow.details();
                let new_supply = details_new._distributionSupply;

                expect(new_supply).to.be.eq(expected_supply.toString());
            });
        })
    });
});
