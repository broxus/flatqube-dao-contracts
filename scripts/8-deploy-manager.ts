import {toNano, WalletTypes} from "locklift";

const logger = require("mocha-logger");


async function main() {
  const signer = await locklift.keystore.getSigner('0');

  const {account} = await locklift.tracing.trace(locklift.factory.accounts.addNewAccount({
    type: WalletTypes.EverWallet,
    value: toNano(50),
    publicKey: signer?.publicKey as string
  }));

  console.log(`Manager: ${account.address}`);
}

main()
  .then(() => process.exit(0))
  .catch(e => {
    console.log(e);
    process.exit(1);
  });
