pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./TestWallet.sol";
import '@broxus/contracts/contracts/utils/RandomNonce.sol';


contract TestFactory is RandomNonce {
    TvmCell static wallet_code;
    event NewWallet(address addr, uint256 pubkey);

    constructor() public {
        tvm.accept();
    }

    function deployUsers(uint256[] pubkeys, uint128[] values) external view {
        tvm.accept();

        for (uint i = 0; i < pubkeys.length; i++) {
            TvmCell stateInit = tvm.buildStateInit({
                contr: TestWallet,
                varInit: {
                    _randomNonce: tx.timestamp + i
                },
                pubkey: tvm.pubkey(),
                code: wallet_code
            });

            address new_wallet = new TestWallet{
                stateInit: stateInit,
                value: values[i],
                wid: address(this).wid,
                flag: 0
            }(pubkeys[i]);

            emit NewWallet(new_wallet, pubkeys[i]);
        }
    }

}
