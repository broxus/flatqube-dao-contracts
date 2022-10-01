import {getRandomNonce, toNano, WalletTypes} from "locklift";
const {isValidTonAddress} = require('../test/utils/common');


const prompts = require('prompts');
const ora = require('ora');


const main = async () => {
    const signer = await locklift.keystore.getSigner('0');

    console.log('\x1b[1m', '\n\nSetting DAO params:')
    const response = await prompts([
        {
            type: 'text',
            name: 'owner',
            message: 'Initial DAO owner',
            validate: (value: string) => isValidTonAddress(value) ? true : 'Invalid Everscale address'
        },
        {
            type: 'number',
            name: 'value',
            message: 'DAO initial balance (in EVERs)',
            initial: 5
        },
        {
            type: 'number',
            name: 'votingDelay',
            message: 'Delay (in seconds) before opening proposal for voting',
            initial: 0
        },
        {
            type: 'number',
            name: 'votingPeriod',
            message: 'Duration (in seconds) how long proposal is open for voting',
            initial: 0
        },
        {
            type: 'number',
            name: 'quorumVotes',
            message: 'The minimum number (satoshi) of votes "for" to accept the proposal',
            initial: 0
        },
        {
            type: 'number',
            name: 'timeLock',
            message: 'Duration (in seconds) between queuing of the proposal and its execution',
            initial: 0
        },
        {
            type: 'number',
            name: 'threshold',
            message: 'Required amount of tokens (satoshi) in stake to create a proposal',
            initial: 0
        },
        {
            type: 'number',
            name: 'gracePeriod',
            message: 'Duration (in seconds) from start of proposal can be executed to its expire',
            initial: 0
        }
    ]);
    console.log('\x1b[1m', '\nSetup complete! ✔\n')

    const proposalConfiguration = {
        votingDelay: response.votingDelay,
        votingPeriod: response.votingPeriod,
        quorumVotes: response.quorumVotes,
        timeLock: response.timeLock,
        threshold: response.threshold,
        gracePeriod: response.gracePeriod
    }

    const spinner = ora('Deploying temporary admin...').start();
    const {account: tempAdmin} = await locklift.tracing.trace(locklift.factory.accounts.addNewAccount({
        type: WalletTypes.WalletV3,
        value: toNano(5),
        publicKey: signer?.publicKey as string
    }), {allowedCodes: {compute: [null]}});
    spinner.succeed(`Temporary admin deployed: ${tempAdmin.address}`);

    const PlatformArtifacts = await locklift.factory.getContractArtifacts('Platform');
    const ProposalArtifacts = await locklift.factory.getContractArtifacts('Proposal');

    spinner.start('Deploying DAO Root...');
    const {contract: daoRoot} = await locklift.tracing.trace(locklift.factory.deployContract({
        contract: 'DaoRoot',
        constructorParams: {
            platformCode_: PlatformArtifacts.code,
            proposalConfiguration_: proposalConfiguration,
            admin_: tempAdmin.address
        },
        initParams: {
            _nonce: getRandomNonce()
        },
        value: toNano(response.value),
        publicKey: signer?.publicKey as string
    }));
    spinner.succeed(`DAO root deployed: ${daoRoot.address}`);

    spinner.start('Installing proposal code...');
    await locklift.tracing.trace(
        daoRoot.methods.updateProposalCode({code: ProposalArtifacts.code})
            .send({from: tempAdmin.address, amount: toNano(1)})
    );
    spinner.succeed('Proposal code installed.');

    spinner.start(`Transferring admin to ${response.owner}...`)
    await locklift.tracing.trace(
        daoRoot.methods.transferAdmin({newAdmin: response.owner})
            .send({from: tempAdmin.address, amount: toNano(1)})
    );
    spinner.succeed(`Admin role transferred to ${response.owner}`);

    console.log('\x1b[1m', `\nAdmin (${response.owner}) should accept ownership now!\n`)
};
main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
