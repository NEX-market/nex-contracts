// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IFastPriceEvents {
    function emitPriceEvent(address _token, uint256 _price) external;
}
