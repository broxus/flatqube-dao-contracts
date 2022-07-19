const {
    toNano
} = locklift.utils;
const logger = require("mocha-logger");
const TokenWallet = require("./token_wallet");
const VoteEscrowAccount = require("./ve_account");
const BigNumber = require('bignumber.js');
const { expect } = require('chai');
const {Dimensions} = require("locklift");


class VoteEscrow {
    constructor(ve_contract, ve_owner) {
        this.contract = ve_contract;
        this._owner = ve_owner;
        this.address = this.contract.address;
        this.token_wallet = null;
    }

    static async from_addr (addr, owner) {
        const ve = await locklift.factory.getDeployedContract('VoteEscrow', addr);
        return new VoteEscrow(ve, owner);
    }

    async tokenWallet() {
        const _details = await this.details();
        this.token_wallet = await TokenWallet.from_addr(_details._qubeWallet, null);
        return this.token_wallet;
    }

    async details() {
        return await this.contract.methods.getDetails({}).call();
    }

    async getCodes() {
        return await this.contract.methods.getCodes({}).call();
    }

    async votingDetails() {
        return await this.contract.methods.getVotingDetails({}).call();
    }

    async getCurrentEpochDetails() {
        return await this.contract.methods.getCurrentEpochDetails({}).call();
    }

    async checkQubeBalance(expected_balance) {
        if (this.token_wallet == null) {
            this.token_wallet = await this.tokenWallet();
        }
        const _details = await this.details();
        const token_balance = await this.token_wallet.balance();
        expect(_details._qubeBalance).to.be.eq(token_balance);
        expect(_details._qubeBalance).to.be.eq(expected_balance.toFixed(0));
    }

    async isGaugeWhitelisted(gauge) {
        const addr = gauge.address === undefined ? gauge : gauge.address;
        return (await this.contract.methods.isGaugeWhitelisted({gauge: addr.toString()}).call()).value0;
    }

    async getGaugeDowntime(gauge) {
        const addr = gauge.address === undefined ? gauge : gauge.address;
        return (await this.contract.methods.getGaugeDowntime({gauge: addr.toString()}).call()).value0;
    }

    arr_to_map(arr) {
        return arr.reduce((map, elem) => {
            map[elem[0]] = elem[1];
            return map;
        }, {});
    }

    async gaugeWhitelist() {
        const res = (await this.contract.methods.gaugeWhitelist({}).call()).gaugeWhitelist;
        return this.arr_to_map(res);
    }

    async currentVotingVotes() {
        const res = (await this.contract.methods.currentVotingVotes({}).call()).currentVotingVotes;
        return this.arr_to_map(res);
    }

    async gaugeDowntimes() {
        const res = (await this.contract.methods.gaugeDowntimes({}).call()).gaugeDowntimes;
        return this.arr_to_map(res);
    }

    async voteEscrowAccount(account) {
        const addr = account.address === undefined ? account : account.address;
        const acc_addr = (await this.contract.methods.getVoteEscrowAccountAddress({answerId: 0, user: addr.toString()}).call()).value0;
        const ve = await locklift.factory.getDeployedContract('VoteEscrowAccount', acc_addr);
        return new VoteEscrowAccount(ve);
    }

    async getEvents(event_name) {
        return (await this.contract.getPastEvents({ filter: (event) => event.event === event_name })).events;
    }

    async getEvent(event_name) {
        return ((await this.getEvents(event_name)).shift()).data;
    }

    async calculateVeMint(amount, lock_time) {
        return (await this.contract.methods.calculateVeMint({qube_amount: amount, lock_time: lock_time}).call()).ve_amount;
    }

    async acceptOwnership(owner) {
        const ve = this.contract;
        return await owner.runTarget(
            {
                contract: ve,
                value: locklift.utils.toNano(5),
            },
            (ve) => ve.methods.acceptOwnership({send_gas_to: owner.address.toString()})
        );
    }

    async installOrUpdateVeAccountCode(code) {
        const ve = this.contract;
        return await this._owner.runTarget(
            {
                contract: ve,
                value: toNano(5)
            },
            (ve) => ve.methods.installOrUpdateVeAccountCode({code: code, send_gas_to: this._owner.address})
        );
    }

    async startVoting(call_id=0) {
        const ve = this.contract;
        return await locklift.tracing.trace(this._owner.runTarget(
            {
                contract: ve,
                value: toNano(5)
            },
            (ve) => ve.methods.startVoting({
                call_id: call_id,
                send_gas_to: this._owner.address.toString()
            })
        ));
    }

