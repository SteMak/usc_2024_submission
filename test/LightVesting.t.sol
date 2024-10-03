// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { LightVesting, Config, Vesting } from "../src/LightVesting.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract VestingTest is Test {
    LightVesting vesting;
    IERC20 token;

    uint256 max_amount = 10 ** 9 * 10 ** 18;
    uint256 max_period = 5 * 52 weeks;

    Config config;

    address userA = vm.addr(0x15);
    address userB = vm.addr(0x17);

    function setUp() public {
        token = IERC20(address(new MockERC20("Pops Lops", "OPL")));
        config = Config(address(this), max_amount, max_period, 70000, 100, token);
        vesting = new LightVesting(config);
    }

    function test_config() public {
        vm.expectRevert();
        vesting.configurate(config);

        vesting.configurate(config, config);
        vesting.configurate(config, config);

        vm.prank(userA);
        vm.expectRevert();
        vesting.configurate(config);

        vm.expectRevert();
        vesting.configurate(Config(address(this), max_amount, max_period, 70000, 100, IERC20(vm.addr(0x99))));

        vm.expectRevert();
        vesting.configurate(Config(address(this), max_amount, max_period, 70000, 1001, token));

        vm.expectRevert();
        vesting.configurate(Config(address(this), max_amount, max_period, 100001, 100, token));

        vesting.configurate(Config(userA, 0, 0, 100000, 1000, token));

        Config memory conf = vesting.getConfig(vesting.CONFIG_KEY());
        assertEq(conf.admin, userA);
        assertEq(conf.fee, 1000);
        assertEq(conf.maxAmount, 0);
        assertEq(conf.maxCliffPercent, 100000);
        assertEq(address(conf.token), address(token));
        assertEq(conf.maxDuration, 0);

        vm.expectRevert();
        vesting.configurate(Config(userA, 0, 0, 100000, 1000, token));

        vm.prank(userA);
        vesting.configurate(Config(address(this), max_amount * 100, max_period * 100, 70000, 100, token));
    }

    function test_basics() public {
        uint256 amount = 100000000;
        MockERC20(address(token)).mint(address(this), type(uint256).max);
        token.approve(address(vesting), type(uint256).max);

        bytes32 key = vesting.create(userA, 17, (amount * 100000) / 99900, block.timestamp, 1000, 500, config);

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

    function test_basics_fuzz(uint256 amount, uint32 duration) public {
        vm.assume(amount <= config.maxAmount);
        vm.assume(duration <= config.maxDuration);

        MockERC20(address(token)).mint(address(this), type(uint256).max);
        token.approve(address(vesting), type(uint256).max);

        vesting.loadConfig(vesting.CONFIG_KEY(), config);
        config.admin = userB;
        vesting.configurate(config);

        uint256 start = vm.getBlockTimestamp();
        uint256 fee = amount * config.fee / vesting.DENOM();

        bytes32 key = vesting.create(userA, block.timestamp, amount, start, duration, duration / 2);

        assertEq(token.balanceOf(address(this)), type(uint256).max - amount);
        assertEq(token.balanceOf(userB), fee);
        assertEq(token.balanceOf(userA), 0);

        Vesting memory vest = vesting.getVesting(key);
        assertEq(vest.amount, amount - fee);
        assertEq(vest.claimed, 0);
        assertEq(vest.start, start);
        assertEq(vest.cliff, duration/2);
        assertEq(vest.user, userA);
        assertEq(vest.duration, duration);

        vm.startPrank(userA);

        if (duration >= 1) {
            vm.warp(start + duration / 4);
            vesting.withdraw(key);
            assertEq(token.balanceOf(userA), 0);

            vm.warp(start + duration / 2);
            vesting.withdraw(key);
            assertEq(token.balanceOf(userA), (amount - fee) * (duration / 2) / duration);

            vm.warp(start + duration * 3 / 4);
            vesting.withdraw(key);
            assertEq(token.balanceOf(userA), (amount - fee) * (duration * 3 / 4) / duration);
        }

        vm.warp(start + duration * 2);
        vesting.withdraw(key);
        assertEq(token.balanceOf(userA), (amount - fee));

        vm.stopPrank();
    }
}
