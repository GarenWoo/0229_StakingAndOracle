// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../src/Uniswap_v2_core/UniswapV2Pair.sol';

import {Test, console} from "forge-std/Test.sol";

contract ConsoleBytesCode_Customized_Test is Test {
    function setUp() public {
    }

    function test_ConsoleByteCode() public {
        bytes32 bytecode32 = keccak256(type(UniswapV2Pair).creationCode);
        console.log("The creationCode Hash of UniswapV2Pair is:");
        console.logBytes32(bytecode32);
        assertTrue(bytecode32.length > 0);
    }

}
