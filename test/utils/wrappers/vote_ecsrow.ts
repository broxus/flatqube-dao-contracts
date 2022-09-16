import {use} from "chai";

const {
    toNano
} = locklift.utils;
const {expect} = require('chai');
import {Account} from 'locklift/everscale-standalone-client'
const Bignumber = require("bignumber.js");
import {FactorySource} from "../../../build/factorySource";
import {Address, Contract} from "locklift";
import {TokenWallet} from "./token_wallet";
import {VoteEscrowAccount} from "./ve_account";



export class VoteEscrow {
    public contract: Contract<FactorySource["TestVoteEscrow"]>;
    public _owner: Account;
    public address: Address;
    public token_wallet: TokenWallet | null;

    constructor(ve_contract: Contract<FactorySource["TestVoteEscrow"]>, ve_owner: Account) {
        this.contract = ve_contract;
        this._owner = ve_owner;
        this.address = this.contract.address;
        this.token_wallet = null;
    }

    static async from_addr(addr: Address, owner: Account) {
        const ve = await locklift.factory.getDeployedContract('TestVoteEscrow', addr);
        return new VoteEscrow(ve, owner);
    }

    async tokenWallet() {
        const _details = await this.details();
        this.token_wallet = await TokenWallet.from_addr(_details._qubeWallet, null);
        return this.token_wallet;
    }

    async details() {
        return await this.contract.methods.getDetails().call();
    }

    async getCodes() {
        return await this.contract.methods.getCodes().call();
    }

    async votingDetails() {
        return await this.contract.methods.getVotingDetails().call();
    }

    async getCurrentEpochDetails() {
        return await this.contract.methods.getCurrentEpochDetails().call();
    }

    async sendQubesToGauge(gauge: Address, amount: number, round_len: number, round_start: number) {
        return await this.contract.methods.sendQubesToGauge({
            gauge: gauge, qube_amount: amount, round_len: round_len, round_start: round_start
        }).send({
            amount: toNano(1),
            from: this._owner.address
        });
    }

    async checkQubeBalance(expected_balance: number) {
        if (this.token_wallet == null) {
            this.token_wallet = await this.tokenWallet();
        }
        const _details = await this.details();
        const token_balance = await this.token_wallet.balance();
        expect(_details._qubeBalance).to.be.eq(token_balance);
        expect(_details._qubeBalance).to.be.eq(expected_balance.toFixed(0));
    }

    async isGaugeWhitelisted(gauge: Address) {
        return (await this.contract.methods.isGaugeWhitelisted({gauge: gauge}).call()).value0;
    }

    async getGaugeDowntime(gauge: Address) {
        return (await this.contract.methods.getGaugeDowntime({gauge: gauge}).call()).value0;
    }

