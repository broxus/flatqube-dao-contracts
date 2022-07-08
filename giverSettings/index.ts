import { Address, Contract, GiverI, ProviderRpcClient, Transaction } from "locklift";
import { Ed25519KeyPair } from "everscale-standalone-client";

// Reimplements this class if need to use custom giver contract
export class Giver implements GiverI {
    public giverContract: Contract<typeof giverAbi>;

    constructor(ever: ProviderRpcClient, readonly keyPair: Ed25519KeyPair, address: string) {
        const giverAddr = new Address(address);
        this.giverContract = new ever.Contract(giverAbi, giverAddr);
    }
    public async sendTo(sendTo: Address, value: string): Promise<{ transaction: Transaction; output?: {} }> {
        return this.giverContract.methods
            .sendTransaction({
                value: value,
                dest: sendTo,
                bounce: false,
            })
            .sendExternal({ publicKey: this.keyPair.publicKey });
    }
}

const giverAbi = {
    "ABI version": 2,
    header: ["time", "expire"],
    functions: [
        {
            name: "upgrade",
            inputs: [{ name: "newcode", type: "cell" }],
            outputs: [],
        },
        {
            name: "sendTransaction",
            inputs: [
                { name: "dest", type: "address" },
                { name: "value", type: "uint128" },
                { name: "bounce", type: "bool" },
            ],
            outputs: [],
        },
        {
            name: "getMessages",
            inputs: [],
            outputs: [
                {
                    components: [
                        { name: "hash", type: "uint256" },
                        { name: "expireAt", type: "uint64" },
                    ],
                    name: "messages",
                    type: "tuple[]",
                },
            ],
        },
        {
            name: "constructor",
            inputs: [],
            outputs: [],
        },
    ],
    events: [],
} as const;
