import {Address, getRandomNonce, toNano, WalletTypes} from "locklift";

const ora = require('ora');
const owner = new Address('0:311fe8e7bfeb6a2622aaba02c21569ac1e6f01c81c33f2623e5d8f1a5ba232d7');


const main = async () => {
    const signer = await locklift.keystore.getSigner('0');

    const proposalConfiguration = {
        votingDelay: 120,
        votingPeriod: 300,
        quorumVotes: toNano(100),
        timeLock: 120,
        threshold: toNano(10),
        gracePeriod: 120
    }

    const spinner = ora('Deploying temporary admin...').start();
    const {account: tempAdmin} = await locklift.tracing.trace(locklift.factory.accounts.addNewAccount({
        type: WalletTypes.WalletV3,
        value: toNano(5),
        publicKey: signer?.publicKey as string
    }), {allowedCodes: {compute: [null]}});
    spinner.succeed(`Temporary admin deployed: ${tempAdmin.address}`);

    const PlatformArtifacts = locklift.factory.getContractArtifacts('Platform');
    const ProposalArtifacts = locklift.factory.getContractArtifacts('Proposal');

    spinner.start('Deploying DAO Root...');
    const {contract: daoRoot} = await locklift.tracing.trace(locklift.factory.deployContract({
        contract: 'TestDaoRoot',
        constructorParams: {
            platformCode_: PlatformArtifacts.code,
            proposalConfiguration_: proposalConfiguration,
            admin_: tempAdmin.address
        },
        initParams: {
            _nonce: getRandomNonce()
        },
        value: toNano(5),
        publicKey: signer?.publicKey as string
    }));
    spinner.succeed(`DAO root deployed: ${daoRoot.address}`);

    spinner.start('Installing proposal code...');
    await locklift.tracing.trace(
        daoRoot.methods.updateProposalCode({code: ProposalArtifacts.code})
            .send({from: tempAdmin.address, amount: toNano(1)})
    );
    spinner.succeed('Proposal code installed.');

    spinner.start(`Transferring admin to ${owner}...`)
    await locklift.tracing.trace(
        daoRoot.methods.transferAdmin({newAdmin: owner})
            .send({from: tempAdmin.address, amount: toNano(1)})
    );
    spinner.succeed(`Admin role transferred to ${owner}`);

    console.log('\x1b[1m', `\nAdmin (${owner}) should accept ownership now!\n`)
};
main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
