const {Dimensions} = require("locklift");
const {
    convertCrystal
} = locklift.utils;


class TokenWallet {
    constructor(wallet_contract, wallet_owner) {
        this.contract = wallet_contract;
        this._owner = wallet_owner;
        this.address = this.contract.address;
    }

    static async from_addr(addr, owner) {
        let userTokenWallet = await locklift.factory.getContract('TokenWallet');
        const wallet = new locklift.provider.ever.Contract(userTokenWallet.abi, addr);
        return new TokenWallet(wallet, owner);
    }

    async owner() {
        return await this.contract.methods.owner({}).call();
    }

    async root() {
        return await this.contract.methods.root({}).call();
    }

    async balance() {
        return (await this.contract.methods.balance({answerId: 0}).call()).value0;
    }

    async transfer(amount, receiver_or_addr, payload='', value) {
        const addr = receiver_or_addr.address === undefined ? receiver_or_addr : receiver_or_addr.address;
        let notify = payload !== '';

        const token = this.contract;
        return await this._owner.runTarget(
            {
                contract: token,
                value: value || convertCrystal(5, Dimensions.Nano)
            },
            (token) => token.methods.transfer({
                amount: amount,
                recipient: addr.toString(),
                deployWalletValue: 0,
                remainingGasTo: this._owner.address.toString(),
                notify: notify,
                payload: payload
            })
        );
    }
}


module.exports = TokenWallet;
