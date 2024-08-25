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

    address userA = address(0x15);
    address userB = address(0x17);

    function setUp() public {
        token = new MockERC20("Pops Lops", "OPL");
        vesting = new LightVesting(
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(address(token)))
        );
    }

    function test_config() public {
        vm.expectRevert();
        vesting.configurate(
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(address(token)))
        );

        vesting.configurate(
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(address(token))),
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(address(token)))
        );

        vesting.configurate(
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(address(token))),
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(address(token)))
        );

        vm.prank(userA);
        vm.expectRevert();
        vesting.configurate(
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(address(token)))
        );

        vm.expectRevert();
        vesting.configurate(Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(userB)));

        vm.expectRevert();
        vesting.configurate(
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 1001, IERC20(address(token)))
        );

        vm.expectRevert();
        vesting.configurate(
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 100001, 100, IERC20(address(token)))
        );

        vesting.configurate(Config(userA, 0, 100 * 52 weeks, 10000, 1000, IERC20(address(token))));

        vm.expectRevert();
        vesting.configurate(Config(userA, 0, 100 * 52 weeks, 10000, 1000, IERC20(address(token))));

        vm.prank(userA);
        vesting.configurate(Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 1000, 100, IERC20(address(token))));
    }

    function test_basicFlow() public {
        uint256 amount = 100000000;
        token.mint(address(this), amount);
        token.approve(address(vesting), amount);

        bytes32 key = vesting.create(
            userA,
            17,
            amount,
            block.timestamp,
            1000,
            500,
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(address(token)))
        );

        vm.expectRevert();
        vesting.create(userA, 17, 0, block.timestamp, 1000, 500);

        vesting.create(userA, 18, 0, block.timestamp, 1000, 500);
        vesting.create(userB, 17, 0, block.timestamp, 1000, 500);

        vm.startPrank(userA);
        vm.warp(block.timestamp + 300);
        vesting.withdraw(key);

        assertEq(token.balanceOf(userA), 0);

        vm.warp(block.timestamp + 200);

        vm.startPrank(userB);
        vm.expectRevert();
        vesting.withdraw(key);

        vm.startPrank(userA);
        vesting.withdraw(key);

        assertEq(token.balanceOf(userA), amount / 2);

        vm.warp(block.timestamp + 1500);
        vesting.withdraw(key);

        assertEq(token.balanceOf(userA), amount);
    }

    function test_rugpull() public {
        uint256 amount = 10 ** 8 * 10 ** 18;

        vm.startPrank(userA);
        token.mint(userA, amount * 100);
        token.approve(address(vesting), amount * 100);

        vesting.loadConfig(
            vesting.CONFIG_KEY(),
            Config(address(this), 10 ** 9 * 10 ** 18, 5 * 52 weeks, 70000, 100, IERC20(address(token)))
        );

        for (uint160 i = 0; i < 100; i++) {
            vesting.create(address(i), 17, amount, block.timestamp + i, 52 weeks, 10 weeks);
        }
        vm.stopPrank();

        vesting.configurate(Config(address(this), amount * 100, 0, 0, 0, IERC20(address(token))));
        vesting.withdraw(vesting.CONFIG_KEY());

        assertEq(token.balanceOf(address(this)), amount * 100);
    }
}
