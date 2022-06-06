pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import '@broxus/contracts/contracts/wallets/Account.sol';


contract TestWallet is Account {
    // deployable by both internal and external msgs
    constructor(uint256 owner_pubkey) public {
        tvm.accept();

        setOwnership(owner_pubkey);
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
