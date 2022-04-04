const {
    convertCrystal
} = locklift.utils;

const fs = require('fs')
const prompts = require('prompts');
const decoder = require('locklift/locklift/contract/output-decoder');

const abi = require('../build/Dummy.abi.json');


async function main() {
    const {
        result
    } = (await locklift.ton.client.net.query_collection({
            collection: 'messages',
            filter: {
                id: {
                    eq: "63a74cd971992782ae04fcb5a8fce0dbb13766689db5d7d240ab041e6b2dfd6e"
                }
            },
            result: 'body id src dst',
        }
    ));
    console.log(result);

    const decodedMessage = await this.locklift.ton.client.abi.decode_message_body({
        abi: {
            type: 'Contract',
            value: abi
        },
        body: result[0].body,
        is_internal: false,
    });
    const functionAttributes = abi.functions.find(({ name }) => name === 'testIter');

    // console.log(decodedMessage.value, functionAttributes);

    const res = new decoder(decodedMessage.value, functionAttributes);
    console.log(decodedMessage)
    console.log(res.decodeInput());
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });