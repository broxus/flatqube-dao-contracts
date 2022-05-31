pragma ton-solidity ^0.57.1;


import "./base/ve_account/VoteEscrowAccountBase.sol";


contract VoteEscrowAccount is VoteEscrowAccountBase {
    // Cant be deployed directly
    constructor() public { revert(); }

    function upgrade(
        TvmCell new_code, uint32 new_version, uint32 call_id, uint32 nonce, address send_gas_to
    ) external override onlyVoteEscrowOrSelf {
        if (new_version == current_version) {
            tvm.rawReserve(_reserve(), 0);
            send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
            return;
        }

        uint8 _tmp;
        TvmBuilder main_builder;
        main_builder.store(voteEscrow); // address 267
        main_builder.store(_tmp); // 8
        main_builder.store(send_gas_to); // address 267

        TvmCell empty;
        main_builder.storeRef(empty); // ref

        TvmBuilder initial;
        initial.store(user);

        main_builder.storeRef(initial); // ref 2

        TvmBuilder params;
        params.store(new_version);
        params.store(current_version);

        main_builder.storeRef(params); // ref3

        TvmCell data = abi.encode(
            call_id,
            nonce,
            qubeBalance,
            veQubeBalance,
            expiredVeQubes,
            unlockedQubes,
            veQubeAverage,
            veQubeAveragePeriod,
            lastUpdateTime,
            lastEpochVoted,
            activeDeposits,
            deposits
        );

        main_builder.storeRef(data); // ref 4

        tvm.setcode(new_code);
        // run onCodeUpgrade from new code
        tvm.setCurrentCode(new_code);
        onCodeUpgrade(main_builder.toCell());
    }

    function onCodeUpgrade(TvmCell upgrade_data) private {
        tvm.resetStorage();
        tvm.rawReserve(_reserve(), 0);

        TvmSlice s = upgrade_data.toSlice();
        (address root_, , address send_gas_to) = s.decode(address, uint8, address);
        voteEscrow = root_;

        // skip 0 bits and 1 ref (platform code), we dont need it
        s.skip(0, 1);

        TvmSlice initialData = s.loadRefAsSlice();
        user = initialData.decode(address);

        TvmSlice params = s.loadRefAsSlice();
        (current_version, ) = params.decode(uint32, uint32);

        IVoteEscrow(voteEscrow).onVoteEscrowAccountDeploy{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(user, send_gas_to);
    }
}
