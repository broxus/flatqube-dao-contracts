pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "./VoteEscrowHelpers.sol";


abstract contract VoteEscrowUpgradable is VoteEscrowHelpers {
    function onVoteEscrowAccountDeploy(address user) external onlyVoteEscrowAccount(user) {
        emit VoteEscrowAccountDeploy(user);
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
}
