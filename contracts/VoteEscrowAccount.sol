pragma ton-solidity ^0.57.1;


import "./base/ve_account/VoteEscrowAccountBase.sol";


contract VoteEscrowAccount is VoteEscrowAccountBase {
    // Cant be deployed directly
    constructor() public { revert(); }


    function upgrade(TvmCell new_code, uint32 new_version, address send_gas_to) external onlyVoteEscrow {
        if (new_version == current_version) {
            tvm.rawReserve(_reserve(), 0);
            send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
            return;
        }

        // TODO: upgrade

        // set code after complete this method
        //        tvm.setcode(new_code);
        //
        //        // run onCodeUpgrade from new code
        //        tvm.setCurrentCode(new_code);
        //        onCodeUpgrade(main_builder.toCell());
    }

    function onCodeUpgrade(TvmCell upgrade_data) private {
        tvm.resetStorage();
        tvm.rawReserve(_reserve(), 0);

        TvmSlice s = upgrade_data.toSlice();
        (address root_, , address send_gas_to) = s.decode(address, uint8, address);
        voteEscrow = root_;

        platform_code = s.loadRef();

        TvmSlice initialData = s.loadRefAsSlice();
        user = initialData.decode(address);

        TvmSlice params = s.loadRefAsSlice();
        (current_version, ) = params.decode(uint32, uint32);

        IVoteEscrow(voteEscrow).onVoteEscrowAccountDeploy{value: 0.01 ton, flag: MsgFlag.SENDER_PAYS_FEES}(user);

        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }
}
