// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LightStorage} from "../src/LightStorage.sol";

contract Implementation {
    function load(bytes32 compatibleKey, bytes memory data) external {
        LightStorage.load(compatibleKey, data);
    }

    function read(bytes32 compatibleKey) external view returns (bytes memory data) {
        return LightStorage.read(compatibleKey);
    }

    /// @dev update transient storage and persistent hash
    function write(bytes32 compatibleKey, bytes memory data) external {
        LightStorage.write(compatibleKey, data);
    }

    function drop(bytes32 compatibleKey) external {
        assembly {
            tstore(compatibleKey, add(tload(compatibleKey), 1))
        }
    }
}

contract LightStorageTest is Test {
    Implementation impl;

    function setUp() public {
        impl = new Implementation();
    }

    function test_basicFlow() public {
        bytes32 key = bytes32(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);
        bytes memory data = hex"7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabb";

        vm.expectRevert();
        impl.load(key, data);

        impl.write(key, data);

        bytes memory retrieved = impl.read(key);
        assertEq(data, retrieved);

        impl.drop(key);
        vm.expectRevert();
        impl.read(key);

        vm.expectRevert();
        impl.load(key, hex"7788aabbccddeeff");

        impl.load(key, data);

        bytes memory retrieved_again = impl.read(key);
        assertEq(data, retrieved_again);
    }

    function test_basicFlow(bytes32 key) public {
        bytes memory data = hex"7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabbccddeeff7788aabb";

        vm.expectRevert();
        impl.load(key, data);

        impl.write(key, data);

        bytes memory retrieved = impl.read(key);
        assertEq(data, retrieved);

        impl.drop(key);
        vm.expectRevert();
        impl.read(key);

        vm.expectRevert();
        impl.load(key, hex"7788aabbccddeeff");

        impl.load(key, data);

        bytes memory retrieved_again = impl.read(key);
        assertEq(data, retrieved_again);
    }

    function test_basicFlow(bytes32 key, bytes memory data) public {
        vm.expectRevert();
        impl.load(key, data);

        impl.write(key, data);

        bytes memory retrieved = impl.read(key);
        assertEq(data, retrieved);

        impl.drop(key);
        vm.expectRevert();
        impl.read(key);

        assembly {
            mstore(data, add(mload(data), 1))
        }
        vm.expectRevert(); 
        impl.load(key, data);
        assembly {
            mstore(data, sub(mload(data), 1))
        }

        impl.load(key, data);

        bytes memory retrieved_again = impl.read(key);
        assertEq(data, retrieved_again);
    }
}
