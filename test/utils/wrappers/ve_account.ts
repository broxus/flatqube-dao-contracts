import {FactorySource} from "../../../build/factorySource";
import {Address, Contract} from "locklift";


export class VoteEscrowAccount {
    public contract: Contract<FactorySource["VoteEscrowAccount"]>
    public address: Address;

    constructor(ve_acc_contract: Contract<FactorySource["VoteEscrowAccount"]>) {
        this.contract = ve_acc_contract;
        this.address = this.contract.address;
    }

    static async from_addr(addr: Address) {
        const contract = await locklift.factory.getDeployedContract('VoteEscrowAccount', addr);
        return new VoteEscrowAccount(contract);
    }

    async getDetails() {
        return await this.contract.methods.getDetails({answerId: 0}).call();
    }

    async calculateVeAverage() {
        return await this.contract.methods.calculateVeAverage().call();
    }
}
