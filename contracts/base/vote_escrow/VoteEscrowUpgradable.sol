pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../../interfaces/IVoteEscrowAccount.sol";
import "./VoteEscrowHelpers.sol";
import "../../libraries/Errors.sol";


abstract contract VoteEscrowUpgradable is VoteEscrowHelpers {
    function installPlatformCode(TvmCell code, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        require(platformCode.toSlice().empty(), Errors.ALREADY_INITIALIZED);

        tvm.rawReserve(_reserve(), 0);

        platformCode = code;
        emit PlatformCodeInstall();
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function installOrUpdateVeAccountCode(TvmCell code, address send_gas_to) external onlyOwner {
        require (msg.value >= Gas.MIN_MSG_VALUE, Errors.LOW_MSG_VALUE);
        tvm.rawReserve(_reserve(), 0);

        veAccountCode = code;
        ve_account_version += 1;
        emit VeAccountCodeUpgrade(ve_account_version - 1, ve_account_version);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function upgradeVeAccount(uint32 call_id, uint32 nonce, address send_gas_to) external view {
        require (msg.value >= Gas.VE_ACC_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);

        tvm.rawReserve(_reserve(), 0);
        _upgradeVeAccount(msg.sender, 0, call_id, nonce, send_gas_to);
    }

    // admin hook, no need for call_id or nonce
    function forceUpgradeVeAccounts(address[] users, address send_gas_to) external view onlyOwner {
        require (msg.value >= Gas.VE_ACC_UPGRADE_VALUE * (users.length + 1), Errors.LOW_MSG_VALUE);

        tvm.rawReserve(_reserve(), 0);
        for (uint i = 0; i < users.length; i++) {
            _upgradeVeAccount(users[i], Gas.VE_ACC_UPGRADE_VALUE, 0, 0, send_gas_to);
        }
    }

    function _upgradeVeAccount(address user, uint128 value, uint32 call_id, uint32 nonce, address send_gas_to) internal view {
        address ve_acc = getVoteEscrowAccountAddress(user);

        uint16 flag = 0;
        if (value == 0) {
            flag = MsgFlag.ALL_NOT_RESERVED;
        }

        IVoteEscrowAccount(ve_acc).upgrade{ value: value, flag: flag }(
            veAccountCode,
            ve_account_version,
            call_id,
            nonce,
            send_gas_to
        );
    }

    function onVeAccountUpgrade(
        address user,
        uint32 old_version,
        uint32 new_version,
        uint32 call_id,
        uint32 nonce,
        address send_gas_to
    ) external view onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        emit VoteEscrowAccountUpgrade(call_id, user, old_version, new_version);
        _sendCallbackOrGas(user, nonce, true, send_gas_to);
    }

    function onVoteEscrowAccountDeploy(address user, address send_gas_to) external override onlyVoteEscrowAccount(user) {
        emit VoteEscrowAccountDeploy(user);

        tvm.rawReserve(_reserve(), 0);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function deployVoteEscrowAccount(address user) public view override returns (address) {
        TvmBuilder constructor_params;

        constructor_params.store(ve_account_version); // 32
        constructor_params.store(ve_account_version); // 32

        return new Platform{
            stateInit: _buildInitData(_buildVoteEscrowAccountParams(user)),
            value: Gas.VE_ACCOUNT_DEPLOY_VALUE
        }(veAccountCode, constructor_params.toCell(), user);
    }
}
