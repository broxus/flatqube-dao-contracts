import {getRandomNonce, toNano, WalletTypes} from "locklift";

const {isValidTonAddress} = require('../test/utils/common');
const fs = require('fs');
const prompts = require('prompts');
const ora = require('ora');


const main = async () => {
    console.log('\x1b[1m', '\n\nSetting Gauge factory params:')
    const response = await prompts([
        {
            type: 'text',
            name: '_owner',
            message: 'Initial gauge factory owner address',
            validate: (value: string) => isValidTonAddress(value) ? true : 'Invalid Everscale address'
        },
        {
            type: 'text',
            name: '_qube',
            message: 'Qube token root address',
            validate: (value: string) => isValidTonAddress(value) ? true : 'Invalid Everscale address'
        },
        {
            type: 'text',
            name: '_vote_escrow',
            message: 'Vote Escrow address',
            validate: (value: string) => isValidTonAddress(value) ? true : 'Invalid Everscale address'
        },
        {
            type: 'number',
            name: '_qube_vesting_period',
            message: 'Default QUBE vesting period (seconds)',
            initial: 120 * 24 * 3600
        },
        {
            type: 'number',
            name: '_qube_vesting_ratio',
            message: 'Default QUBE vesting ratio, number from 1 (0.1%) to 1000 (100%)',
            initial: 1000
        }
    ]);
    console.log('\x1b[1m', '\nSetup complete! ✔');

    const signer = await locklift.keystore.getSigner('0');

    const spinner = ora('Deploying temporary admin...').start();
    const {account: tempAdmin} = await locklift.tracing.trace(locklift.factory.accounts.addNewAccount({
        type: WalletTypes.WalletV3,
        value: toNano(5),
        publicKey: signer?.publicKey as string
    }), {allowedCodes: {compute: [null]}});
    spinner.succeed(`Temporary admin deployed: ${tempAdmin.address}`);

    const Gauge = await locklift.factory.getContractArtifacts('Gauge');
    const GaugeAccount = await locklift.factory.getContractArtifacts('GaugeAccount');
    const Platform = await locklift.factory.getContractArtifacts('Platform');

    spinner.start('Deploying gauge factory...');
    const {contract: factory} = await locklift.tracing.trace(locklift.factory.deployContract({
        contract: 'GaugeFactory',
        initParams: {
            nonce: getRandomNonce(),
            PlatformCode: Platform.code
        },
        publicKey: signer?.publicKey as string,
        constructorParams: {...response, _owner: tempAdmin.address},
        value: locklift.utils.toNano(5),
    }));
    spinner.succeed(`Gauge factory deployed: ${factory.address}`);

    spinner.start('Installing gauge code...');
    await locklift.tracing.trace(factory.methods.installNewGaugeCode({
        gauge_code: Gauge.code, meta: {call_id: 0, nonce: 0, send_gas_to: tempAdmin.address}
    }).send({
        amount: toNano(2),
        from: tempAdmin.address
    }));
    spinner.succeed('Gauge code installed');

    spinner.start('Installing gauge account code...');
    await locklift.tracing.trace(factory.methods.installNewGaugeAccountCode({
        gauge_account_code: GaugeAccount.code, meta: {call_id: 0, nonce: 0, send_gas_to: tempAdmin.address}
    }).send({
        amount: toNano(2),
        from: tempAdmin.address
    }));
    spinner.succeed('Gauge account code installed');

    spinner.start(`Transferring ownership to ${response._owner}...`)
    await locklift.tracing.trace(
        factory.methods.transferOwnership({new_owner: response._owner, meta: {call_id: 0, nonce: 0, send_gas_to: response._owner}})
            .send({from: tempAdmin.address, amount: toNano(1)})
    );
    spinner.succeed(`Owner role transferred to ${response._owner}`);

    console.log('\x1b[1m', `\nOwner (${response._owner}) should accept ownership now!`);
};
main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
