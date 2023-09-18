import {deployUser, deployUsers, sendAllEvers, setupTokenRoot, setupVoteEscrow} from "../test/utils/common";
import {Address, toNano} from "locklift";
const logger = require("mocha-logger");

const token = new Address('0:044ea4b4a7ebad8a24e1dfcec4d06f204e57119d43f4da4272156099d480c337');
const owner = new Address('0:311fe8e7bfeb6a2622aaba02c21569ac1e6f01c81c33f2623e5d8f1a5ba232d7');
const dao = new Address('0:d16cb4205125538a90a2f0fce6e71e949e33f1d6fbde8c263185996f707c3cc9');

async function main() {
    const tmp_owner = await deployUser(5);

    const vote_escrow = await setupVoteEscrow({
        owner: tmp_owner.address,
        qube: token,
        dao: dao,
        max_lock: 4 * 365 * 24 * 3600,
        distribution: [1000000000000, 2000000000000, 3000000000000],
        distribution_scheme: [8000, 1000, 1000],
        epoch_time: 3 * 24 * 3600,
        voting_time: 24 * 3600,
        time_before_voting: 24 * 3600
    });

    const gauges = await deployUsers(3, 1);

    for (const gauge of gauges) {
        await vote_escrow.addToWhitelist(gauge.address);
    }
    logger.log('Added test gauges to whitelist');

    await vote_escrow.transferOwnership({address: owner});
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
