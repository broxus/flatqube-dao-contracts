pragma ever-solidity ^0.62.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import '@broxus/contracts/contracts/wallets/Account.tsol';
import "@broxus/contracts/contracts/libraries/MsgFlag.tsol";



contract TestWallet is Account {
    // deployable by both internal and external msgs
    constructor(uint256 owner_pubkey) public {
        tvm.accept();

        setOwnership(owner_pubkey);
    }

    // can accept tokens
    function onAcceptTokensTransfer(
        address,
        uint128,
        address,
        address,
        address remainingGasTo,
        TvmCell
    ) external pure {
        tvm.rawReserve(address(this).balance - msg.value, 0);

        remainingGasTo.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    // batch version of sendTransaction
    function sendTransactions(
        address[] dest,
        uint128[] value,
        bool[] bounce,
        uint8[] flags,
        TvmCell[] payload
    )
        public
        view
        onlyOwner
    {
        tvm.accept();

        for (uint i = 0; i < dest.length; i++) {
            dest[i].transfer(value[i], bounce[i], flags[i], payload[i]);
        }
    }
}
