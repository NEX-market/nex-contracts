// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH10.sol";
import "../core/interfaces/INitManager.sol";
import "../access/Governable.sol";

contract RewardRouterV2 is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public nit; // NEX Liquidity Provider token

    address public feeNitTracker;

    address public nitManager;

    mapping (address => address) public pendingReceivers;

    event StakeNit(address account, uint256 amount);
    event UnstakeNit(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _nit,
        address _feeNitTracker,
        address _nitManager
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;
        nit = _nit;
        feeNitTracker = _feeNitTracker;
        nitManager = _nitManager;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }


    function mintAndStakeNit(address _token, uint256 _amount, uint256 _minUsd, uint256 _minNit) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;

        uint256 nitAmount = INitManager(nitManager).addLiquidityForAccount(account, account, _token, _amount, _minUsd, _minNit);

        IRewardTracker(feeNitTracker).stakeForAccount(account, account, nit, nitAmount);

        emit StakeNit(account, nitAmount);

        return nitAmount;
    }

    function mintAndStakeNitETH(uint256 _minUsd, uint256 _minNit) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH10(weth).deposit{value: msg.value}();
        IERC20(weth).approve(nitManager, msg.value);

        address account = msg.sender;
        uint256 nitAmount = INitManager(nitManager).addLiquidityForAccount(address(this), account, weth, msg.value, _minUsd, _minNit);

        IRewardTracker(feeNitTracker).stakeForAccount(account, account, nit, nitAmount);

        emit StakeNit(account, nitAmount);

        return nitAmount;
    }

    function unstakeAndRedeemNit(address _tokenOut, uint256 _nitAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(_nitAmount > 0, "RewardRouter: invalid _nitAmount");

        address account = msg.sender;
       IRewardTracker(feeNitTracker).unstakeForAccount(account, nit, _nitAmount, account);
        uint256 amountOut = INitManager(nitManager).removeLiquidityForAccount(account, _tokenOut, _nitAmount, _minOut, _receiver);

        emit UnstakeNit(account, _nitAmount);

        return amountOut;
    }

    function unstakeAndRedeemNitETH(uint256 _nitAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_nitAmount > 0, "RewardRouter: invalid _nitAmount");

        address account = msg.sender;
        IRewardTracker(feeNitTracker).unstakeForAccount(account, nit, _nitAmount, account);
        uint256 amountOut = INitManager(nitManager).removeLiquidityForAccount(account, weth, _nitAmount, _minOut, address(this));

        IWETH10(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeNit(account, _nitAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeNitTracker).claimForAccount(account, account);
    }
    
    function handleRewards(
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

      if (_shouldConvertWethToEth) {
          uint256 weth1 = IRewardTracker(feeNitTracker).claimForAccount(account, address(this));

          IWETH10(weth).withdraw(weth1);

          payable(account).sendValue(weth1);
        } else {
          IRewardTracker(feeNitTracker).claimForAccount(account, account);
        }
    }





}
