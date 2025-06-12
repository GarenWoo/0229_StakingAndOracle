// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract KKToken is ERC20 {
    address public immutable owner;

    error NotOwner(address caller);

    event TokenMinted(address recipient, uint256 amount, uint256 timestamp);
    event TokenBurnt(address sender, uint256 amount, uint256 timestamp);

    constructor() ERC20("KK Token", "KKT") {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
        _;
    }

    function mint(address _recipient, uint256 _amount) external onlyOwner {
        _mint(_recipient, _amount);
        emit TokenMinted(_recipient, _amount, block.timestamp);
    }

    function burn(address _account, uint256 _amount) external onlyOwner {
        _burn(_account, _amount);
        emit TokenBurnt(_account, _amount, block.timestamp);
    }

}
