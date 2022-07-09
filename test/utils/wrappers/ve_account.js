const {
    convertCrystal
} = locklift.utils;


class VoteEscrowAccount {
    constructor(ve_acc_contract) {
        this.contract = ve_acc_contract;
        this.address = this.contract.address;
    }

    static async from_addr(addr) {
        const veAccContract = await locklift.factory.getContract('VoteEscrowAccount');
        const ve_acc = new locklift.provider.ever.Contract(veAccContract.abi, addr);
        return new VoteEscrowAccount(ve_acc);
    }

    async getDetails() {
        return await this.contract.methods.getDetails({answerId: 0}).call();
    }

    async calculateVeAverage() {
        return await this.contract.methods.calculateVeAverage({}).call();
    }
}

module.exports = VoteEscrowAccount
