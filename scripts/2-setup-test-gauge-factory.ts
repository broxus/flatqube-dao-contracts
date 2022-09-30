import {
    deployUser,
    deployUsers,
    sendAllEvers,
    setupGaugeFactory,
    setupTokenRoot,
    setupVoteEscrow
} from "../test/utils/common";
import {Address, toNano} from "locklift";
const logger = require("mocha-logger");


const acc = '';


async function main() {
    const token_holder = new Address(acc);

    const owner = await deployUser(50);
    const qube = await setupTokenRoot('QUBE_1', 'QUBE_1', owner);

    // @ts-ignore
    await qube.mint('9999999999999999999999999999', {address: token_holder});
    logger.log('Minted qubes');

    const vote_escrow = await setupVoteEscrow({
        owner: owner, qube: qube
    });

    const gauge_factory = await setupGaugeFactory({
        _owner: owner, _qube: qube, _voteEscrow: vote_escrow, _qubeVestingRatio: 0, _qubeVestingPeriod: 0
    });

    logger.log(`Factory: ${gauge_factory.address}, qube: ${qube.address}`);

    await vote_escrow.transferOwnership({address: token_holder});
    await gauge_factory.methods.transferOwnership({
        new_owner: token_holder, meta: {call_id: 0, send_gas_to: token_holder, nonce: 0}
    });

    await sendAllEvers(owner, token_holder);
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
