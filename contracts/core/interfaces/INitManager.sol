// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface INitManager {
    function cooldownDuration() external returns (uint256);
    function lastAddedAt(address _account) external returns (uint256);
    function addLiquidity(address _token, uint256 _amount, uint256 _minUsd, uint256 _minNit) external returns (uint256);
    function addLiquidityForAccount(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsd, uint256 _minNit) external returns (uint256);
    function removeLiquidity(address _tokenOut, uint256 _nitAmount, uint256 _minOut, address _receiver) external returns (uint256);
    function removeLiquidityForAccount(address _account, address _tokenOut, uint256 _nitAmount, uint256 _minOut, address _receiver) external returns (uint256);
    function getAum(bool maximise) external view returns (uint256);
    function getTokenAum(address _token, bool maximise) external view returns (uint256);
}
