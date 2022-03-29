pragma solidity ^0.58.2;

contract Dummy {

    struct RewardTokenData {
        address tokenRoot;
        address tokenWallet;
        uint128 tokenBalance;
        uint128 tokenBalanceCumulative;
        uint32 vestingPeriod;
        uint32 vestingRatio;

    }

    struct QubeRewardData {
        RewardTokenData mainData;
        bool enabled;
        uint256 accRewardPerShare;
        // qube current reward speed
        uint128 rewardPerSecond;
        // qube reward speed for future epoch
        uint128 nextEpochRewardPerSecond;
        // timestamp when qubeRewardPerSecond will be changed
        uint32 nextEpochTime;
        // timestamp when next epoch will end
        // we need this for case when next epoch wont end in time, so that farm speed will be 0 after that point
        uint32 nextEpochEndTime;
    }

    struct Simple {
        uint32 a;
        uint32 b;
    }

    uint32[] ab;
    Simple[] simple;

    QubeRewardData qube_rew;
    QubeRewardData[] qube_arr;
    uint128[] balances;

    constructor() public {
        tvm.accept();

        qube_rew.mainData.vestingRatio = 123;
        qube_rew.mainData.tokenBalance = 123;
        qube_rew.nextEpochEndTime = 123123;

        qube_arr = new QubeRewardData[](100);
        balances = new uint128[](100);
        ab = new uint32[](100);
        simple = new Simple[](100);
//        for (uint i = 0; i < 100; i++) {
//            qube_arr[i].mainData.tokenBalance = 12123;
//            balances[i] = 123123;
//        }
    }

    function testLocalStorage() external {
        tvm.accept();

        RewardTokenData _local = qube_rew.mainData;
        for (uint i = 0; i < 100; i++) {
            uint128 q = _local.vestingRatio;
            uint128 qwe = _local.tokenBalance;
            uint128 res = q + qwe;
        }
    }

    function testStorage() external {
        tvm.accept();

        for (uint i = 0; i < 100; i++) {
            uint128 q = qube_rew.mainData.vestingRatio;
            uint128 qwe = qube_rew.mainData.tokenBalance;
            uint128 res = q + qwe;
        }
    }

    function testArr() external {
        tvm.accept();

        for (uint i = 0; i < 100; i++) {
            uint128 qwe = balances[i];
            uint128 www = qwe + 123;
        }
    }

    function testStructArr() external {
        tvm.accept();

        for (uint i = 0; i < 100; i++) {
            uint256 qwe = qube_arr[i].mainData.tokenBalance;
            uint256 www = qwe + 123;
        }
    }

    function testSimpleStruct() external {
        tvm.accept();

        for (uint i = 0; i < 100; i++) {
            uint256 qwe = ab[i];
            uint256 res = qwe + 123;
        }
    }

    function testSimpleStruct2() external {
        tvm.accept();

        for (uint i = 0; i < 100; i++) {
            uint256 qwe = simple[i].a;
            uint256 res = qwe + 123;
        }
    }
}
