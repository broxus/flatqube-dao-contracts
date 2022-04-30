const { expect, version} = require('chai');
const logger = require('mocha-logger');
const {
    convertCrystal
} = locklift.utils;


describe("Test max ve acc deposits ", async function() {
    this.timeout(10000000);
    let test;

    it('Deploying tester...', async function() {
        const [keyPair] = await locklift.keys.getKeyPairs();
        let Tester = await locklift.factory.getContract('Tester');

        test = await locklift.giver.deployContract({
            contract: Tester,
            constructorParams: {},
            initParams: {},
            keyPair,
        }, convertCrystal(200, 'nano'));
    });

    it('Saving deposits', async function() {
        // const nums = Array.from({length: 6}, (v, i) => i);
        // for (const i of nums) {
        //     const tx = await test.run({
        //         method: 'create',
        //         params: {amount: 150}
        //     });
        //     console.log(`Running ${i}`)
        //     // console.log(tx);
        // }
        const tx = await test.run({
            method: 'massCreate',
            params: {num: 50}
        });
    });

    it.skip('Check upgrade', async function() {
        let Tester = await locklift.factory.getContract('Tester');
        const tx = await test.run({
            method: 'checkUpgrade',
            params: {new_code: Tester.code}
        })

        console.log(tx);
    });

    it('Check iterations', async function() {
        const tx = await test.run({
            method: 'syncDeposits',
            params: {iterations: 1}
        })

        console.log(tx);

        const tx1 = await test.run({
            method: 'syncDeposits',
            params: {iterations: 200}
        })

        console.log(tx1);
    })

});