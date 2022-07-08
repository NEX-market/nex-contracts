// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "../core/interfaces/IVault.sol";
import "../core/interfaces/IVaultPriceFeed.sol";
import "../core/interfaces/IBasePositionManager.sol";

contract VaultReader {
    function getVaultTokenInfoV3(address _vault, address _positionManager, address _weth, uint256 _usdAmount, address[] memory _tokens) public view returns (uint256[] memory) {
        uint256 propsLength = 13;

        IVault vault = IVault(_vault);
        IVaultPriceFeed priceFeed = IVaultPriceFeed(vault.priceFeed());
        IBasePositionManager positionManager = IBasePositionManager(_positionManager);

        uint256[] memory amounts = new uint256[](_tokens.length * propsLength);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                token = _weth;
            }

            amounts[i * propsLength] = vault.poolAmounts(token);
            amounts[i * propsLength + 1] = vault.reservedAmounts(token);
            amounts[i * propsLength + 2] = vault.getTokenAum(token);
            amounts[i * propsLength + 3] = vault.getRedemptionAmount(token, _usdAmount);
            amounts[i * propsLength + 4] = vault.tokenWeights(token);
            amounts[i * propsLength + 5] = vault.bufferAmounts(token);
            amounts[i * propsLength + 6] = vault.globalShortSizes(token);
            amounts[i * propsLength + 7] = positionManager.maxGlobalShortSizes(token);
            amounts[i * propsLength + 8] = vault.getMinPrice(token);
            amounts[i * propsLength + 9] = vault.getMaxPrice(token);
            amounts[i * propsLength + 10] = vault.guaranteedUsd(token);
            amounts[i * propsLength + 11] = priceFeed.getPrimaryPrice(token, false);
            amounts[i * propsLength + 12] = priceFeed.getPrimaryPrice(token, true);
        }

        return amounts;
    }

    function getVaultTokenInfoV4(address _vault, address _positionManager, address _weth, uint256 _usdAmount, address[] memory _tokens) public view returns (uint256[] memory) {
        uint256 propsLength = 14;

        IVault vault = IVault(_vault);
        IVaultPriceFeed priceFeed = IVaultPriceFeed(vault.priceFeed());
        IBasePositionManager positionManager = IBasePositionManager(_positionManager);

        uint256[] memory amounts = new uint256[](_tokens.length * propsLength);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                token = _weth;
            }

            amounts[i * propsLength] = vault.poolAmounts(token);
            amounts[i * propsLength + 1] = vault.reservedAmounts(token);
            amounts[i * propsLength + 2] = vault.getTokenAum(token);
            amounts[i * propsLength + 3] = vault.getRedemptionAmount(token, _usdAmount);
            amounts[i * propsLength + 4] = vault.tokenWeights(token);
            amounts[i * propsLength + 5] = vault.bufferAmounts(token);
            amounts[i * propsLength + 6] = vault.globalShortSizes(token);
            amounts[i * propsLength + 7] = positionManager.maxGlobalShortSizes(token);
            amounts[i * propsLength + 8] = positionManager.maxGlobalLongSizes(token);
            amounts[i * propsLength + 9] = vault.getMinPrice(token);
            amounts[i * propsLength + 10] = vault.getMaxPrice(token);
            amounts[i * propsLength + 11] = vault.guaranteedUsd(token);
            amounts[i * propsLength + 12] = priceFeed.getPrimaryPrice(token, false);
            amounts[i * propsLength + 13] = priceFeed.getPrimaryPrice(token, true);
        }

        return amounts;
    }
}