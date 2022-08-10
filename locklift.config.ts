import { LockliftConfig } from "locklift/config";
import { FactorySource } from "./build/factorySource";
import {GiverWallet, SimpleGiver, TestnetGiver} from "./giverSettings";
import * as dotenv from "dotenv";
declare global {
    const locklift: import("locklift").Locklift<FactorySource>;
}
dotenv.config();


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
            // Specify connection settings for https://github.com/broxus/everscale-standalone-client/
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
            // Specify connection settings for https://github.com/broxus/everscale-standalone-client/
            connection: "testnet",
            // This giver is default local-node giverV2
            giver: {
                // Check if you need provide custom giver
                giverFactory: (ever, keyPair, address) => new TestnetGiver(ever, keyPair, address),
                address: "0:a4053fd2e9798d0457c9e8f012cef203e49da863d76f36d52d5e2e62c326b217",
                key: process.env.TESTNET_GIVER_KEY ?? "",
            },
            tracing: {
                endpoint: 'https://net.ton.dev/graphql',
            },

            keys: {
                // Use everdev to generate your phrase
                // !!! Never commit it in your repos !!!
                // phrase: "action inject penalty envelope rabbit element slim tornado dinner pizza off blood",
                amount: 500
            },
        },
        main: {
            connection: "mainnet",
            giver: {
                // Mainnet giver has the same abi as testnet one
                giverFactory: (ever, keyPair, address) => new TestnetGiver(ever, keyPair, address),
                address: "0:3bcef54ea5fe3e68ac31b17799cdea8b7cffd4da75b0b1a70b93a18b5c87f723",
                key: process.env.MAIN_GIVER_KEY ?? ""
            },
            tracing: {
                endpoint: 'https://main.ton.dev/graphql'
            },
            keys: {
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
