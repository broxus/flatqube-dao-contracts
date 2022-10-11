import {deployUser, deployUsers, sendAllEvers, setupTokenRoot, setupVoteEscrow, sleep} from "../test/utils/common";
import {Address, toNano} from "locklift";
import {Token} from "../test/utils/wrappers/token";
import {VoteEscrow} from "../test/utils/wrappers/vote_ecsrow";
const logger = require("mocha-logger");


async function main() {
    const factory = await locklift.factory.getContractArtifacts('GaugeFactory');
    const gauge = await locklift.factory.getContractArtifacts('Gauge');
    const acc = await locklift.factory.getContractArtifacts('GaugeAccount');
    const ve = await locklift.factory.getContractArtifacts('VoteEscrow');
    const ve_acc = await locklift.factory.getContractArtifacts('VoteEscrowAccount');
    // const test_acc = await locklift.factory.getContractArtifacts('TestGaugeAccount');

    console.log('Gauge Factory:');
    console.log(factory.code);

    console.log('\nGauge:');
    console.log(gauge.code);

    console.log('\nGauge Account:');
    console.log(acc.code);

    // console.log('\nTest Gauge Account:');
    // console.log(test_acc.code);

    console.log('\nVote Escrow:');
    console.log(ve.code);

    console.log('\nVote Escrow Account:');
    console.log(ve_acc.code);
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
