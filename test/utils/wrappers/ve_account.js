const {
    convertCrystal
} = locklift.utils;


class VoteEscrowAccount {
    constructor(ve_acc_contract) {
        this.contract = ve_acc_contract;
        this.address = this.contract.address;
    }

    static async from_addr(addr) {
        const contract = await locklift.factory.getDeployedContract('VoteEscrowAccount', addr);
        return new VoteEscrowAccount(contract);
    }

    async getDetails() {
        return await this.contract.methods.getDetails({answerId: 0}).call();
    }

    async calculateVeAverage() {
        return await this.contract.methods.calculateVeAverage({}).call();
    }
}

module.exports = VoteEscrowAccount