    async endVoting(call_id) {
        let gas = new BigNumber((await this.contract.methods.calculateGasForEndVoting({}).call()).min_gas);
        gas = gas.plus(new BigNumber(10**9)).toFixed(0)

        const ve = this.contract;
        return await locklift.tracing.trace(this._owner.runTarget(
            {
                contract: ve,
                value: gas
            },
            (ve) => ve.methods.endVoting({
                call_id: call_id,
                send_gas_to: this._owner.address.toString()
            })
        ));
    }

    async vote(voter, votes, call_id=0) {
        const ve = this.contract;
        return locklift.tracing.trace(voter.runTarget(
            {
                contract: ve,
                value: toNano(5)
            },
            (ve) => ve.methods.vote({
                votes: votes,
                call_id: call_id,
                nonce: 0,
                send_gas_to: voter.address.toString()
            })
        ));
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
            value: toNano(5)
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
            value: toNano(5)
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
            value: toNano(5)
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
            value: toNano(5)
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
            value: toNano(5)
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
            value: toNano(5)
        });
    }

    async deployVeAccount(user) {
        const addr = user.address === undefined ? user : user.address;
        const ve = this.contract;
        return await user.runTarget(
            {
                contract: ve,
                value: toNano(5)
            },
            (ve) => ve.methods.deployVoteEscrowAccount({user: addr.toString()})
        );
    }

    async depositPayload(deposit_owner_or_addr, lock_time, call_id=0) {
        const addr = deposit_owner_or_addr.address === undefined ? deposit_owner_or_addr : deposit_owner_or_addr.address;
        return (await this.contract.methods.encodeDepositPayload({
            deposit_owner: addr.toString(),
            nonce: 0,
            lock_time: lock_time,
            call_id: call_id
        }).call()).payload;
    }

    async whitelistDepositPayload(whitelist_contract_or_addr, call_id=0) {
        const addr = whitelist_contract_or_addr.address === undefined ? whitelist_contract_or_addr : whitelist_contract_or_addr.address;
        return (await this.contract.methods.encodeWhitelistPayload({
            whitelist_addr: addr.toString(),
            nonce: 0,
            call_id: call_id
        }).call()).payload;
    }

    async distributionDepositPayload(call_id=0) {
        return (await this.contract.methods.encodeDistributionPayload({
            nonce: 0,
            call_id: call_id
        }).call()).payload;
    }

    async withdraw(user, call_id=0, allowed_codes) {
        const ve_acc = await this.voteEscrowAccount(user);
        const gas = await ve_acc.contract.call({method: 'calculateMinGas'});
        return await user.runTarget({
            contract: this.contract,
            method: 'withdraw',
            params: {
                nonce: 0,
                call_id: call_id,
                send_gas_to: user.address
            },
            value: gas.plus(new BigNumber(3*10**9)).toFixed(0),
            tracing_allowed_codes: allowed_codes
        });
    }

    async deposit(from_wallet, amount, lock_time, call_id, calc_min_gas=true) {
        let gas = null;
        if (calc_min_gas) {
            const ve_acc = await this.voteEscrowAccount(from_wallet._owner);
            gas = (await ve_acc.contract.methods.calculateMinGas({answerId: 0}).call({})).min_gas;
            gas = new BigNumber(gas);
            gas = gas.plus(new BigNumber(3*10**9)).toFixed(0);
        }
        const payload = await this.depositPayload(from_wallet._owner, lock_time, call_id);
        return await from_wallet.transfer(amount, this.contract, payload, gas);
    }

    async whitelistDeposit(from_wallet, amount, whitelist_addr, call_id=0) {
        const payload = await this.whitelistDepositPayload(whitelist_addr, call_id);
        return await from_wallet.transfer(amount, this.contract, payload, null);
    }

    async distributionDeposit(from_wallet, amount, call_id) {
        const payload = await this.distributionDepositPayload(call_id);
        return await from_wallet.transfer(amount, this.contract, payload, null);
    }

    async upgrade(new_code) {
        const ve = this.contract;
        return await this._owner.runTarget(
            {
                contract: ve,
                value: toNano(5)
            },
            (ve) => ve.methods.upgrade({code: new_code, send_gas_to: this._owner.address})
        );
    }

    async upgradeVeAccount(user, call_id=0) {
        const ve = this.contract;
        return await user.runTarget(
            {
                contract: ve,
                value: toNano(5)
            },
            (ve) => ve.methods.upgradeVeAccount({nonce: 0, call_id: call_id, send_gas_to: user.address})
        );
    }

    async forceUpgradeVeAccounts(users) {
        users = users.map((user) => user.address === undefined ? user : user.address );
        const ve = this.contract;
        return await this._owner.runTarget(
            {
                contract: ve,
                value: toNano(5 * users.length)
            },
            (ve) => ve.methods.forceUpgradeVeAccounts({users: users, send_gas_to: this._owner.address})
        );
    }
}


module.exports = VoteEscrow;