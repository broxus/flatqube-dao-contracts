import { LockliftConfig } from "locklift";
import { FactorySource } from "./build/factorySource";
import {GiverWallet, SimpleGiver, TestnetGiver} from "./giverSettings";
import * as dotenv from "dotenv";
declare global {
    const locklift: import("locklift").Locklift<FactorySource>;
}
dotenv.config();


const LOCAL_NETWORK_ENDPOINT = process.env.NETWORK_ENDPOINT || "http://localhost/graphql";
const DEV_NET_NETWORK_ENDPOINT = process.env.DEV_NET_NETWORK_ENDPOINT || "https://devnet-sandbox.evercloud.dev/graphql";

const VENOM_TESTNET_ENDPOINT = process.env.VENOM_TESTNET_ENDPOINT || "https://jrpc-testnet.venom.foundation/rpc";
const VENOM_TESTNET_TRACE_ENDPOINT =
    process.env.VENOM_TESTNET_TRACE_ENDPOINT || "https://gql-testnet.venom.foundation/graphql";

// Create your own link on https://dashboard.evercloud.dev/
const MAIN_NET_NETWORK_ENDPOINT = process.env.MAIN_NET_NETWORK_ENDPOINT || "https://mainnet.evercloud.dev/XXX/graphql";



const config: LockliftConfig = {
    compiler: {
        // Specify path to your TON-Solidity-Compiler
        // path: "/mnt/o/projects/broxus/TON-Solidity-Compiler/build/solc/solc",

        // Or specify version of compiler
        version: "0.62.0",

        // Specify config for external contracts as in example
        externalContracts: {
            "node_modules/broxus-token-contracts/build": [
                'TokenRootUpgradeable',
                'TokenWalletUpgradeable',
                'TokenWalletPlatform'
            ]
        }
    },
    linker: {
        // Specify path to your stdlib
        // lib: "/mnt/o/projects/broxus/TON-Solidity-Compiler/lib/stdlib_sol.tvm",
        // // Specify path to your Linker
        // path: "/mnt/o/projects/broxus/TVM-linker/target/release/tvm_linker",

        // Or specify version of linker
        version: "0.15.48",
    },
    networks: {
        local: {
            // Specify connection settings for https://github.com/broxus/everscale-client/
            connection: {
                group: "localnet",
                // @ts-ignore
                type: "graphql",
                data: {
                    // @ts-ignore
                    endpoints: ["http://localhost:5000/graphql"],
                    latencyDetectionInterval: 1000,
                    local: true,
                },
            },
            // This giver is default local-node giverV2
            giver: {
                // Check if you need provide custom giver
                giverFactory: (ever, keyPair, address) => new SimpleGiver(ever, keyPair, address),
                address: "0:ece57bcc6c530283becbbd8a3b24d3c5987cdddc3c8b7b33be6e4a6312490415",
                key: "172af540e43a524763dd53b26a066d472a97c4de37d5498170564510608250c3",
            },
            tracing: {
                endpoint: 'http://localhost:5000/graphql',
            },

            keys: {
                // Use everdev to generate your phrase
                // !!! Never commit it in your repos !!!
                // phrase: "action inject penalty envelope rabbit element slim tornado dinner pizza off blood",
                amount: 500
            },
        },
        test: {
            connection: {
                id: 1,
                type: "graphql",
                group: "dev",
                data: {
                    endpoints: [DEV_NET_NETWORK_ENDPOINT],
                    latencyDetectionInterval: 1000,
                    local: false,
                },
            },
            giver: {
                address: "0:a4053fd2e9798d0457c9e8f012cef203e49da863d76f36d52d5e2e62c326b217",
                key: "secret key",
            },
            tracing: {
                endpoint: DEV_NET_NETWORK_ENDPOINT,
            },
            keys: {
                // Use everdev to generate your phrase
                // !!! Never commit it in your repos !!!
                // phrase: "action inject penalty envelope rabbit element slim tornado dinner pizza off blood",
                amount: 20,
            },
        },
        main: {
            connection: {
                id: 1000,
                group: "group",
                type: "jrpc",
                data: {
                    endpoint: process.env.MAIN_RPC_ENDPOINT || ""
                },
            },
            giver: {
                // Mainnet giver has the same abi as testnet one
                giverFactory: (ever, keyPair, address) => new TestnetGiver(ever, keyPair, address),
                address: "0:73a868302a14a05ee6de24eed367bd42e7cd345406bb12e5fc6749de91a579ff",
                phrase: process.env.MAIN_SEED_PHRASE ?? "",
                accountId: 0
            },
            tracing: {
                endpoint: process.env.MAIN_GQL_ENDPOINT ?? ""
            },
            keys: {
                phrase: process.env.MAIN_SEED_PHRASE ?? "",
                amount: 500
            }
        }
    },
    mocha: {
        timeout: 3000000,
        bail: true
    },
};

export default config;
