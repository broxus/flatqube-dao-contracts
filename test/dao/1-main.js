const BigNumber = require('bignumber.js');
const logger = require('mocha-logger');
const { expect } = require('chai');
const { getRandomNonce, toNano } = locklift.utils;
const {deployUser, setupTokenRoot, setupVoteEscrow} = require("../utils/common");

const stringToBytesArray = (dataString) => {
    return Buffer.from(dataString).toString('hex')
};

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
        veOwner = await deployUser(500);
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

        logger.log(`DaoRoot address: ${daoRoot.address}`);
        logger.log(`Installing Proposal code`);
        await locklift.tracing.trace(veOwner.runTarget(
            {
                contract: daoRoot,
                value: CALL_VALUE
            },
            (dao) => dao.methods.updateProposalCode({code: Proposal.code})
        ))

        voteEscrow = await setupVoteEscrow({
            owner: veOwner, qube: qubeToken, dao: daoRoot.address
        });

        await locklift.tracing.trace(veOwner.runTarget(
            {
                contract: daoRoot,
                value: CALL_VALUE
            },
            (dao) => dao.methods.setVoteEscrowRoot({newVoteEscrowRoot: voteEscrow.address})
        ));
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
            const lock_time = 100;

            userAccount0 = await deployUser(100)
            userAccount1 = await deployUser(100);

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
                let callHash = '0x' + (await testTarget.methods.getCallHash({newParam}).call()).value0.toString(16);

                tonActions = [{
                    value: toNano(1),
                    target: testTarget.address,
                    payload: (await testTarget.methods.encodePayload({addr: testTarget.address, callHash}).call()).value0
                }];

                // locklift.tracing.setAllowCodes({compute: [60]})
                // locklift.tracing.allowCodesForAddress(userAccount0.address.toString(), {compute: [60]});
                // const config = {allowedCodes: {contracts: {}}}
                // config.allowedCodes.contracts[userAccount0.address.toString()] = {compute: [60]}
                // locklift.tracing.allowCodesForAddress({address: userAccount0.address.toString(), allowedCodes: {compute: [60]}});
                await locklift.tracing.trace(userAccount0.runTarget(
                    {
                        contract: daoRoot,
                        value: toNano(10 + 0.5 + 0.5 + 1 + 2 + 0.1),
                    },
                    (dao) => dao.methods.propose({
                        answerId: 0,
                        tonActions,
                        ethActions,
                        description
                    })
                ),
                {
                        allowedCodes: {
                            contracts: {
                                [userAccount0.address.toString()]: {compute:[60]}
                            }
                        }
                    }
                );

                const deployedProposals = (await veAccount0.methods.created_proposals({}).call()).created_proposals;
                console.log(deployedProposals);
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
                    const createdProposalLockedVotes = map_proposals[proposalId];
                    logger.log(`Current locked votes for proposal creation: ${createdProposalLockedVotes}`);
                    const lockedVotes = (await veAccount0.methods.lockedTokens({answerId: 0}).call()).value0;
                    const totalVotes = (await veAccount0.methods.calculateVeAverage({}).call())._veQubeBalance;
                    logger.log(`veAccount0 totalVotes: ${totalVotes.toString()}`);
                    logger.log(`veAccount0 availableVotes: ${totalVotes.minus(lockedVotes).toString()}`);
                    expect(createdProposalLockedVotes.toString())
                        .to
                        .equal(expectedThreshold.toString(), 'Wrong threshold');
                    expect(lockedVotes.toString())
                        .to
                        .equal(expectedThreshold.toString(), 'Wrong lockedVotes');
                });
                it('Check TonActions', async function () {
                    const actualTonActions = await proposal.call({method: 'tonActions'});
                    expect(actualTonActions.length)
                        .to
                        .equal(tonActions.length, 'Wrong TonActions amount');
                    for (const [i, actualTonAction] of actualTonActions.entries()) {
                        expect(actualTonAction.value)
                            .to
                            .equal(tonActions[i].value, 'Wrong TonAction value');
                        expect(actualTonAction.target)
                            .to
                            .equal(tonActions[i].target, 'Wrong TonAction target');
                        expect(actualTonAction.payload)
                            .to
                            .equal(tonActions[i].payload, 'Wrong TonAction payload');
                    }
                });
                it('Check EthActions', async function () {
                    const actualEthActions = await proposal.call({method: 'ethActions'});
                    expect(actualEthActions.length)
                        .to
                        .equal(ethActions.length, 'Wrong EthActions amount');
                    for (const [i, actualEthAction] of actualEthActions.entries()) {
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
                    const state = await proposal.call({method: 'getState'});
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
                    castedVoteBefore = (await veAccount0.call({method: 'casted_votes'}))[proposalId];
                    votesToCast = (await veAccount0.call({method: 'getDetails'})).token_balance;
                    forVotesBefore = await proposal.call({method: 'forVotes'});
                    againstVotesBefore = await proposal.call({method: 'againstVotes'});
                    logger.log(`Account0 Cast Vote for Proposal ${proposalId}, amount: ${votesToCast.toString()}, support: True`)
                    logger.log(`DaoAccount0 casted vote Before: ${castedVoteBefore}`)
                    await userAccount0.runTarget({
                        contract: voteEscrow,
                        method: 'castVote',
                        params: {
                            proposal_id: proposalId,
                            support: true
                        },
                        value: CALL_VALUE
                    })
                });
                it('Check votes after', async function () {
                    const forVotes = await proposal.call({method: 'forVotes'});
                    const againstVotes = await proposal.call({method: 'againstVotes'});
                    const castedVote = (await veAccount0.call({method: 'casted_votes'}))[proposalId];
                    logger.log(`Proposal ForVotes: ${forVotes.toString()}`);
                    logger.log(`Proposal againstVotes: ${againstVotes.toString()}`);
                    logger.log(`DaoAccount0 castedVote: ${castedVote}`);
                    expect(forVotesBefore.plus(votesToCast).toString())
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
                    votesToCast = (await veAccount1.call({method: 'getDetails'})).token_balance;
                    forVotesBefore = await proposal.call({method: 'forVotes'});
                    againstVotesBefore = await proposal.call({method: 'againstVotes'});
                    castedVotesBefore = (await veAccount1.call({method: 'casted_votes'}))[proposalId];
                    logger.log(`Account1 Cast Vote for Proposal ${proposalId}, amount: ${votesToCast.toString()}, support: False`);
                    logger.log(`DaoAccount1 castedVotes Before: ${castedVotesBefore}`);
                    await userAccount1.runTarget({
                        contract: voteEscrow,
                        method: 'castVote',
                        params: {
                            proposal_id: proposalId,
                            support: false
                        },
                        value: CALL_VALUE
                    })
                });
                it('Check votes after', async function () {
                    const forVotes = await proposal.call({method: 'forVotes'});
                    const againstVotes = await proposal.call({method: 'againstVotes'});
                    const castedVote = (await veAccount1.call({method: 'casted_votes'}))[proposalId];
                    logger.log(`Proposal ForVotes: ${forVotes.toString()}`);
                    logger.log(`Proposal againstVotes: ${againstVotes.toString()}`);
                    logger.log(`DaoAccount1 castedVote: ${castedVote}`);
                    expect(againstVotesBefore.plus(votesToCast).toString())
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
                    const voteEndTime = await proposal.call({method: 'endTime'});
                    timeLeft = voteEndTime - Math.floor(Date.now() / 1000);
                    logger.log(`Time left to vote end: ${timeLeft}`);
                    await wait((timeLeft + 5) * 1000);
                });
                it('Check status after vote end', async function () {
                    let state = await proposal.call({method: 'getState'});
                    logger.log(`Current state: ${ProposalState[state]}`);
                    expect(ProposalState[state])
                        .to
                        .equal('Succeeded', 'Wrong state');
                });
                it('Check proposal Queue', async function () {
                    logger.log('Queue proposal');
                    await proposal.run({method: 'queue'});
                    state = await proposal.call({method: 'getState'});
                    logger.log(`Current state: ${ProposalState[state]}`);
                    expect(ProposalState[state])
                        .to
                        .equal('Queued', 'Wrong state');
                });
                it('Check proposal Executing', async function () {
                    const targetExecutedBefore = await testTarget.call({method: 'executed'});

                    expect(targetExecutedBefore)
                        .to
                        .equal(false, 'Wrong executed state in target before executing');

                    logger.log('Executing proposal');
                    await proposal.run({method: 'execute'});
                    state = await proposal.call({method: 'getState'});
                    logger.log(`Current state: ${ProposalState[state]}`);
                    expect(ProposalState[state])
                        .to
                        .equal('Executed', 'Wrong state');
                    await userAccount1.runTarget({
                        contract: testTarget,
                        method: 'call',
                        params: {newParam},
                    })
                    await userAccount1.runTarget({
                        contract: testTarget,
                        method: 'call',
                        params: {newParam: 0},
                    })
                    const targetExecuted = await testTarget.call({method: 'executed'});
                    const targetParam = await testTarget.call({method: 'param'});
                    expect(targetExecuted)
                        .to
                        .equal(true, 'Wrong executed state in target after executing');
                    expect(targetParam.toNumber())
                        .to
                        .equal(newParam, 'Wrong target new param after executing');
                });
            })
            describe('Check unlock proposer vote tokens', async function () {
                it('Check votes amount after unlock', async function () {
                    const lockedVotes = await veAccount0.call({method: 'lockedTokens'});
                    const totalVotes = (await veAccount0.call({method: 'getDetails'})).token_balance;
                    logger.log(`DaoAccount0 lockedVotes: ${lockedVotes.toString()}`);
                    logger.log(`DaoAccount0 totalVotes: ${totalVotes.toString()}`);
                    expect(lockedVotes.toNumber())
                        .to
                        .equal(0, 'Wrong locked votes');
                });
            });
            describe('Check unlock casted votes', async function () {
                let castedVotesBefore;
                let canWithdrawBefore;
                before('Unlock casted votes', async function () {
                    castedVotesBefore = Object.keys(await veAccount0.call({method: 'casted_votes'}));
                    logger.log(`Casted votes before unlock: ${JSON.stringify(castedVotesBefore)}`);
                    canWithdrawBefore = await veAccount0.call({method: 'canWithdrawVotes'});
                    logger.log(`Casted withdraw before unlock: ${canWithdrawBefore}`);
                    await userAccount0.runTarget({
                        contract: voteEscrow,
                        method: 'tryUnlockCastedVotes',
                        params: {proposal_ids: castedVotesBefore},
                        value: CALL_VALUE
                    });
                });
                it('Check casted votes before unlock', async function () {
                    expect(canWithdrawBefore)
                        .to
                        .equal(false, 'Wrong canWithdrawVotes before');
                });
                it('Check casted votes after unlock', async function () {
                    const castedVotes = Object.keys(await veAccount0.call({method: 'casted_votes'}));
                    logger.log(`Casted votes after unlock: ${JSON.stringify(castedVotes)}`);
                    const canWithdraw = await veAccount0.call({method: 'canWithdrawVotes'});
                    logger.log(`Casted withdraw after unlock: ${canWithdraw}`);
                    expect(canWithdraw)
                        .to
                        .equal(true, 'Wrong canWithdrawVotes after');
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
                await veOwner.runTarget({
                    contract: daoRoot,
                    method: 'updateProposalConfiguration',
                    params: {newConfig: newConfiguration},
                });
                currentConfiguration = await daoRoot.call({method: 'proposalConfiguration'});
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
                await veOwner.runTarget({
                    contract: daoRoot,
                    method: 'upgrade',
                    params: {code: TestUpgrade.code},
                    value: toNano(3)
                });
                newDaoRoot = TestUpgrade;
                newDaoRoot.setAddress(daoRoot.address);
            })
            it('Check new DAO Root contract', async function () {
                expect(await newDaoRoot.call({method: 'storedData'}))
                    .to
                    .not
                    .equal(null, 'Emtpy data after upgrade');
                expect(await newDaoRoot.call({method: 'isUpgraded'}))
                    .to
                    .equal(true, 'Wrong votingPeriod');
            })
        })
    });
})
