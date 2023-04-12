pragma ever-solidity ^0.62.0;


interface ICallbackReceiver {
    function acceptSuccessCallback(uint32 nonce, TvmCell payload) external;
    function acceptFailCallback(uint32 nonce, TvmCell payload) external;
}
