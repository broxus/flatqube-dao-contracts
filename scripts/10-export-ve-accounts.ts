import {writeFileSync} from 'fs';
import {Address} from 'locklift';
import {yellowBright} from 'chalk';
// eslint-disable-next-line @typescript-eslint/no-var-requires

const OLD_VE_ACC_HASH =
  'ece2b4e78d48eccb21b2d352b0139b99c02f03f7f5d88004201f1306ff652c23';
const ve_root = '0:8317ae7ee92d748500e179843b587d7fbd98d6bb37402e2b44566f9f6f3cdd90';

async function exportVeAccounts() {
  console.log('VoteEscrow: ' + ve_root);

  let continuation = undefined;
  let hasResults = true;
  const accounts: Address[] = [];

  const start = Date.now();

  while (hasResults) {
    const result: { accounts: Address[]; continuation: string | undefined } =
      await locklift.provider.getAccountsByCodeHash({
        codeHash: OLD_VE_ACC_HASH,
        continuation,
        limit: 50,
      });

    console.log(result.accounts.map((a) => a.toString()));

    continuation = result.continuation;
    hasResults = result.accounts.length === 50;

    accounts.push(...result.accounts);
  }

  const promises: Promise<Address | null>[] = [];

  for (const ve_acc_addr of accounts) {
    promises.push(
      new Promise(async (resolve) => {
        const ve_acc = locklift.factory.getDeployedContract(
          'VoteEscrowAccount',
          ve_acc_addr,
        );

        const root = await ve_acc.methods.getDetails({answerId: 0}).call().then((r) => r._voteEscrow.toString());
        if (root === ve_root) {
          resolve(ve_acc_addr);
        } else {
          console.log(
            yellowBright(`VoteEscrow acc ${ve_acc_addr} has another root: ${root}`),
          );
          resolve(null);
        }
      }),
    );
  }

  const pairs = await Promise.all(promises);

  console.log(`Export took ${(Date.now() - start) / 1000} seconds`);

  writeFileSync(
    './ve_accs.json',
    JSON.stringify(
      pairs.filter((v) => !!v),
      null,
      2,
    ),
  );
}

exportVeAccounts()
  .then(() => process.exit(0))
  .catch((e) => {
    console.log(e);
    process.exit(1);
  });
