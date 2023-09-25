import {isNumeric} from "../test/utils/common";
const {isValidTonAddress} = require('../test/utils/common');
const fs = require('fs');
const prompts = require('prompts');
const ora = require('ora');


const main = async () => {
    console.log('\x1b[1m', '\n\nSetting Vote Escrow params:')
    const response = await prompts([
        {
            type: 'text',
            name: 'owner',
            message: 'Initial Vote Escrow owner address',
            validate: (value: string) => isValidTonAddress(value) ? true : 'Invalid Everscale address'
        },
        {
            type: 'text',
            name: 'qube',
            message: 'Qube token root address',
            validate: (value: string) => isValidTonAddress(value) ? true : 'Invalid Everscale address'
        },
        {
            type: 'text',
            name: 'dao',
            message: 'DAO root address',
            validate: (value: string) => isValidTonAddress(value) ? true : 'Invalid Everscale address'
        },
        // {
        //     type: 'number',
        //     name: 'start_offset',
        //     message: 'Time before origin epoch starts (seconds), starting from deploy moment',
        //     initial: 86400
        // },
        {
            type: 'number',
            name: 'min_lock',
            message: 'Qube min time lock (seconds)',
            initial: 7 * 24 * 3600
        },
        {
            type: 'number',
            name: 'max_lock',
            message: 'Qube max time lock (seconds)',
            initial: 4 * 365 * 24 * 3600
        },
        {
            type: 'list',
            name: 'distribution_scheme',
            message: 'Distribution scheme (farming, treasury, team), numbers from 1 (0.01%) to 10000 (100%)',
            initial: '7000, 2000, 1000',
            separator: ','
        },
        {
            type: 'text',
            name: 'distribution',
            message: 'File with distribution schedule',
            initial: 'distribution.txt',
            validate: (value: string) => {
                let data = (fs.readFileSync(value, {encoding: 'utf-8', flag: 'r'})).trim();
                const valid = (data.split('\n')).every((i: string) => isNumeric(i));
                return valid ? valid : 'Invalid file content';
            }
        },
        {
            type: 'number',
            name: 'epoch_time',
            message: 'Epoch length (seconds)',
            initial: 14 * 24 * 3600
        },
        {
            type: 'number',
            name: 'time_before_voting',
            message: 'Offset between epoch start and voting start (seconds)',
            initial: 2 * 24 * 3600
        },
        {
            type: 'number',
            name: 'voting_time',
            message: 'Voting length (seconds)',
            initial: 11 * 24 * 3600
        },
        {
            type: 'number',
            name: 'gauge_min_votes_ratio',
            message: 'Min % gauge should get during voting, from 1 (0.01%) to 10000 (100%)',
            initial: 100
        },
        {
            type: 'number',
            name: 'gauge_max_votes_ratio',
            message: 'Max % gauge can get during voting, from 1 (0.01%) to 10000 (100%)',
            initial: 2500
        },
        {
            type: 'number',
            name: 'gauge_max_downtime',
            message: 'If gauge not being elected than many times, it is removed from vote escrow whitelist',
            initial: 4
        },
        {
            type: 'number',
            name: 'max_gauges_per_vote',
            message: 'Max number of gauges user can vote for during epoch',
            initial: 10
        },
        {
            type: 'number',
            name: 'whitelist_price',
            message: 'Price for whitelisting gauge in vote escrow (in QUBEs)',
            initial: 1000 * 10**9
        }
    ]);
    console.log('\x1b[1m', '\nSetup complete! ✔');

    let data = (fs.readFileSync(response.distribution, {encoding: 'utf-8', flag: 'r'})).trim();
    data = data.split('\n');
    const numeric_data = data.map((i: number) => Number(i));
    const sum = numeric_data.reduce((a: number, b: number) => a + b, 0)
    console.log('\x1b[1m', `\nA total of ${sum / 10**9} QUBEs is going to be distributed over ${data.length} epochs\n`);
    response.distribution = data;

    const signer = await locklift.keystore.getSigner('0');

    const VoteEscrowContract = await locklift.factory.getContractArtifacts('VoteEscrow');
    const Platform = await locklift.factory.getContractArtifacts('Platform');
    const VoteEscrowAccount = await locklift.factory.getContractArtifacts('VoteEscrowAccount');

    const spinner = ora('Deploying vote escrow deployer...').start();
    const {contract: deployer} = await locklift.tracing.trace(locklift.factory.deployContract({
        contract: 'VoteEscrowDeployer',
        initParams: {
            _randomNonce: locklift.utils.getRandomNonce(),
            PlatformCode: Platform.code,
            veAccountCode: VoteEscrowAccount.code,
        },
        publicKey: signer?.publicKey as string,
        constructorParams: {},
        value: locklift.utils.toNano(6.5),
    }));
    spinner.succeed(`Deployer ready: ${deployer.address}`);

    spinner.start('Installing vote escrow code...');
    await locklift.tracing.trace(
        deployer.methods.installVoteEscrowCode({code: VoteEscrowContract.code})
            .sendExternal({publicKey: signer?.publicKey as string})
    );
    spinner.succeed('Vote escrow code installed');

    spinner.start('Deploying vote escrow...');
    const tx = await locklift.tracing.trace(
        deployer.methods.deployVoteEscrow(response).sendExternal({publicKey: signer?.publicKey as string})
    );
    const ve_addr = tx?.output?._vote_escrow;
    spinner.succeed(`Vote escrow deployed and configured: ${ve_addr}`);

    console.log('\x1b[1m', `\nOwner (${response.owner}) should accept ownership now!`);
};
main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
