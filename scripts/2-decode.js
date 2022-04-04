const {
    convertCrystal
} = locklift.utils;
const { abiContract } = require('@tonclient/core')

const fs = require('fs')
const prompts = require('prompts');
const decoder = require('locklift/locklift/contract/output-decoder');

const abi = require('../build/Dummy.abi.json');


async function main() {
    const inMsg = "63a74cd971992782ae04fcb5a8fce0dbb13766689db5d7d240ab041e6b2dfd6e";
    const params = {
        in_msg: inMsg,
        abi: abiContract("../build/Dummy.abi.json")
    }

    console.log('Query params:', params)

    const res = (await locklift.ton.client.net.query({ "query": "{  transactions(filter:{    id:{ eq:\"28e853aa000251541f34a4ba4d644e205da80894ab302d58374facbdbde7e656\"}  }) {    id,    boc,    status  }}" }));
    console.log(res.result.data.transactions);
    console.log(`🠗\n🠗\n🠗`)

}


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });