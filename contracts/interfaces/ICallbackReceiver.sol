pragma ton-solidity ^0.57.1;


interface ICallbackReceiver {
    function acceptSuccessCallback(uint32 nonce) external;
    function acceptFailCallback(uint32 nonce) external;
}
