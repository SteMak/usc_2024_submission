// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { LightVesting, Config } from "../src/LightVesting.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract VestingTest is Test {
    LightVesting vesting;
    MockERC20 token;

    function setUp() public {
        token = new MockERC20("Pops Lops", "OPL");
        vesting = new LightVesting(
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 700, 100, IERC20(address(token)))
        );
    }

    function test_basicFlow() public {}
}
