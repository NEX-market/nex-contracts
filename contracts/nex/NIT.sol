// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "../tokens/MintableBaseToken.sol";

contract NIT is MintableBaseToken {
    constructor() MintableBaseToken("NEX Index Token", "NIT", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "NIT";
    }
}
