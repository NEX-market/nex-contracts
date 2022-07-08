// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/IERC20Metadata.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IVault.sol";
import "./interfaces/INitManager.sol";
import "../tokens/interfaces/IMintable.sol";
import "../access/Governable.sol";

pragma solidity 0.8.11;

contract NitManager is ReentrancyGuard, Governable, INitManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant USD_DECIMALS = 30;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;

    IVault public vault;
    address public nit;

    uint256 public override cooldownDuration;
    mapping (address => uint256) public override lastAddedAt;

    uint256 public aumAddition;
    uint256 public aumDeduction;

    bool public inPrivateMode;
    mapping (address => bool) public isHandler;

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInUsd,
        uint256 nitSupply,
        uint256 usdAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 nitAmount,
        uint256 aumInUsd,
        uint256 nitSupply,
        uint256 usdAmount,
        uint256 amountOut
    );

    constructor(address _vault, address _nit, uint256 _cooldownDuration) {
        gov = msg.sender;
        vault = IVault(_vault);
        nit = _nit;
        cooldownDuration = _cooldownDuration;
    }

    function setInPrivateMode(bool _inPrivateMode) external onlyGov {
        inPrivateMode = _inPrivateMode;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    function setCooldownDuration(uint256 _cooldownDuration) external onlyGov {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "NitManager: invalid _cooldownDuration");
        cooldownDuration = _cooldownDuration;
    }

    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyGov {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function addLiquidity(address _token, uint256 _amount, uint256 _minUsd, uint256 _minNit) external override nonReentrant returns (uint256) {
        if (inPrivateMode) { revert("NitManager: action not enabled"); }
        return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minUsd, _minNit);
    }

    function addLiquidityForAccount(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsd, uint256 _minNit) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _addLiquidity(_fundingAccount, _account, _token, _amount, _minUsd, _minNit);
    }

    function removeLiquidity(address _tokenOut, uint256 _nitAmount, uint256 _minOut, address _receiver) external override nonReentrant returns (uint256) {
        if (inPrivateMode) { revert("NitManager: action not enabled"); }
        return _removeLiquidity(msg.sender, _tokenOut, _nitAmount, _minOut, _receiver);
    }

    function removeLiquidityForAccount(address _account, address _tokenOut, uint256 _nitAmount, uint256 _minOut, address _receiver) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _removeLiquidity(_account, _tokenOut, _nitAmount, _minOut, _receiver);
    }

    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    function getAum(bool maximise) public override view returns (uint256) {
        uint256 length = vault.allWhitelistedTokensLength();
        uint256 aum = aumAddition;

        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            bool isWhitelisted = vault.whitelistedTokens(token);

            if (!isWhitelisted) {
                continue;
            }
            uint256 tokenAum = getTokenAum(token, maximise);
            aum = aum + tokenAum;
        }

        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);
    }

    // returns 30 decimals
    function getTokenAum(address _token, bool maximise) public override view returns(uint256) {
        bool isWhitelisted = vault.whitelistedTokens(_token);
        
        if (!isWhitelisted) {
            return 0;
        }

        uint256 price = maximise ? vault.getMaxPrice(_token) : vault.getMinPrice(_token);
        uint256 poolAmount = vault.poolAmounts(_token);
        uint256 decimals = vault.tokenDecimals(_token);
        uint256 tokenAum;
        uint256 shortProfits;

        if (vault.stableTokens(_token)) {
            tokenAum = tokenAum.add(poolAmount.mul(price).div(10 ** decimals));
        } else {
            uint256 size = vault.globalShortSizes(_token);
            if (size > 0) {
                uint256 averagePrice = vault.globalShortAveragePrices(_token);
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = size.mul(priceDelta).div(averagePrice);
                if (price > averagePrice) {
                    tokenAum = tokenAum.add(delta);
                } else {
                    shortProfits = shortProfits.add(delta);
                }
            }
            tokenAum = tokenAum.add(vault.guaranteedUsd(_token));

            uint256 reservedAmount = vault.reservedAmounts(_token);
            tokenAum = tokenAum.add(poolAmount.sub(reservedAmount).mul(price).div(10 ** decimals));
        }
        
        tokenAum = shortProfits > tokenAum ? 0 : tokenAum.sub(shortProfits);
        return tokenAum;
    }

    function _addLiquidity(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsd, uint256 _minNit) private returns (uint256) {
        require(_amount > 0, "NitManager: invalid _amount");

        // calculate aum before buyUSD
        uint256 aumInUsd = getAum(true);
        uint256 nitSupply = IERC20(nit).totalSupply();

        IERC20(_token).safeTransferFrom(_fundingAccount, address(vault), _amount);
        uint256 usdAmount = vault.buy(_token, address(this));
        require(usdAmount >= _minUsd, "NitManager: insufficient USD output");

        uint256 decimals = IERC20Metadata(nit).decimals();
        uint256 mintAmount = aumInUsd == 0 ? usdAmount.mul(10 ** decimals).div(10 ** USD_DECIMALS) : usdAmount.mul(nitSupply).div(aumInUsd);
        require(mintAmount >= _minNit, "NitManager: insufficient NIT output");

        IMintable(nit).mint(_account, mintAmount);

        lastAddedAt[_account] = block.timestamp;

        emit AddLiquidity(_account, _token, _amount, aumInUsd, nitSupply, usdAmount, mintAmount);

        return mintAmount;
    }

    function _removeLiquidity(address _account, address _tokenOut, uint256 _nitAmount, uint256 _minOut, address _receiver) private returns (uint256) {
        require(_nitAmount > 0, "NitManager: invalid _nitAmount");
        require(lastAddedAt[_account].add(cooldownDuration) <= block.timestamp, "NitManager: cooldown duration not yet passed");

        // calculate aum before sell
        uint256 aumInUsd = getAum(false);
        uint256 nitSupply = IERC20(nit).totalSupply();

        uint256 usdAmount = _nitAmount.mul(aumInUsd).div(nitSupply);

        IMintable(nit).burn(_account, _nitAmount);

        uint256 amountOut = vault.sell(_tokenOut, _receiver, usdAmount);
        require(amountOut >= _minOut, "NitManager: insufficient output");

        emit RemoveLiquidity(_account, _tokenOut, _nitAmount, aumInUsd, nitSupply, usdAmount, amountOut);

        return amountOut;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "NitManager: forbidden");
    }
}
