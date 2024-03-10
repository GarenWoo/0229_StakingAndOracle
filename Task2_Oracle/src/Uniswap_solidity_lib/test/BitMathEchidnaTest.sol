// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../libraries/BitMath.sol';

contract BitMathEchidnaTest {
    function mostSignificantBitInvariant(uint256 input) external pure {
        uint8 msb = BitMath.mostSignificantBit(input);
        assert(input >= (uint256(2)**msb));
        assert(msb == 255 || input < uint256(2)**(msb + 1));
    }
}
