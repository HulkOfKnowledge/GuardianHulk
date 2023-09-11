// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/*
* @title GuardianHulkStableCoin
* @author HulkOfKnowledge
* Collateral: Exogenous (ETH & BTC)
* Minting: Algorithmic
* Relative Stability: Pegged to USD
*
* This contract is the ERC20 implementation of my stablecoin.
* This contract is governed by GuardianHulkEngine(The Engine Contract).
*/

contract GuardianHulkStableCoin is ERC20Burnable, Ownable  {
    error GuardianHulkStableCoin__LessThanZero();
    error GuardianHulkStableCoin__InsufficientFunds();
    error GuardianHulkStableCoin__InvalidAddress();

    constructor() ERC20("GuardianHulk","GDH") {}

    function burn(uint256 _amount) public override onlyOwner{
        uint256 balance = balanceOf(msg.sender);
        if (_amount<=0){
            revert GuardianHulkStableCoin__LessThanZero();
        }
        if (balance < _amount){
            revert GuardianHulkStableCoin__InsufficientFunds();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool){
        if (_to == address(0)){
            revert GuardianHulkStableCoin__InvalidAddress();
        }
        if (_amount<=0){
            revert GuardianHulkStableCoin__LessThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}