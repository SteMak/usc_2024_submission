// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LightStorage {
    function _writeS(bytes32 key, bytes32 value) private {
        assembly {
            sstore(key, value)
        }
    }

    function _readS(bytes32 key) private view returns (bytes32 value) {
        assembly {
            value := sload(key)
        }
    }

    function _writeT(bytes32 key, bytes memory data) private {
        bytes32 lastKey;
        uint256 lastShift;
        unchecked {
            uint256 fullSlots = 0x01 + data.length / 0x20;
            lastKey = bytes32(uint256(key) + fullSlots);
            lastShift = 0x08 * (0x20 - data.length % 0x20);
        }

        assembly {
            for {} iszero(eq(key, lastKey)) {
                data := add(data, 0x20)
                key := add(key, 0x01)
            } {
                tstore(key, mload(data))
            }
            tstore(key, shr(lastShift, mload(data)))
        }
    }

    function _readT(bytes32 key) private view returns (bytes memory data) {
        uint256 length;
        assembly {
            length := tload(key)
            key := add(key, 0x01)
        }

        data = new bytes(0x20 + length);
        assembly {
            mstore(data, length)
        }

        bytes32 lastKey;
        uint256 lastShift;
        unchecked {
            uint256 fullSlots = length / 0x20;
            lastKey = bytes32(uint256(key) + fullSlots);
            lastShift = 0x08 * (0x20 - length % 0x20);
        }
        assembly {
            let i := 0x20
            for {} iszero(eq(key, lastKey)) {
                i := add(i, 0x20)
                key := add(key, 0x01)
            } {
                mstore(add(data, i), tload(key))
            }
            mstore(add(data, i), shl(lastShift, tload(key)))
        }
    }

    /// @dev set `data` to transient storage under `compatibleKey` validating `hash(data)` matches persistent hash in storage under `compatibleKey`
    function load(bytes32 compatibleKey, bytes memory data) internal {
        bytes32 dataHash = keccak256(data);
        bytes32 persistentHash = _readS(compatibleKey);
        require(persistentHash == dataHash);

        _writeT(compatibleKey, data);
    }

    function read(bytes32 compatibleKey) internal view returns (bytes memory data) {
        data = _readT(compatibleKey);

        bytes32 dataHash = keccak256(data);
        bytes32 persistentHash = _readS(compatibleKey);
        require(persistentHash == dataHash);
    }

    /// @dev update transient storage and persistent hash
    function write(bytes32 compatibleKey, bytes memory data) internal {
        bytes32 dataHash = keccak256(data);

        _writeS(compatibleKey, dataHash);
        _writeT(compatibleKey, data);
    }
}
