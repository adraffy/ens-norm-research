// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

contract Test {

    function validate(uint24[] memory v) public pure returns (uint24[] memory u) {
        function (uint24[] memory, uint256) pure returns (uint256) f = state0;
        uint256 i;
        while (i < v.length) {
            uint256 next = f(v, i);
            assembly {
                f := next
                i := add(i, 1)
            }
        }
        u = v;
    }

    function ptr(function (uint24[] memory, uint256) private pure returns (uint256) f) private pure returns (uint256 offset) {
        assembly {
            offset := f
        }
    }

    function state0(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        cps[pos] = 10;
        next = ptr(state1);
    }

    function state1(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        cps[pos] = 20;
        next = ptr(state0);
    }

}