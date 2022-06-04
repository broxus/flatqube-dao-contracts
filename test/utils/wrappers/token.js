const {
    convertCrystal
} = locklift.utils;
const logger = require("mocha-logger");
const TokenWallet = require("./token_wallet");


class Token {
    constructor(token_contract, token_owner) {
        this.token = token_contract;
        this.owner = token_owner;
        this.address = this.token.address;
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
        return await this.token.call({
            method: 'walletOf',
            params: { walletOwner: addr }
        });
    }

    async wallet(user) {
        const wallet_addr = await this.walletAddr(user);
        return await TokenWallet.from_addr(wallet_addr, user);
    }

    async deployWallet(user) {
        await user.runTarget({
            contract: this.token,
            method: 'deployWallet',
            params: {
                answerId: 0,
                walletOwner: user.address,
                deployWalletValue: convertCrystal(1, 'nano'),
            },
            value: convertCrystal(2, 'nano'),
        });
        const addr = await this.walletAddr(user);

        logger.log(`User token wallet: ${addr}`);
        return await TokenWallet.from_addr(addr, user);
    }

    async mint(mint_amount, user) {
        await this.owner.runTarget({
            contract: this.token,
            method: 'mint',
            params: {
                amount: mint_amount,
                recipient: user.address,
                deployWalletValue: convertCrystal(1, 'nano'),
                remainingGasTo: this.owner.address,
                notify: false,
                payload: ''
            },
            value: convertCrystal(3, 'nano'),
        });

        const walletAddr = await this.walletAddr(user);

        logger.log(`User token wallet: ${walletAddr}`);
        return await TokenWallet.from_addr(walletAddr, user);
    }
}


module.exports = Token;