import {deployUser, deployUsers, sendAllEvers, setupTokenRoot, setupVoteEscrow} from "../test/utils/common";
import {Address, toNano} from "locklift";
const logger = require("mocha-logger");

const acc1 = '';
const acc2 = '';


async function main() {
    const token_holder = new Address(acc1);
    const token_holder_2 = new Address(acc2);

    const owner = await deployUser(50);
    const qube = await setupTokenRoot('QUBE_1', 'QUBE_1', owner);
    const gauges = await deployUsers(5, 1);

    const owner_qube_wallet = await qube.mint('9999999999999999999999999999', owner);
    // @ts-ignore
    await qube.mint('9999999999999999999999999999', {address: token_holder});
    // @ts-ignore
    await qube.mint('9999999999999999999999999999', {address: token_holder_2});

    logger.log('Minted qubes');

    const vote_escrow = await setupVoteEscrow({
        owner: owner,
        qube: qube,
        max_lock: 4 * 365 * 24 * 3600,
        distribution: [1000000000000, 2000000000000, 3000000000000],
        distribution_scheme: [8000, 1000, 1000],
        epoch_time: 3 * 24 * 3600,
        voting_time: 24 * 3600,
        time_before_voting: 24 * 3600
    });

    await vote_escrow.distributionDeposit(owner_qube_wallet, 9000000000000, 1);
    logger.log('Sent qubes to vote escrow');

    for (const gauge of gauges) {
        await vote_escrow.addToWhitelist(gauge.address);
    }
    logger.log('Added test gauges to whitelist');

    await vote_escrow.contract.methods.transferOwnership({
        new_owner: token_holder, meta: {call_id:0,nonce:0,send_gas_to:token_holder}
    }).send({from: owner.address, amount: toNano(2)});
    logger.log('Transferred ownership');

    await sendAllEvers(owner, token_holder);
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
