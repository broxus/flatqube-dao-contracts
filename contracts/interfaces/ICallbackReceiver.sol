pragma ton-solidity ^0.60.0;


interface ICallbackReceiver {
    function acceptSuccessCallback(uint32 nonce) external;
    function acceptFailCallback(uint32 nonce) external;
}
