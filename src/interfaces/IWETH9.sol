//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address guy, uint256 wad) external returns (bool);
    function transfer(address dst, uint256 wad) external returns (bool);
    function totalSupply() external view returns (uint256);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}
