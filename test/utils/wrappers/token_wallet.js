const {
    convertCrystal
} = locklift.utils;


class TokenWallet {
    constructor(wallet_contract, wallet_owner) {
        this.wallet = wallet_contract;
        this._owner = wallet_owner;
        this.address = this.wallet.address;
    }

    static async from_addr(addr, owner) {
        let userTokenWallet = await locklift.factory.getContract(
            'TokenWallet',
            'node_modules/broxus-ton-tokens-contracts/build'
        );

        userTokenWallet.setAddress(addr);
        return new TokenWallet(userTokenWallet, owner);
    }

    async owner() {
        return await this.wallet.call({method: 'owner'});
    }

    async root() {
        return await this.wallet.call({method: 'root'});
    }

    async balance() {
        return await this.wallet.call({method: 'balance'});
    }

    async transfer(amount, receiver_or_addr, payload='', tracing=null, allowed_codes={compute: []}) {
        let addr = receiver_or_addr.address;
        if (addr === undefined) {
            addr = receiver_or_addr;
        }
        let notify = false;
        if (payload) {
            notify = true;
        }
        return await this._owner.runTarget({
            contract: this.wallet,
            method: 'transfer',
            params: {
                amount: amount,
                recipient: addr,
                deployWalletValue: 0,
                remainingGasTo: this._owner.address,
                notify: notify,
                payload: payload
            },
            value: convertCrystal(5, 'nano'),
            tracing: tracing,
            tracing_allowed_codes: allowed_codes
        });
    }
}


module.exports = TokenWallet;