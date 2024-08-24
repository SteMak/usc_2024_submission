// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

enum KeyStatus {
    Empty,
    HashOnly,
    Loaded
}

library LightStorage {
    error DataMismatchHash(bytes32 dataHash, bytes32 persistentHash);
    error DataNotLoaded(bytes32 persistentHash);
    error UnknownKey(bytes32 compatibleHash);

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
            lastShift = 0x08 * (0x20 - (data.length % 0x20));
        }

        assembly {
            for {

            } iszero(eq(key, lastKey)) {
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
            lastShift = 0x08 * (0x20 - (length % 0x20));
        }
        assembly {
            let i := 0x20
            for {

            } iszero(eq(key, lastKey)) {
                i := add(i, 0x20)
                key := add(key, 0x01)
            } {
                mstore(add(data, i), tload(key))
            }
            mstore(add(data, i), shl(lastShift, tload(key)))
        }
    }

    function status(bytes32 compatibleKey) internal view returns (KeyStatus) {
        bytes32 persistentHash = _readS(compatibleKey);
        if (persistentHash == 0) return KeyStatus.Empty;

        bytes memory data = _readT(compatibleKey);

        bytes32 dataHash = keccak256(data);
        if (persistentHash == dataHash) return KeyStatus.Loaded;

        return KeyStatus.HashOnly;
    }

    function load(bytes32 compatibleKey, bytes memory data) internal {
        bytes32 persistentHash = _readS(compatibleKey);
        require(persistentHash != 0, UnknownKey(compatibleKey));

        bytes32 dataHash = keccak256(data);
        require(persistentHash == dataHash, DataMismatchHash(dataHash, persistentHash));

        _writeT(compatibleKey, data);
    }

    function read(bytes32 compatibleKey) internal view returns (bytes memory data) {
        bytes32 persistentHash = _readS(compatibleKey);
        require(persistentHash != 0, UnknownKey(compatibleKey));

        data = _readT(compatibleKey);

        bytes32 dataHash = keccak256(data);
        require(persistentHash == dataHash, DataNotLoaded(persistentHash));
    }

    function write(bytes32 compatibleKey, bytes memory data) internal {
        bytes32 dataHash = keccak256(data);

        _writeS(compatibleKey, dataHash);
        _writeT(compatibleKey, data);
    }
}
