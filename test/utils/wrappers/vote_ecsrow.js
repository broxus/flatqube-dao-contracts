const {
    convertCrystal
} = locklift.utils;
const logger = require("mocha-logger");
const TokenWallet = require("./token_wallet");
const VoteEscrowAccount = require("./ve_account");


class VoteEscrow {
    constructor(ve_contract, ve_owner) {
        this.contract = ve_contract;
        this._owner = ve_owner;
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

    async voteEscrowAccount(account) {
        const addr = account.address === undefined ? account : account.address;
        const acc_addr = await this.contract.call({method: 'getVoteEscrowAccountAddress', params: {user: addr}})
        const ve_acc = await locklift.factory.getContract('VoteEscrowAccount');
        ve_acc.setAddress(acc_addr);
        return new VoteEscrowAccount(ve_acc);
    }

    async getEvent(event_name) {
        return ((await this.contract.getEvents(event_name)).pop()).value;
    }

    async calculateVeMint(amount, lock_time) {
        return await this.contract.call({
            method: 'calculateVeMint',
            params: {
                qube_amount: amount,
                lock_time: lock_time
            }
        });
    }

    async installPlatformCode() {
        const Platform = await locklift.factory.getContract('Platform');
        return await this._owner.runTarget({
            contract: this.contract,
            method: 'installPlatformCode',
            params: {
                code: Platform.code,
                send_gas_to: this._owner.address
            },
            value: convertCrystal(5, 'nano')
        });
    }

    async installOrUpdateVeAccountCode(code) {
        return await this._owner.runTarget({
            contract: this.contract,
            method: 'installOrUpdateVeAccountCode',
            params: {
                code: code,
                send_gas_to: this._owner.address
            },
            value: convertCrystal(5, 'nano')
        });
    }

    // farming, treasury, team
    async setDistributionScheme(scheme, call_id=0) {
        return await this._owner.runTarget({
            contract: this.contract,
            method: 'setDistributionScheme',
            params: {
                _new_scheme: scheme,
                call_id: call_id,
                send_gas_to: this._owner.address
            },
            value: convertCrystal(5, 'nano')
        });
    }

    async setDistribution(distribution, call_id=0) {
        return await this._owner.runTarget({
            contract: this.contract,
            method: 'setDistribution',
            params: {
                _new_distribution: distribution,
                call_id: call_id,
                send_gas_to: this._owner.address
            },
            value: convertCrystal(5, 'nano')
        });
    }

    async setVotingParams(
        epoch_time,
        time_before_voting,
        voting_time,
        gauge_min_votes_ratio,
        gauge_max_votes_ratio,
        gauge_max_downtime,
        max_gauges_per_vote,
        call_id=0
    ) {
        return await this._owner.runTarget({
            contract: this.contract,
            method: 'setVotingParams',
            params: {
                _epoch_time: epoch_time,
                _time_before_voting: time_before_voting,
                _voting_time: voting_time,
                _gauge_min_votes_ratio: gauge_min_votes_ratio,
                _gauge_max_votes_ratio: gauge_max_votes_ratio,
                _gauge_max_downtime: gauge_max_downtime,
                _max_gauges_per_vote: max_gauges_per_vote,
                call_id: call_id,
                send_gas_to: this._owner.address
            },
            value: convertCrystal(5, 'nano')
        });
    }

    async setWhitelistPrice(new_price, call_id=0) {
        return await this._owner.runTarget({
            contract: this.contract,
            method: 'setWhitelistPrice',
            params: {
                new_price: new_price,
                call_id: call_id,
                send_gas_to: this._owner.address
            },
            value: convertCrystal(5, 'nano')
        });
    }

    async setQubeLockTimeLimits(new_min, new_max) {
        return await this._owner.runTarget({
            contract: this.contract,
            method: 'setQubeLockTimeLimits',
            params: {
                new_min: new_min,
                new_max: new_max,
                call_id: 0,
                send_gas_to: this._owner.address
            },
            value: convertCrystal(5, 'nano')
        });
    }

    async initialize(start_time) {
        return await this._owner.runTarget({
            contract: this.contract,
            method: 'initialize',
            params: {
                start_time: start_time,
                send_gas_to: this._owner.address
            },
            value: convertCrystal(5, 'nano')
        });
    }

    async depositPayload(deposit_owner_or_addr, lock_time, call_id=0) {
        const addr = deposit_owner_or_addr.address === undefined ? deposit_owner_or_addr : deposit_owner_or_addr.address;
        return await this.contract.call({
            method: 'encodeDepositPayload',
            params: {
                deposit_owner: addr,
                nonce: 0,
                lock_time: lock_time,
                call_id: call_id
            }
        });
    }

    async whitelistDepositPayload(whitelist_contract_or_addr) {
        const addr = whitelist_contract_or_addr.address === undefined ? whitelist_contract_or_addr : whitelist_contract_or_addr.address;
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

    async deposit(from_wallet, amount, lock_time, call_id, allowed_codes) {
        const payload = await this.depositPayload(from_wallet._owner, lock_time, call_id);
        return await from_wallet.transfer(amount, this.contract, payload, null, allowed_codes);
    }

    async whitelistDeposit(from_wallet, amount, whitelist_addr, allowed_codes) {
        const payload = await this.whitelistDepositPayload(whitelist_addr);
        return await from_wallet.transfer(amount, this.contract, payload, null, allowed_codes);
    }

    async distributionDeposit(from_wallet, amount, allowed_codes) {
        const payload = await this.distributionDepositPayload();
        return await from_wallet.transfer(amount, this.contract, payload, null, allowed_codes);
    }


}


module.exports = VoteEscrow;