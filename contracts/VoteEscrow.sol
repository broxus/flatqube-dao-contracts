pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";
import "./libraries/Errors.sol";
import "./base/vote_escrow/VoteEscrowBase.sol";


contract VoteEscrow is VoteEscrowBase {
    constructor(address _owner, address _qube) public {
        require (tvm.pubkey() != 0, Errors.WRONG_PUBKEY);
        require (tvm.pubkey() == msg.pubkey(), Errors.WRONG_PUBKEY);
        tvm.accept();

        owner = _owner;
        qube = _qube;

        _setupTokenWallet();
    }

    // TODO: Up
    function upgrade() external onlyOwner {}

    function onCodeUpgrade() private {}
}
