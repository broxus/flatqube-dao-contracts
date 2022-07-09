const {
    convertCrystal
} = locklift.utils;
const logger = require("mocha-logger");
const TokenWallet = require("./token_wallet");
const {Dimensions} = require("locklift");


class Token {
    constructor(token_contract, token_owner) {
        this.contract = token_contract;
        this.owner = token_owner;
        this.address = this.contract.address;
    }

    static async from_addr (addr, owner) {
        const rootToken = await locklift.factory.getContract(
            'TokenRoot',
            'node_modules/broxus-ton-tokens-contracts/build'
        );
        rootToken.setAddress(addr);
        return new Token(rootToken, owner);
    }

    async walletAddr(user_or_addr) {
        let addr = user_or_addr.address;
        if (addr === undefined) {
            addr = user_or_addr;
        }
        return (await this.contract.methods.walletOf({ walletOwner: addr.toString(), answerId: 0 }).call()).value0;
    }

    async wallet(user) {
        const wallet_addr = await this.walletAddr(user);
        return await TokenWallet.from_addr(wallet_addr, user);
    }

    async deployWallet(user) {
        const token = this.contract;
        await user.runTarget(
            {
                contract: token,
                value: locklift.utils.convertCrystal(2, Dimensions.Nano),
            },
            (token) => token.methods.deployWallet({
                answerId: 0,
                walletOwner: user.address.toString(),
                deployWalletValue: locklift.utils.convertCrystal(1, Dimensions.Nano),
            })
        );

        const addr = await this.walletAddr(user);
        logger.log(`User token wallet: ${addr.toString()}`);
        return await TokenWallet.from_addr(addr, user);
    }

    async mint(mint_amount, user) {
        const token = this.contract;
        await this.owner.runTarget(
            {
                contract: token,
                value: locklift.utils.convertCrystal(5, Dimensions.Nano),
            },
            (token) => token.methods.mint({
                amount: mint_amount,
                recipient: user.address.toString(),
                deployWalletValue: locklift.utils.convertCrystal(1, Dimensions.Nano),
                remainingGasTo: this.owner.address.toString(),
                notify: false,
                payload: ''
            })
        );

        const walletAddr = await this.walletAddr(user);
        logger.log(`User token wallet: ${walletAddr.toString()}`);
        return await TokenWallet.from_addr(walletAddr, user);
    }
}


module.exports = Token;