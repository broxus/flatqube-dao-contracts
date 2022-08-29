import {Address, Contract} from "locklift";
import {FactorySource} from "../../../build/factorySource";
import {TokenWallet} from "./token_wallet";
import {Account} from "everscale-standalone-client/nodejs";
import {use} from "chai";

const {toNano} = locklift.utils;


export class Gauge {
    public contract: Contract<FactorySource["Gauge"]>;
    public _owner: Account;
    public address: Address;
    public name: string | undefined;

    constructor(contract: Contract<FactorySource["Gauge"]>, owner: Account) {
        this.contract = contract;
        this._owner = owner;
        this.address = contract.address;
    }

    static async from_addr(addr: Address, owner: Account) {
        const contract = await locklift.factory.getDeployedContract('Gauge', addr);
        return new Gauge(contract, owner);
    }

    async gaugeAccount(user: Address) {
        const addr = (await this.contract.methods.getGaugeAccountAddress({user: user, answerId: 0}).call()).value0;
        return locklift.factory.getDeployedContract('GaugeAccount', addr);
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

    async getDetails() {
        return this.contract.methods.getDetails().call();
    }

    async getTokenDetails() {
        return this.contract.methods.getTokenDetails().call();
    }

    async getRewardDetails() {
        return this.contract.methods.getRewardDetails().call();
    }

    async depositPayload(deposit_owner: Address, lock_time: number, claim=false,call_id = 0) {
        return (await this.contract.methods.encodeDepositPayload({
            deposit_owner: deposit_owner,
            claim: claim,
            nonce: 0,
            lock_time: lock_time,
            call_id: call_id
        }).call()).deposit_payload;
    }

    async rewardDepositPayload(call_id = 0) {
        return (await this.contract.methods.encodeRewardDepositPayload({
            nonce: 0,
            call_id: call_id
        }).call()).reward_deposit_payload;
    }

    async setExtraFarmEndTime(ids: number[], farm_end_times: number[], call_id=0) {
        return await this.contract.methods.setExtraFarmEndTime({
            ids: ids,
            farm_end_times: farm_end_times,
            meta: {nonce: 0, call_id: call_id, send_gas_to: this._owner.address}
        }).send({
            from: this._owner.address,
            amount: toNano(2)
        });
    }

    async addRewardRounds(
        ids: number[],
        new_rounds: {startTime: number, rewardPerSecond: number}[],
        call_id=0
    ) {
        const new_rounds_full = new_rounds.map((i) => {
            return {endTime: 0, accRewardPerShare: 0, ...i}
        })
        return await this.contract.methods.addRewardRounds({
            ids: ids,
            new_rounds: new_rounds_full,
            meta: {nonce: 0, call_id: call_id, send_gas_to: this._owner.address}
        }).send({
            from: this._owner.address,
            amount: toNano(2)
        });
    }

    async withdraw(user: Account, amount: number, claim: boolean, call_id=0) {
        return await this.contract.methods.withdraw({
            amount: amount,
            claim: claim,
            meta: {nonce: 0, call_id: call_id, send_gas_to: user.address}
        }).send({
            amount: toNano(2),
            from: user.address
        });
    }

    async claimReward(user: Account, call_id=0) {
        return await this.contract.methods.claimReward({
            meta: {nonce: 0, call_id: call_id, send_gas_to: user.address}
        }).send({
            amount: toNano(5),
            from: user.address
        });
    }

    async withdrawUnclaimed(ids: number[], to: Address, call_id= 0) {
        return await this.contract.methods.withdrawUnclaimed({
            ids: ids, to: to, meta: {nonce: 0, call_id: call_id, send_gas_to: this._owner.address}
        }).send({
            from: this._owner.address,
            amount: toNano(5)
        });
    }

    async deposit(from_wallet: TokenWallet, amount: number, lock_time: number, claim: boolean, call_id = 0, value=toNano(5)) {
        const payload = await this.depositPayload(from_wallet._owner?.address as Address, lock_time, claim, call_id);
        return await from_wallet.transfer(amount, this.contract.address, payload, value);
    }

    async rewardDeposit(from_wallet: TokenWallet, amount: number, call_id=0) {
        const payload = await this.rewardDepositPayload(call_id);
        return await from_wallet.transfer(amount, this.contract.address, payload, null);
    }
}