    arr_to_map(arr: any[]) {
        return arr.reduce((map: Object, elem: any[]) => {
            // @ts-ignore
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

    async voteEscrowAccount(user: Address) {
        const acc_addr = (await this.contract.methods.getVoteEscrowAccountAddress({
            answerId: 0,
            user: user
        }).call()).value0;
        const ve = await locklift.factory.getDeployedContract('VoteEscrowAccount', acc_addr);
        return new VoteEscrowAccount(ve);
    }

    async getEvents(event_name: string) {
        return (await this.contract.getPastEvents({filter: (event) => event.event === event_name})).events;
    }

    async getEvent(event_name: string) {
        const last_event = (await this.getEvents(event_name)).shift();
        if (last_event) {
            return last_event.data;
        }
        return null;
    }

    async calculateVeMint(amount: number | string, lock_time: number | string) {
        return (await this.contract.methods.calculateVeMint({
            qube_amount: amount.toString(), lock_time: lock_time.toString()
        }).call()).ve_amount;
    }

    async transferOwnership(new_owner: { address: Address }) {
        return this.contract.methods.transferOwnership({
            new_owner: new_owner.address, meta: {call_id: 0, nonce: 0, send_gas_to: this._owner.address}
        }).send({
            amount: toNano(5),
            from: this._owner.address
        });
    }

    async acceptOwnership(owner: Account) {
        return this.contract.methods.acceptOwnership({meta: {call_id: 0, nonce: 0, send_gas_to: owner.address}}).send({
            amount: toNano(5),
            from: owner.address
        });
    }

    async installOrUpdateVeAccountCode(code: string) {
        return await this.contract.methods.installOrUpdateVeAccountCode(
            {code: code, meta: {call_id: 0, nonce: 0, send_gas_to: this._owner.address}}
        ).send({
            from: this._owner.address,
            amount: toNano(5)
        });
    }

    async startVoting(call_id = 0) {
        return await locklift.tracing.trace(this.contract.methods.startVoting({
            meta: {call_id: call_id, nonce: 0, send_gas_to: this._owner.address}
        }).send({
            amount: toNano(5),
            from: this._owner.address
        }));
    }

    async endVoting(call_id = 0) {
        let gas = new Bignumber((await this.contract.methods.calculateGasForEndVoting({}).call()).min_gas);
        gas = gas.plus(new Bignumber(10 ** 9)).toFixed(0)

        return await locklift.tracing.trace(this.contract.methods.endVoting({
            meta: {call_id: call_id, nonce: 0, send_gas_to: this._owner.address}
        }).send({
            amount: gas,
            from: this._owner.address
        }));
    }

    async voteEpoch(voter: Account, votes: any, call_id = 0) {
        return await locklift.tracing.trace(this.contract.methods.voteEpoch({
            votes: votes,
            meta: {call_id: call_id, nonce: 0, send_gas_to: voter.address}
        }).send({
            amount: toNano(5),
            from: voter.address
        }));
    }

    async addToWhitelist(gauge: Address) {
        return await locklift.tracing.trace(this.contract.methods.addToWhitelist({
            gauge: gauge, meta: {call_id: 0, nonce: 0, send_gas_to: this._owner.address}
        }).send({
            from: this._owner.address,
            amount: toNano(1)
        }));
    }

    async deployVeAccount(user: Address) {
        return this.contract.methods.deployVoteEscrowAccount({user: user}).send({
            amount: toNano(5),
            from: this._owner.address
        });
    }

    async depositPayload(deposit_owner: Address, lock_time: number, call_id = 0) {
        return (await this.contract.methods.encodeDepositPayload({
            deposit_owner: deposit_owner,
            nonce: 0,
            lock_time: lock_time,
            call_id: call_id
        }).call()).payload;
    }

    async whitelistDepositPayload(whitelist_contract: Address, call_id = 0) {
        return (await this.contract.methods.encodeWhitelistPayload({
            whitelist_addr: whitelist_contract,
            nonce: 0,
            call_id: call_id
        }).call()).payload;
    }

    async distributionDepositPayload(call_id = 0) {
        return (await this.contract.methods.encodeDistributionPayload({
            nonce: 0,
            call_id: call_id
        }).call()).payload;
    }

    async withdraw(user: Account, call_id = 0) {
        const ve_acc = await this.voteEscrowAccount(user.address);
        let gas;
        gas = (await ve_acc.contract.methods.calculateMinGas({answerId: 0}).call()).min_gas;
        gas = new Bignumber(gas);
        gas = gas.plus(new Bignumber(3 * 10 ** 9)).toFixed(0);

        return await this.contract.methods.withdraw({
            meta: {call_id: call_id, nonce: 0, send_gas_to: user.address}
        }).send({
            amount: gas,
            from: user.address
        });
    }

    async deposit(from_wallet: TokenWallet, amount: number, lock_time: number, call_id = 0, calc_min_gas = true) {
        let gas = null;
        if (calc_min_gas) {
            const ve_acc = await this.voteEscrowAccount(from_wallet._owner?.address as Address);
            gas = (await ve_acc.contract.methods.calculateMinGas({answerId: 0}).call()).min_gas;
            gas = new Bignumber(gas);
            gas = gas.plus(new Bignumber(3 * 10 ** 9)).toFixed(0);
        }
        const payload = await this.depositPayload(from_wallet._owner?.address as Address, lock_time, call_id);
        return await from_wallet.transfer(amount, this.contract.address, payload, gas);
    }

    async whitelistDeposit(from_wallet: TokenWallet, amount: number, whitelist_addr: Address, call_id = 0) {
        const payload = await this.whitelistDepositPayload(whitelist_addr, call_id);
        return await from_wallet.transfer(amount, this.contract.address, payload, null);
    }

    async distributionDeposit(from_wallet: TokenWallet, amount: number, call_id = 0) {
        const payload = await this.distributionDepositPayload(call_id);
        return await from_wallet.transfer(amount, this.contract.address, payload, null);
    }

    async upgrade(new_code: string) {
        return await this.contract.methods.upgrade({
            code: new_code, meta: {call_id: 0, send_gas_to: this._owner.address, nonce: 0}
        }).send({
           amount: toNano(5),
           from: this._owner.address
        });
    }

    async upgradeVeAccount(user: Account, call_id = 0) {
        return await this.contract.methods.upgradeVeAccount({
            meta: {call_id: call_id, nonce: 0, send_gas_to: user.address}
        }).send({
            amount: toNano(5),
            from: user.address
        });
    }

    async forceUpgradeVeAccounts(users: Address[]) {
        return await this.contract.methods.forceUpgradeVeAccounts({
            users: users, meta: {call_id: 0, nonce: 0, send_gas_to: this._owner.address}
        }).send({
            amount: toNano(5 + users.length),
            from: this._owner.address
        });
    }
}
