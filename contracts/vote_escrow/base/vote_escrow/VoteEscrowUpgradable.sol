pragma ever-solidity ^0.62.0;


import "@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../../interfaces/IVoteEscrowAccount.sol";
import {RPlatform as Platform} from "../../../Platform.sol";
import "./VoteEscrowHelpers.sol";
import "../../../libraries/Errors.sol";


abstract contract VoteEscrowUpgradable is VoteEscrowHelpers {
    function installPlatformCode(TvmCell code, Callback.CallMeta meta) external override onlyOwner {
        require(platformCode.toSlice().empty(), Errors.ALREADY_INITIALIZED);

        tvm.rawReserve(_reserve(), 0);

        platformCode = code;
        emit PlatformCodeInstall(meta.call_id);
        meta.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function installOrUpdateVeAccountCode(TvmCell code, Callback.CallMeta meta) external override onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        veAccountCode = code;
        ve_account_version += 1;
        emit VeAccountCodeUpdate(meta.call_id, ve_account_version - 1, ve_account_version);
        meta.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function upgradeVeAccount(Callback.CallMeta meta) external view {
        require (msg.value >= Gas.VE_ACC_UPGRADE_VALUE, Errors.LOW_MSG_VALUE);

        tvm.rawReserve(_reserve(), 0);
        _upgradeVeAccount(msg.sender, 0, meta);
    }

    // admin hook, no need for call_id or nonce
    function forceUpgradeVeAccounts(address[] users, Callback.CallMeta meta) external view onlyOwner {
        require (msg.value >= Gas.VE_ACC_UPGRADE_VALUE * (users.length + 1), Errors.LOW_MSG_VALUE);

        tvm.rawReserve(_reserve(), 0);
        for (uint i = 0; i < users.length; i++) {
            _upgradeVeAccount(users[i], Gas.VE_ACC_UPGRADE_VALUE, meta);
        }
    }

    function _upgradeVeAccount(address user, uint128 value, Callback.CallMeta meta) internal view {
        address ve_acc = getVoteEscrowAccountAddress(user);

        uint16 flag = 0;
        if (value == 0) {
            flag = MsgFlag.ALL_NOT_RESERVED;
        }

        IVoteEscrowAccount(ve_acc).upgrade{ value: value, flag: flag }(
            veAccountCode,
            ve_account_version,
            meta
        );
    }

    function onVeAccountUpgrade(
        address user,
        uint32 old_version,
        uint32 new_version,
        Callback.CallMeta meta
    ) external override view onlyVoteEscrowAccount(user) {
        tvm.rawReserve(_reserve(), 0);

        emit VoteEscrowAccountUpgrade(meta.call_id, user, old_version, new_version);
        _sendCallbackOrGas(user, meta.nonce, true, meta.send_gas_to);
    }

    function onVoteEscrowAccountDeploy(address user, Callback.CallMeta meta) external override onlyVoteEscrowAccount(user) {
        emit VoteEscrowAccountDeploy(user);

        tvm.rawReserve(_reserve(), 0);
        meta.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function deployVoteEscrowAccount(address user) public view override returns (address) {
        TvmBuilder constructor_params;

        constructor_params.store(ve_account_version); // 32
        constructor_params.store(ve_account_version); // 32
        constructor_params.store(dao); // address

        return new Platform{
            stateInit: _buildInitData(_buildVoteEscrowAccountParams(user)),
            value: Gas.VE_ACCOUNT_DEPLOY_VALUE
        }(veAccountCode, constructor_params.toCell(), user);
    }
}
