const BigNumber = require('bignumber.js');
const logger = require('mocha-logger');
const { expect } = require('chai');
const { getRandomNonce, toNano } = locklift.utils;
const {deployUser, setupTokenRoot, setupVoteEscrow, tryIncreaseTime} = require("../utils/common");

const stringToBytesArray = (dataString) => {
    return Buffer.from(dataString).toString('hex')
};

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

const ProposalState = [
    'Pending',
    'Active',
    'Canceled',
    'Failed',
    'Succeeded',
    'Expired',
    'Queued',
    'Executed'
]

const configAddr = '0:0000000000000000000000000000000000000000000000000000000000001234';

const proposalConfiguration = {
    votingDelay: 0,
    votingPeriod: 20,
    quorumVotes: 1000,
    timeLock: 0,
    threshold: 500,
    gracePeriod: 60 * 60 * 24 * 14
}

const arr_to_map = function(arr) {
    return arr.reduce((map, elem) => {
        map[elem[0]] = elem[1];
        return map;
    }, {});
}


const description = 'proposal-test-1';

const CALL_VALUE = toNano(51);

let voteEscrow;
let veOwner;
let qubeToken;
let daoRoot;

describe('Test DAO in VoteEscrow', async function () {
    before('Setup VoteEscrow', async function () {
        const signer = await locklift.keystore.getSigner('0');
        logger.log(`Deploying veOwner`);
        veOwner = await deployUser(25);
        logger.log(`Deploying qubeToken`);
        qubeToken = await setupTokenRoot('Qube', 'QUBE', veOwner);

        const Platform = await locklift.factory.getContractArtifacts('Platform');

        logger.log(`Deploying DaoRoot`);

        const Proposal = await locklift.factory.getContractArtifacts('Proposal');

        logger.log(`Configuration: ${JSON.stringify(proposalConfiguration, null, 4)}`);
        const {contract} = await locklift.factory.deployContract({
            contract: 'DaoRoot',
            initParams: {
                _nonce: getRandomNonce()
            },
            constructorParams: {
                platformCode_: Platform.code,
                proposalConfiguration_: proposalConfiguration,
                admin_: veOwner.address
            },
            publicKey: signer.publicKey,
            value: toNano(10)
        });
        daoRoot = contract;

        await locklift.tracing.trace(daoRoot.methods.updateEthereumActionEventConfiguration({
            newConfiguration: configAddr,
            newDeployEventValue: toNano(2)
        }).send({from: veOwner.address, amount: toNano(2)}));

        logger.log(`DaoRoot address: ${daoRoot.address}`);
        logger.log(`Installing Proposal code`);
        await locklift.tracing.trace(daoRoot.methods.updateProposalCode({
            code: Proposal.code
        }).send({from: veOwner.address, amount: toNano(2)}));

        voteEscrow = await setupVoteEscrow({
            owner: veOwner, qube: qubeToken, dao: daoRoot.address, max_lock: 1000
        });

        await locklift.tracing.trace(daoRoot.methods.setVoteEscrowRoot({
            newVoteEscrowRoot: voteEscrow.address
        }).send({from: veOwner.address, amount: toNano(2)}));
    })

    describe('DAO', async function () {
        const getVeAccount = async function (_user_address) {
            return (await voteEscrow.voteEscrowAccount(_user_address)).contract;
        }
        const DEPOSIT_VALUE = 100000;
        let userAccount0;
        let userTokenWallet0;
        let veAccount0;
        let userAccount1;
        let userTokenWallet1;
        let veAccount1;
        let proposalId;
        let testTarget;
        before('Setup test accounts', async function () {
            const signer = await locklift.keystore.getSigner('0');
            const lock_time = 1000;

            userAccount0 = await deployUser(25)
            userAccount1 = await deployUser(10);

            userTokenWallet0 = await qubeToken.mint(DEPOSIT_VALUE * 2, userAccount0);
            userTokenWallet1 = await qubeToken.mint(DEPOSIT_VALUE * 2, userAccount1);

            logger.log(`Depositing test tokens`);

            const tx = await voteEscrow.deposit(userTokenWallet0, DEPOSIT_VALUE * 2, lock_time, 1, false);
            // await locklift.tracing.trace(tx, {allowedCodes: {compute: [null]}});

            const tx1 = await voteEscrow.deposit(userTokenWallet1, DEPOSIT_VALUE, lock_time, 2, false);
            // await locklift.tracing.trace(tx1, {allowedCodes: {compute: [null]}});

            veAccount0 = await getVeAccount(userAccount0.address);
            veAccount1 = await getVeAccount(userAccount1.address);
            logger.log(`UserDataContract0: ${veAccount0.address.toString()}`);
            logger.log(`UserDataContract1: ${veAccount1.address.toString()}`);

            const {contract} = await locklift.factory.deployContract({
                contract: 'TestTarget',
                constructorParams: {
                    _daoRoot: daoRoot.address
                },
                initParams: {
                    _nonce: getRandomNonce()
                },
                publicKey: signer.publicKey,
                value: toNano(0.2)
            });
            testTarget = contract;

            logger.log(`TestTarget: ${testTarget.address}`);

        })
        describe('Proposal tests', async function () {
            let proposal;
            let newParam = 16711680;
            let tonActions = [];

            let ethActions = [
                {
                    value: 1,
                    chainId: 2,
                    target: '0x7a250d5630b4cf539739df2c5dacb4c659f2488d',
                    signature: stringToBytesArray('test(uint8 a)'),
                    callData: '000000000000000000000000000000000000000000000000000000000000000f'
                }
            ];
            before('Deploy proposal', async function () {
                let callHash = (await testTarget.methods.getCallHash({newParam}).call()).value0;
                const callHashHex = '0x' + (new BigNumber(callHash)).toString(16)

                tonActions = [{
                    value: toNano(1),
                    target: testTarget.address,
                    payload: (await testTarget.methods.encodePayload({addr: testTarget.address, callHash: callHashHex}).call()).value0
                }];

                // our test-wallet doesn't have dao callback handlers
                locklift.tracing.setAllowedCodesForAddress(userAccount0.address.toString(), {compute: [60]});
                locklift.tracing.setAllowedCodesForAddress(userAccount1.address.toString(), {compute: [60]});

                await locklift.tracing.trace(daoRoot.methods.propose({
                    answerId: 0,
                    tonActions,
                    ethActions,
                    description
                }).send({from: userAccount0.address, amount: toNano(10 + 0.5 + 0.5 + 1 + 2 + 0.1)}))

                const deployedProposals = (await veAccount0.methods.created_proposals({}).call()).created_proposals;
                proposalId = deployedProposals[0][0];

                const expectedProposalAddress = (await daoRoot.methods.expectedProposalAddress({proposalId: proposalId, answerId: 0}).call()).value0;
                proposal = await locklift.factory.getDeployedContract('Proposal', expectedProposalAddress);

                logger.log(`Deployed Proposal #${proposalId}: ${expectedProposalAddress}`);
                logger.log(`TonActions: \n${JSON.stringify(tonActions, null, 4)}`);
                logger.log(`EthActions: \n${JSON.stringify(ethActions, null, 4)}`);
            })

            describe('Check proposal deployed correct', async function () {
                it('Check proposer', async function () {
                    const proposer = (await proposal.methods.getProposer({answerId: 0}).call()).value0;
                    expect(proposer.toString())
                        .to
                        .equal(userAccount0.address.toString(), 'Wrong proposal proposer');
                });
                it('Check locked tokens', async function () {
                    const proposalId = await proposal.methods.id({}).call();
                    const expectedThreshold = proposalConfiguration.threshold.toString();
                    logger.log(`Expected threshold: ${expectedThreshold.toString()}`);
                    const created_proposals = (await veAccount0.methods.created_proposals({}).call()).created_proposals;
                    const map_proposals = arr_to_map(created_proposals);
                    const createdProposalLockedVotes = map_proposals[proposalId.id];
                    logger.log(`Current locked votes for proposal creation: ${createdProposalLockedVotes}`);
                    const lockedVotes = (await veAccount0.methods.lockedTokens({answerId: 0}).call()).value0;
                    const totalVotes = (await veAccount0.methods.calculateVeAverage({}).call())._veQubeBalance;
                    logger.log(`veAccount0 totalVotes: ${totalVotes.toString()}`);
                    logger.log(`veAccount0 availableVotes: ${totalVotes - lockedVotes}`);
                    expect(createdProposalLockedVotes.toString())
                        .to
                        .equal(expectedThreshold.toString(), 'Wrong threshold');
                    expect(lockedVotes.toString())
                        .to
                        .equal(expectedThreshold.toString(), 'Wrong lockedVotes');
                });
                it('Check TonActions', async function () {
                    const actualTonActions = await proposal.methods.tonActions({}).call();
                    expect(actualTonActions.tonActions.length)
                        .to
                        .equal(tonActions.length, 'Wrong TonActions amount');
                    for (const [i, actualTonAction] of actualTonActions.tonActions.entries()) {
                        expect(actualTonAction.value)
                            .to
                            .equal(tonActions[i].value, 'Wrong TonAction value');
                        expect(actualTonAction.target.toString())
                            .to
                            .equal(tonActions[i].target.toString(), 'Wrong TonAction target');
                        expect(actualTonAction.payload)
                            .to
                            .equal(tonActions[i].payload, 'Wrong TonAction payload');
                    }
                });
                it('Check EthActions', async function () {
                    const actualEthActions = await proposal.methods.ethActions({}).call();
                    expect(actualEthActions.ethActions.length)
                        .to
                        .equal(ethActions.length, 'Wrong EthActions amount');
                    for (const [i, actualEthAction] of actualEthActions.ethActions.entries()) {
                        expect(new BigNumber(actualEthAction.value).toString())
                            .to
                            .equal(ethActions[i].value.toString(), 'Wrong EthActions value');
                        expect('0x' + new BigNumber(actualEthAction.target).toString(16))
                            .to
                            .equal(ethActions[i].target, 'Wrong EthActions target');
                        expect(actualEthAction.chainId.toString())
                            .to
                            .equal(ethActions[i].chainId.toString(), 'Wrong EthActions chainId');
                        expect(actualEthAction.signature)
                            .to
                            .equal(ethActions[i].signature, 'Wrong EthActions signature');
                        expect(actualEthAction.callData)
                            .to
                            .equal(ethActions[i].callData, 'Wrong EthActions callData');
                    }
                });
                it('Check State', async function () {
                    const state = (await proposal.methods.getState({answerId: 0}).call()).value0;
                    logger.log(`Actual state: ${ProposalState[state]}`);
                    expect(['Active', 'Pending'])
                        .to
                        .include(ProposalState[state], 'Wrong State');
                })
            })
            describe('Check votes [support=True]', async function () {
                let votesToCast;
                let forVotesBefore;
                let againstVotesBefore;
                let castedVoteBefore;
                before('Make vote support Vote', async function () {
                    castedVoteBefore = (await veAccount0.methods.casted_votes({}).call()).casted_votes;
                    castedVoteBefore = (arr_to_map(castedVoteBefore))[proposalId];
                    votesToCast = (await veAccount0.methods.calculateVeAverage({}).call())._veQubeBalance;

                    forVotesBefore = (await proposal.methods.forVotes({}).call()).forVotes;
                    againstVotesBefore = (await proposal.methods.againstVotes({}).call()).againstVotes;
                    logger.log(`Account0 Cast Vote for Proposal ${proposalId}, amount: ${votesToCast.toString()}, support: True`)
                    logger.log(`DaoAccount0 casted vote Before: ${castedVoteBefore}`)

                    await tryIncreaseTime(1); // make sure status is Active
                    await locklift.tracing.trace(voteEscrow.contract.methods.castVote({
                        proposal_id: proposalId, support: true
                    }).send({from: userAccount0.address, amount: toNano(3)}))
                });

                it('Check votes after', async function () {
                    const forVotes = (await proposal.methods.forVotes({}).call()).forVotes;
                    const againstVotes = (await proposal.methods.againstVotes({}).call()).againstVotes;
                    const tmp = (await veAccount0.methods.casted_votes({}).call()).casted_votes;
                    const castedVote = (arr_to_map(tmp))[proposalId];
                    logger.log(`Proposal ForVotes: ${forVotes.toString()}`);
                    logger.log(`Proposal againstVotes: ${againstVotes.toString()}`);
                    logger.log(`DaoAccount0 castedVote: ${castedVote}`);
                    expect((Number(forVotesBefore) + Number(votesToCast)).toString())
                        .to
                        .equal(forVotes.toString(), 'Wrong forVotes');
                    expect(againstVotes.toString())
                        .to
                        .equal(againstVotesBefore.toString(), 'Wrong againstVotes');
                    expect(castedVoteBefore)
                        .to
                        .equal(undefined, 'Wrong castedVote Before');
                    expect(castedVote)
                        .to
                        .equal(true, 'Wrong castedVote');
                })
            })
            describe('Check votes [support=False]', async function () {
                let votesToCast;
                let forVotesBefore;
                let againstVotesBefore;
                let castedVotesBefore;
                before('Make vote support Vote', async function () {
                    votesToCast = (await veAccount1.methods.calculateVeAverage({}).call())._veQubeBalance;
                    forVotesBefore = (await proposal.methods.forVotes({}).call()).forVotes;
                    againstVotesBefore = (await proposal.methods.againstVotes({}).call()).againstVotes;
                    castedVotesBefore = (await veAccount1.methods.casted_votes({}).call()).casted_votes;
                    castedVotesBefore = (arr_to_map(castedVotesBefore))[proposalId];
                    logger.log(`Account1 Cast Vote for Proposal ${proposalId}, amount: ${votesToCast.toString()}, support: False`);
                    logger.log(`DaoAccount1 castedVotes Before: ${castedVotesBefore}`);

                    await locklift.tracing.trace(voteEscrow.contract.methods.castVote({
                        proposal_id: proposalId, support: false
                    }).send({from: userAccount1.address, amount: toNano(3)}))
                });
                it('Check votes after', async function () {
                    const forVotes = (await proposal.methods.forVotes({}).call()).forVotes;
                    const againstVotes = (await proposal.methods.againstVotes({}).call()).againstVotes;
                    const tmp = (await veAccount1.methods.casted_votes({}).call()).casted_votes;
                    const castedVote = (arr_to_map(tmp))[proposalId];
                    logger.log(`Proposal ForVotes: ${forVotes.toString()}`);
                    logger.log(`Proposal againstVotes: ${againstVotes.toString()}`);
                    logger.log(`DaoAccount1 castedVote: ${castedVote}`);
                    // console.log(againstVotesBefore, votesToCast, againstVotes);
                    expect((Number(againstVotesBefore) + Number(votesToCast)).toString())
                        .to
                        .equal(againstVotes.toString(), 'Wrong againstVotes');
                    expect(forVotes.toString())
                        .to
                        .equal(forVotesBefore.toString(), 'Wrong forVotes');
                    expect(castedVotesBefore)
                        .to
                        .equal(undefined, 'Wrong castedVotes Before');
                    expect(castedVote)
                        .to
                        .equal(false, 'Wrong castedVote');
                })
            })
            describe('Check proposal execution', async function () {
                let timeLeft;
                before('Make vote support Vote', async function () {
                    const voteEndTime = (await proposal.methods.endTime({}).call()).endTime;
                    timeLeft = voteEndTime - Math.floor(Date.now() / 1000);
                    logger.log(`Time left to vote end: ${timeLeft}`);
                    await tryIncreaseTime(timeLeft + 5);
                });
                it('Check status after vote end', async function () {
                    let state = (await proposal.methods.getState({answerId: 0}).call()).value0;
                    logger.log(`Current state: ${ProposalState[state]}`);
                    expect(ProposalState[state])
                        .to
                        .equal('Succeeded', 'Wrong state');
                });
                it('Check proposal Queue', async function () {
                    logger.log('Queue proposal');
                    await locklift.tracing.trace(proposal.methods.queue({}).sendExternal({withoutSignature: true}));
                    let state = (await proposal.methods.getState({answerId: 0}).call()).value0;
                    logger.log(`Current state: ${ProposalState[state]}`);
                    expect(ProposalState[state])
                        .to
                        .equal('Queued', 'Wrong state');
                });
                it('Check proposal Executing', async function () {
                    const targetExecutedBefore = (await testTarget.methods.executed({}).call()).executed;

                    expect(targetExecutedBefore)
                        .to
                        .equal(false, 'Wrong executed state in target before executing');

                    logger.log('Executing proposal');
                    const tx = await locklift.tracing.trace(
                        proposal.methods.execute({}).sendExternal({withoutSignature: true}),
                        {allowedCodes: {contracts: {[configAddr]: {compute: [null]}}}}
                    );
                    let state = (await proposal.methods.getState({answerId: 0}).call()).value0;
                    logger.log(`Current state: ${ProposalState[state]}`);
                    expect(ProposalState[state])
                        .to
                        .equal('Executed', 'Wrong state');

                    await locklift.tracing.trace(testTarget.methods.call({newParam}).send({from: userAccount1.address, amount: toNano(2)}));
                    await locklift.tracing.trace(
                        testTarget.methods.call({newParam: 0}).send({from: userAccount1.address, amount: toNano(2)}),
                        {
                            allowedCodes: {contracts: {[testTarget.address]: {compute: [1201]}}}
                        }
                    );

                    const targetExecuted = (await testTarget.methods.executed({}).call()).executed;
                    const targetParam = (await testTarget.methods.param({}).call()).param;
                    expect(targetExecuted)
                        .to
                        .equal(true, 'Wrong executed state in target after executing');
                    expect(targetParam.toString())
                        .to
                        .equal(newParam.toString(), 'Wrong target new param after executing');
                });
            })
            describe('Check unlock proposer vote tokens', async function () {
                it('Check votes amount after unlock', async function () {
                    const lockedVotes = (await veAccount0.methods.lockedTokens({answerId: 0}).call()).value0;
                    const totalVotes = (await veAccount0.methods.calculateVeAverage({}).call())._veQubeBalance;
                    logger.log(`DaoAccount0 lockedVotes: ${lockedVotes.toString()}`);
                    logger.log(`DaoAccount0 totalVotes: ${totalVotes.toString()}`);
                    expect(lockedVotes.toString())
                        .to
                        .equal('0', 'Wrong locked votes');
                });
            });
            describe('Check unlock casted votes', async function () {
                let castedVotesBefore;

                before('Unlock casted votes', async function () {
                    const castedVotesBefore_arr = (await veAccount0.methods.casted_votes({}).call()).casted_votes;
                    castedVotesBefore = arr_to_map(castedVotesBefore_arr);
                    logger.log(`Casted votes before unlock: ${JSON.stringify(castedVotesBefore)}`);

                    await locklift.tracing.trace(voteEscrow.contract.methods.tryUnlockCastedVotes({
                        proposal_ids: Object.keys(castedVotesBefore)
                    }).send({from: userAccount0.address, amount: toNano(3)}));
                });

                it('Check casted votes after unlock', async function () {
                    const castedVotes_arr = (await veAccount0.methods.casted_votes({}).call()).casted_votes;
                    const castedVotes = Object.keys(arr_to_map(castedVotes_arr));
                    logger.log(`Casted votes after unlock: ${JSON.stringify(castedVotes)}`);
                });
            });
        });
        describe('Test configuration update', async function () {
            let newConfiguration = {
                votingDelay: 60 * 60 * 24 * 2,
                votingPeriod: 60 * 60 * 24 * 3,
                quorumVotes: 500000_000000000,
                timeLock: 60 * 60 * 24 * 2,
                threshold: 100000_000000000,
                gracePeriod: 60 * 60 * 24 * 2
            }
            let currentConfiguration;
            before('Update proposals configuration', async function () {
                await locklift.tracing.trace(
                    daoRoot.methods.updateProposalConfiguration({newConfig: newConfiguration}).send({from: veOwner.address, amount: toNano(2)})
                );

                currentConfiguration = (await daoRoot.methods.proposalConfiguration({}).call()).proposalConfiguration;
            })
            it('Check new configuration', async function () {
                expect(currentConfiguration.votingDelay.toString())
                    .to
                    .equal(newConfiguration.votingDelay.toString(), 'Wrong votingDelay');
                expect(currentConfiguration.votingPeriod.toString())
                    .to
                    .equal(newConfiguration.votingPeriod.toString(), 'Wrong votingPeriod');
                expect(currentConfiguration.quorumVotes.toString())
                    .to
                    .equal(newConfiguration.quorumVotes.toString(), 'Wrong quorumVotes');
                expect(currentConfiguration.timeLock.toString())
                    .to
                    .equal(newConfiguration.timeLock.toString(), 'Wrong timeLock');
                expect(currentConfiguration.threshold.toString())
                    .to
                    .equal(newConfiguration.threshold.toString(), 'Wrong threshold');
                expect(currentConfiguration.gracePeriod.toString())
                    .to
                    .equal(newConfiguration.gracePeriod.toString(), 'Wrong gracePeriod');
            })
        })
        describe('Test DAO root upgrade', async function () {
            let TestUpgrade;
            let newDaoRoot;
            before('Run update function', async function () {
                TestUpgrade = await locklift.factory.getContractArtifacts('TestUpgrade');
                await locklift.tracing.trace(daoRoot.methods.upgrade({code: TestUpgrade.code}).send({from: veOwner.address, amount: toNano(3)}));
                newDaoRoot = await locklift.factory.getDeployedContract('TestUpgrade', daoRoot.address);
            })
            it('Check new DAO Root contract', async function () {
                expect((await newDaoRoot.methods.storedData({}).call()).storedData)
                    .to
                    .not
                    .equal(null, 'Emtpy data after upgrade');
                expect((await newDaoRoot.methods.isUpgraded({}).call()).isUpgraded)
                    .to
                    .equal(true, 'Empty data after upgrade');
            })
        })
    });
})
