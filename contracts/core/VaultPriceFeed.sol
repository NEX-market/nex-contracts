// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";

import "./interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../oracle/interfaces/ISecondaryPriceFeed.sol";
import "../amm/interfaces/ITrisolarisPair.sol";
import "../amm/interfaces/IAmmOracle.sol";

pragma solidity 0.8.11;

contract VaultPriceFeed is IVaultPriceFeed {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant ONE_USD = PRICE_PRECISION;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours;
    uint256 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20;

    // Identifier of the Sequencer offline flag on the Flags contract

    address public gov;

    bool public isAmmEnabled = true;
    bool public isSecondaryPriceEnabled = true;
    bool public useV2Pricing = false;
    bool public favorPrimaryPrice = false;
    uint256 public priceSampleSpace = 3;
    uint256 public maxStrictPriceDeviation = 0;
    address public secondaryPriceFeed;
    uint256 public spreadThresholdBasisPoints = 30;

    address public near;
    address public eth;
    
    IAmmOracle public nearAmmOracle;
    IAmmOracle public ethAmmOracle;

    mapping (address => address) public priceFeeds;
    mapping (address => uint256) public priceDecimals;
    mapping (address => uint256) public spreadBasisPoints;
    // Flux can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping (address => bool) public strictStableTokens;

    mapping (address => uint256) public override adjustmentBasisPoints;
    mapping (address => bool) public override isAdjustmentAdditive;
    mapping (address => uint256) public lastAdjustmentTimings;

    modifier onlyGov() {
        require(msg.sender == gov, "VaultPriceFeed: forbidden");
        _;
    }

    constructor() {
        gov = msg.sender;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }


    function setAdjustment(address _token, bool _isAdditive, uint256 _adjustmentBps) external override onlyGov {
        require(
            lastAdjustmentTimings[_token].add(MAX_ADJUSTMENT_INTERVAL) < block.timestamp,
            "VaultPriceFeed: adjustment frequency exceeded"
        );
        require(_adjustmentBps <= MAX_ADJUSTMENT_BASIS_POINTS, "invalid _adjustmentBps");
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        lastAdjustmentTimings[_token] = block.timestamp;
    }

    function setUseV2Pricing(bool _useV2Pricing) external override onlyGov {
        useV2Pricing = _useV2Pricing;
    }

    function setIsAmmEnabled(bool _isEnabled) external override onlyGov {
        isAmmEnabled = _isEnabled;
    }

    function setIsSecondaryPriceEnabled(bool _isEnabled) external override onlyGov {
        isSecondaryPriceEnabled = _isEnabled;
    }

    function setSecondaryPriceFeed(address _secondaryPriceFeed) external onlyGov {
        secondaryPriceFeed = _secondaryPriceFeed;
    }

    function setTokens(address _near, address _eth) external onlyGov {
        near = _near;
        eth = _eth;
    }

    function setNearAmmOracle(IAmmOracle _nearAmmOracle) external onlyGov {
        nearAmmOracle = _nearAmmOracle;
    }

    function setEthAmmOracle(IAmmOracle _ethAmmOracle) external onlyGov {
        ethAmmOracle = _ethAmmOracle;
    }

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external override onlyGov {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "VaultPriceFeed: invalid _spreadBasisPoints");
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints) external override onlyGov {
        spreadThresholdBasisPoints = _spreadThresholdBasisPoints;
    }

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external override onlyGov {
        favorPrimaryPrice = _favorPrimaryPrice;
    }

    function setPriceSampleSpace(uint256 _priceSampleSpace) external override onlyGov {
        require(_priceSampleSpace > 0, "VaultPriceFeed: invalid _priceSampleSpace");
        priceSampleSpace = _priceSampleSpace;
    }

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external override onlyGov {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }

    function setTokenConfig(
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external override onlyGov {
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        strictStableTokens[_token] = _isStrictStable;
    }

    function getPrice(address _token, bool _maximise, bool _includeAmmPrice) public override view returns (uint256) {
        
        uint256 price = useV2Pricing ? getPriceV2(_token, _maximise, _includeAmmPrice) : getPriceV1(_token, _maximise, _includeAmmPrice);
        
        uint256 adjustmentBps = adjustmentBasisPoints[_token];
        
        if (adjustmentBps > 0) { 
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) { 
                price = price.mul(BASIS_POINTS_DIVISOR.add(adjustmentBps)).div(BASIS_POINTS_DIVISOR);
            } else { 
                price = price.mul(BASIS_POINTS_DIVISOR.sub(adjustmentBps)).div(BASIS_POINTS_DIVISOR);
            }
        }

        return price; 
    }


    function getPriceV1(address _token, bool _maximise, bool _includeAmmPrice) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise); 

        if (_includeAmmPrice && isAmmEnabled) {
            uint256 ammPrice = getAmmPrice(_token); 
            if (ammPrice > 0) {
                if (_maximise && ammPrice > price) { 
                    price = ammPrice;
                }
                if (!_maximise && ammPrice < price) { 
                    price = ammPrice;
                }
            }
        }

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise); 
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price.sub(ONE_USD) : ONE_USD.sub(price);
            if (delta <= maxStrictPriceDeviation) { 
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return price.mul(BASIS_POINTS_DIVISOR.add(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
        }

        return price.mul(BASIS_POINTS_DIVISOR.sub(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
    }

    function getPriceV2(address _token, bool _maximise, bool _includeAmmPrice) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (_includeAmmPrice && isAmmEnabled) {
            price = getAmmPriceV2(_token, _maximise, price);
        }

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price.sub(ONE_USD) : ONE_USD.sub(price);
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return price.mul(BASIS_POINTS_DIVISOR.add(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
        }

        return price.mul(BASIS_POINTS_DIVISOR.sub(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
    }

    function getAmmPriceV2(address _token, bool _maximise, uint256 _primaryPrice) public view returns (uint256) {
        uint256 ammPrice = getAmmPrice(_token);
        if (ammPrice == 0) { 
            return _primaryPrice; 
        }
        uint256 diff = ammPrice > _primaryPrice ? ammPrice.sub(_primaryPrice) : _primaryPrice.sub(ammPrice);
        if (diff.mul(BASIS_POINTS_DIVISOR) < _primaryPrice.mul(spreadThresholdBasisPoints)) {
            if (favorPrimaryPrice) { 
                return _primaryPrice;
            }
            return ammPrice;
        }

        if (_maximise && ammPrice > _primaryPrice) {
            return ammPrice;
        }

        if (!_maximise && ammPrice < _primaryPrice) {
            return ammPrice;
        }

        return _primaryPrice;
    }

    function getPrimaryPrice(address _token, bool _maximise) public override view returns (uint256) {
        address priceFeedAddress = priceFeeds[_token]; 
        require(priceFeedAddress != address(0), "VaultPriceFeed: invalid price feed");

         
        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress); 

        uint256 price = 0;
        uint80 roundId = priceFeed.latestRound();

        for (uint80 i = 0; i < priceSampleSpace; i++) { 
            if (roundId <= i) { break; } 
            uint256 p;

            if (i == 0) {
                int256 _p = priceFeed.latestAnswer(); 
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            } else {
                (, int256 _p, , ,) = priceFeed.getRoundData(roundId - i);
                
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            }

            if (price == 0) {
                price = p;
                continue;
            }

            if (_maximise && p > price) { 
                price = p;
                continue;
            }

            if (!_maximise && p < price) { 
                price = p;
            }
        } 

        require(price > 0, "VaultPriceFeed: could not fetch price");
        // normalise price precision
        uint256 _priceDecimals = priceDecimals[_token]; 
        return price.mul(PRICE_PRECISION).div(10 ** _priceDecimals); 
    }

    function getSecondaryPrice(address _token, uint256 _referencePrice, bool _maximise) public view returns (uint256) {
        if (secondaryPriceFeed == address(0)) { return _referencePrice; } 
        
        return ISecondaryPriceFeed(secondaryPriceFeed).getPrice(_token, _referencePrice, _maximise);
    }

    // set isAmmEnabled to true to apply TWAP
    // apply only if ETH/USDC, NEAR/USDC pairs have enough liquidities
    function getAmmPrice(address _token) public override view returns (uint256) {
        if (_token == near) {
            return nearAmmOracle.consult(_token, 10 ** 18).mul(PRICE_PRECISION);
        }

        if (_token == eth) {
            return ethAmmOracle.consult(_token, 10 ** 12).mul(PRICE_PRECISION);
        }

        return 0;
    }

    // if divByReserve0: calculate price as reserve1 / reserve0
    // if !divByReserve1: calculate price as reserve0 / reserve1
    function getPairPrice(address _pair, bool _divByReserve0) public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = ITrisolarisPair(_pair).getReserves();
        if (_divByReserve0) {
            if (reserve0 == 0) { return 0; }
            return reserve1.mul(PRICE_PRECISION).div(reserve0);
        }
        if (reserve1 == 0) { return 0; }
        return reserve0.mul(PRICE_PRECISION).div(reserve1);
    }
}
