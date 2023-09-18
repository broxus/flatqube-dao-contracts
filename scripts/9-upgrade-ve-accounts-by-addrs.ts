import {Address, toNano, WalletTypes} from "locklift";
import {readFileSync} from "fs";
import {EverWalletAccount} from "everscale-standalone-client/nodejs";


async function main() {
  const signer = await locklift.keystore.getSigner('0');

  const manager_addr = await EverWalletAccount.fromPubkey({
    publicKey: signer!.publicKey
  });

  const acc = await locklift.factory.accounts.addExistingAccount({
    type: WalletTypes.EverWallet,
    address: manager_addr.address
  });

  console.log(`Manager: ${acc.address}`);

  const ve_addr = new Address('0:8317ae7ee92d748500e179843b587d7fbd98d6bb37402e2b44566f9f6f3cdd90');
  const ve = locklift.factory.getDeployedContract('VoteEscrow', ve_addr);

  // read json address array from ve_accs.json
  const ve_accs = JSON.parse(readFileSync('./ve_accs.json').toString());
  console.log(`Found ${ve_accs.length} aacs`);

  const chunkSize = 500;
  for (let i = 0; i < ve_accs.length; i += chunkSize) {
    const chunk = ve_accs.slice(i, i + chunkSize);

    const value = toNano((chunk.length + 1) * 1.5);
    await locklift.tracing.trace(ve.methods.forceUpgradeVeAccountsByAddrs({
      accs: chunk, meta: {nonce:0 , call_id: 0, send_gas_to: acc.address}
    }).send({from: acc.address, amount: value}));
    console.log(`Sent ${chunk.length} accounts`);
    // do whatever
  }
}

main()
  .then(() => process.exit(0))
  .catch(e => {
    console.log(e);
    process.exit(1);
  });
