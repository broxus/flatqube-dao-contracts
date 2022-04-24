pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "@broxus/contracts/contracts/platform/Platform.sol";
import "./libraries/Errors.sol";
import "./base/vote_escrow/VoteEscrowBase.sol";


contract VoteEscrow is VoteEscrowBase {
    // TODO: up
    constructor(address _owner, address _qube, uint32 _distribution_interval) public {
        require (tvm.pubkey() != 0, WRONG_PUBKEY);
        require (tvm.pubkey() == msg.pubkey(), WRONG_PUBKEY);
        tvm.accept();

        owner = _owner;
        qube = _qube;

        // 2 years
        distributionInterval = _distribution_interval;

        _setupTokenWallet();
    }

    // TODO: Up
    function upgrade() external onlyOwner {}

    function onCodeUpgrade() private {}
}
