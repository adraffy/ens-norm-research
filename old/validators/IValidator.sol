// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

interface IValidator {
    //function name() external view returns (string);
    function validate(uint24[] memory cps) external view;
}