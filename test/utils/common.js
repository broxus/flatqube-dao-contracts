const logger = require("mocha-logger");
const {expect} = require("chai");
const Token = require("./wrappers/token");
const VoteEscrow = require('./wrappers/vote_ecsrow');
const {
    convertCrystal
} = locklift.utils;


const setupTokenRoot = async function(token_name, token_symbol, owner) {
    const RootToken = await locklift.factory.getContract(
        'TokenRoot',
        'node_modules/broxus-ton-tokens-contracts/build'
    );

    const TokenWallet = await locklift.factory.getContract(
        'TokenWallet',
        'node_modules/broxus-ton-tokens-contracts/build'
    );

    const [keyPair] = await locklift.keys.getKeyPairs();

    const _root = await locklift.giver.deployContract({
        contract: RootToken,
        constructorParams: {
            initialSupplyTo: locklift.utils.zeroAddress,
            initialSupply: 0,
            deployWalletValue: 0,
            mintDisabled: false,
            burnByRootDisabled: false,
            burnPaused: false,
            remainingGasTo: owner.address
        },
        initParams: {
            name_: token_name,
            symbol_: token_symbol,
            decimals_: 9,
            rootOwner_: owner.address,
            walletCode_: TokenWallet.code,
            randomNonce_: locklift.utils.getRandomNonce(),
            deployer_: locklift.utils.zeroAddress
        },
        keyPair,
    });
    _root.setKeyPair(keyPair);

    logger.log(`Token root address: ${_root.address}`);

    const name = await _root.call({
        method: 'name',
        params: {}
    });

    expect(name.toString()).to.be.equal(token_name, 'Wrong root name');
    expect((await locklift.ton.getBalance(_root.address)).toNumber()).to.be.above(0, 'Root balance empty');
    return new Token(_root, owner);
}


const setupVoteEscrow = async function(owner, qube) {
    const VoteEscrowContract = await locklift.factory.getContract('VoteEscrow');
    const VeAccount = await locklift.factory.getContract('VoteEscrowAccount');
    const Platform = await locklift.factory.getContract('Platform');
    const [keyPair] = await locklift.keys.getKeyPairs();

    const ve = await locklift.giver.deployContract({
        contract: VoteEscrowContract,
        constructorParams: {
            _owner: owner.address,
            _qube: qube.address
        },
        initParams: {
            deploy_nonce: locklift.utils.getRandomNonce(),
            platformCode: Platform.code,
            veAccountCode: VeAccount.code
        },
        keyPair
    });
    logger.log(`Vote Escrow address: ${ve.address}`);
    return new VoteEscrow(ve, owner);
}


module.exports = {
    setupTokenRoot,
    setupVoteEscrow
}