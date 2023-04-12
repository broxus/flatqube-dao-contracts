pragma ever-solidity >= 0.39.0;

import "./IBasicEvent.tsol";


interface IEverscaleEvent is IBasicEvent {
    struct EverscaleEventVoteData {
        uint64 eventTransactionLt;
        uint32 eventTimestamp;
        TvmCell eventData;
    }

    struct EverscaleEventInitData {
        EverscaleEventVoteData voteData;
        address configuration;
        address staking;
    }
}
