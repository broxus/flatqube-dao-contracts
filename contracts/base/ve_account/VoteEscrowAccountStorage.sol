pragma ton-solidity ^0.57.1;
pragma AbiHeader expire;


import "../../interfaces/IVoteEscrowAccount.sol";


abstract contract VoteEscrowAccountStorage is IVoteEscrowAccount {
    uint32 current_version;

    address voteEscrow;
    address user;

    uint128 qubeBalance; // total amount of deposited qubes
    uint128 veQubeBalance; // current ve balance
    uint128 expiredVeQubes; // expired ve qubes that should be withdrawn from vote escrow contract
    uint128 unlockedQubes; // qubes with expired lock, that can be withdraw

    // this is updated every time user deposit qubes/ve expire
    uint128 veQubeAverage;
    uint32 veQubeAveragePeriod;
    uint32 lastUpdateTime;

    uint32 lastEpochVoted; // number of last epoch when user voted
    uint32 activeDeposits; // number of currently locked deposits

    mapping (uint64 => QubeDeposit) deposits;

    uint32 constant MAX_ITERATIONS_PER_MSG = 50;
    uint128 constant CONTRACT_MIN_BALANCE = 0.3 ton;
}
