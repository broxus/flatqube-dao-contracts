import {Address, Contract} from "locklift";
import {FactorySource} from "../../../build/factorySource";
import {Account} from "locklift/build/factory";
import {TokenWallet} from "./token_wallet";

const {toNano} = locklift.utils;


declare type AccountType = Account<FactorySource["TestWallet"]>;


export class Gauge {
    public contract: Contract<FactorySource["Gauge"]>;
    public _owner: AccountType | null;
    public address: Address;
    public name: string | undefined;

    constructor(contract: Contract<FactorySource["Gauge"]>, owner: AccountType) {
        this.contract = contract;
        this._owner = owner;
        this.address = contract.address;
    }

    static async from_addr(addr: Address, owner: AccountType) {
        const contract = await locklift.factory.getDeployedContract('Gauge', addr);
        return new Gauge(contract, owner);
    }

    async gaugeAccount(user: Address) {
        const addr = (await this.contract.methods.getGaugeAccountAddress({user: user, answerId: 0}).call()).value0;
        return locklift.factory.getDeployedContract('GaugeAccount', addr);
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

    async withdraw(user: AccountType, amount: number, claim: boolean, call_id=0) {
        return await user.runTarget(
            {
                contract: this.contract,
                value: toNano(2)
            },
            (gauge) => gauge.methods.withdraw({
                amount: amount,
                claim: claim,
                meta: {nonce: 0, call_id: call_id, send_gas_to: user.address}
            })
        );
    }

    async deposit(from_wallet: TokenWallet, amount: number, lock_time: number, claim: boolean, call_id = 0) {
        const payload = await this.depositPayload(from_wallet._owner?.address as Address, lock_time, claim, call_id);
        return await from_wallet.transfer(amount, this.contract.address, payload, null);
    }

    async rewardDeposit(from_wallet: TokenWallet, amount: number, call_id=0) {
        const payload = await this.rewardDepositPayload(call_id);
        return await from_wallet.transfer(amount, this.contract.address, payload, null);
    }
}
