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
        veAccContract.setAddress(addr);
        return new VoteEscrowAccount(veAccContract);
    }

    async getDetails() {
        return await this.contract.call({method: 'getDetails'});
    }
}

module.exports = VoteEscrowAccount
