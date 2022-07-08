// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "../access/Governable.sol";
import "../peripherals/interfaces/ITimelock.sol";

contract RewardManager is Governable {

    bool public isInitialized;

    ITimelock public timelock;
    address public rewardRouter;

    address public nitManager;

    address public feeNitTracker;

    function initialize(
        ITimelock _timelock,
        address _rewardRouter,
        address _nitManager,
        address _feeNitTracker
    ) external onlyGov {
        require(!isInitialized, "RewardManager: already initialized");
        isInitialized = true;

        timelock = _timelock;
        rewardRouter = _rewardRouter;

        nitManager = _nitManager;

        feeNitTracker = _feeNitTracker;
    }


    function enableRewardRouter() external onlyGov {
        timelock.managedSetHandler(nitManager, rewardRouter, true);

        timelock.managedSetHandler(feeNitTracker, rewardRouter, true);
    }
}
