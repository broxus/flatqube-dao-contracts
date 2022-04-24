pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./VoteEscrowStorage.sol";


abstract contract VoteEscrowUpgradable is VoteEscrowStorage {
    function getVoteEscrowAccountAddress(address user) public view responsible returns (address) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false } address(
            tvm.hash(_buildInitData(_buildVoteEscrowAccountParams(user)))
        );
    }

    function _buildVoteEscrowAccountParams(address user) internal view returns (TvmCell) {
        TvmBuilder builder;
        builder.store(user);
        return builder.toCell();
    }

    function _buildInitData(TvmCell _initialData) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Platform,
            varInit: {
                root: address(this),
                platformType: PlatformTypes.VoteEscrowAccount,
                initialData: _initialData,
                platformCode: platformCode
            },
            pubkey: 0,
            code: platformCode
        });
    }


    function deployVoteEscrowAccount(address user) public returns (address) {
        TvmBuilder constructor_params;

        constructor_params.store(ve_account_version); // 32
        constructor_params.store(ve_account_version); // 32

        return new Platform{
        stateInit: _buildInitData(_buildVoteEscrowAccountParams(user)),
        value: Gas.VE_ACCOUNT_DEPLOY_VALUE
        }(veAccountCode, constructor_params.toCell(), user);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, Errors.NOT_OWNER);
        _;
    }

    modifier onlyVoteEscrowAccount(address user) {
        address ve_account_addr = getVoteEscrowAccountAddress(user);
        require (msg.sender == ve_account_addr, NOT_VOTE_ESCROW_ACCOUNT);
        _;
    }
}
