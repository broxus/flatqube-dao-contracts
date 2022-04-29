const {
    convertCrystal
} = locklift.utils;
const logger = require("mocha-logger");
const TokenWallet = require("./token_wallet");


class VoteEscrow {
    constructor(ve_contract, ve_owner) {
        this.contract = ve_contract;
        this.owner = ve_owner;
        this.address = this.contract.address;
    }

    static async from_addr (addr, owner) {
        const veContract = await locklift.factory.getContract('VoteEscrow');
        veContract.setAddress(addr);
        return new VoteEscrow(veContract, owner);
    }

    async details() {
        return await this.contract.call({method: 'getDetails'});
    }

    async depositPayload(deposit_owner_or_addr, lock_time) {
        let addr = deposit_owner_or_addr.address;
        if (addr === undefined) {
            addr = deposit_owner_or_addr;
        }
        return await this.contract.call({
            method: 'encodeDepositPayload',
            params: {
                deposit_owner: addr,
                nonce: 0,
                lock_time: lock_time,
                call_id: 0
            }
        });
    }

    async whitelistDepositPayload(whitelist_contract_or_addr) {
        let addr = whitelist_contract_or_addr.address;
        if (addr === undefined) {
            addr = whitelist_contract_or_addr;
        }
        return await this.contract.call({
            method: 'encodeWhitelistPayload',
            params: {
                deposit_owner: addr,
                nonce: 0,
                call_id: 0
            }
        });
    }

    async distributionDepositPayload() {
        return await this.contract.call({
            method: 'encodeDistributionPayload',
            params: {
                nonce: 0,
                call_id: 0
            }
        });
    }

    async deposit(from_wallet, amount, lock_time, tracing_errors) {
        const payload = await this.depositPayload(from_wallet._owner);
        return await from_wallet.transfer(amount, this.contract, payload, null, tracing_errors);
    }

    async whitelistDeposit(from_wallet, amount, whitelist_addr, tracing_errors) {
        const payload = await this.whitelistDepositPayload(whitelist_addr);
        return await from_wallet.transfer(amount, this.contract, payload, null, tracing_errors);
    }

    async distributionDeposit(from_wallet, amount, tracing_errors) {
        const payload = await this.distributionDepositPayload();
        return await from_wallet.transfer(amount, this.contract, payload, null, tracing_errors);
    }


}


module.exports = VoteEscrow;