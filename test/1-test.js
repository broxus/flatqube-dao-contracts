const { expect, version} = require('chai');
const logger = require('mocha-logger');
const {
    convertCrystal
} = locklift.utils;

describe("Test optimization cases", async function() {
   this.timeout(10000000);


   it('Testing...', async function() {
       const [keyPair] = await locklift.keys.getKeyPairs();
       let Dummy = await locklift.factory.getContract('Dummy');

       const dummy = await locklift.giver.deployContract({
           contract: Dummy,
           constructorParams: {},
           initParams: {},
           keyPair,
       }, convertCrystal(15, 'nano'));

       logger.log('Testing....');
       const tx1 = await dummy.run({
            method: 'testLocalStorage',
           params: {},
           keyPair: keyPair
       })
       // console.log(tx1)
       console.log(Number(tx1.transaction.compute.gas_fees) / 10**9);

       const tx2 = await dummy.run({
           method: 'testStorage',
           params: {},
           keyPair: keyPair
       })
       console.log(Number(tx2.transaction.compute.gas_fees) / 10**9);

       const tx3 = await dummy.run({
           method: 'testArr',
           params: {},
           keyPair: keyPair
       })
       console.log(Number(tx3.transaction.compute.gas_fees) / 10**9);

       const tx4 = await dummy.run({
           method: 'testStructArr',
           params: {},
           keyPair: keyPair
       })
       console.log(Number(tx4.transaction.compute.gas_fees) / 10**9);

       const tx5 = await dummy.run({
           method: 'testSimpleStruct',
           params: {},
           keyPair: keyPair
       })
       console.log(Number(tx5.transaction.compute.gas_fees) / 10**9);

       const tx6 = await dummy.run({
           method: 'testSimpleStruct2',
           params: {},
           keyPair: keyPair
       })
       console.log(Number(tx6.transaction.compute.gas_fees) / 10**9);
   })
});