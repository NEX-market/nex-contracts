// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../core/interfaces/INitManager.sol";
import "./interfaces/IRewardTracker.sol";

contract StakedNit {
    using SafeMath for uint256;

    string public constant name = "StakedNit";
    string public constant symbol = "sNIT";
    uint8 public constant decimals = 18;

    address public nit;
    INitManager public nitManager;
    address public feeNitTracker;

    mapping (address => mapping (address => uint256)) private _allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        address _nit,
        INitManager _nitManager,
        address _feeNitTracker
    ) {
        nit = _nit;
        nitManager = _nitManager;
        feeNitTracker = _feeNitTracker;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return _allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 nextAllowance = _allowances[_sender][msg.sender].sub(_amount, "StakedNit: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function balanceOf(address _account) external view returns (uint256) {
        IRewardTracker(feeNitTracker).depositBalances(_account, nit);
    }

    function totalSupply() external view returns (uint256) {
        IERC20(feeNitTracker).totalSupply();
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "StakedNit: approve from the zero address");
        require(_spender != address(0), "StakedNit: approve to the zero address");

        _allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "StakedNit: transfer from the zero address");
        require(_recipient != address(0), "StakedNit: transfer to the zero address");

        require(
            nitManager.lastAddedAt(_sender).add(nitManager.cooldownDuration()) <= block.timestamp,
            "StakedNit: cooldown duration not yet passed"
        );

        IRewardTracker(feeNitTracker).unstakeForAccount(_sender, nit, _amount, _sender);

        IRewardTracker(feeNitTracker).stakeForAccount(_sender, _recipient, nit, _amount);
    }

    
}