pragma ton-solidity ^0.57.1;


interface IVoteEscrowCallbackReceiver {
    function acceptVoteEscrowSuccessCallback(uint32 nonce) external;
    function acceptVoteEscrowFailCallback(uint32 nonce) external;
}
