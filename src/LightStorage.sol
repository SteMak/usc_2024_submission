// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Storage status variations
enum KeyStatus {
    Empty,
    HashOnly,
    Loaded
}

// Persistent Storage Layout
// [compatibleKey] keccak256(data)

// Transient Storage Layout
// [compatibleKey]        data.length
// [compatibleKey + k]    data[(k - 1) * 0x20 : k * 0x20]    (0 < k <= data.length / 0x20)
// [compatibleKey + data.length / 0x20 + 1] 00..00 concat data[data.length / 0x20 * 0x20 : data.length]

/// @title LightStorage Library
/// @notice Combined storage abstraction. While actual data is processed in `transient` storage,
///   the data hash is put to `persistent` storage. This requires data to be stored off-chain and
///   partially loaded for each transaction execution.
/// @dev The keys used for combined storage are requred to be sufficiently far apart, such as those
///   generated by the `keccak256` function.
library LightStorage {
    error DataMismatchHash(bytes32 dataHash, bytes32 persistentHash);
    error DataNotLoaded(bytes32 persistentHash);
    error UnknownKey(bytes32 compatibleKey);

    event Write(bytes32 indexed compatibleKey, bytes data);

    /// @dev Writes a 32-byte value to `persistent` storage
    function _writeS(bytes32 key, bytes32 value) private {
        assembly {
            sstore(key, value)
        }
    }

    /// @dev Reads a 32-byte value from `persistent` storage
    function _readS(bytes32 key) private view returns (bytes32 value) {
        assembly {
            value := sload(key)
        }
    }

    /// @dev Writes data to `transient` storage, spreading it across multiple slots if necessary
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

    /// @dev Reads data from `transient` storage, reassembling it from multiple slots if necessary
    function _readT(bytes32 key) private view returns (bytes memory data) {
        uint256 length;
        assembly {
            length := tload(key)
            key := add(key, 0x01)
        }

        // Additional slot allocation as the code below potentially writes zeros to one more slot
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

    /// @notice Checks the status of combined storage at the key
    /// @return The status of the combined storage (Empty, HashOnly, or Loaded)
    function status(bytes32 compatibleKey) internal view returns (KeyStatus) {
        bytes32 persistentHash = _readS(compatibleKey);
        if (persistentHash == 0) return KeyStatus.Empty;

        bytes memory data = _readT(compatibleKey);

        bytes32 dataHash = keccak256(data);
        if (persistentHash == dataHash) return KeyStatus.Loaded;

        return KeyStatus.HashOnly;
    }

    /// @notice Loads data into `transient` storage, ensuring it matches the hash in `persistent` storage
    /// @dev Reverts if the `persistent` storage is empty or if the data does not match the hash
    function load(bytes32 compatibleKey, bytes memory data) internal {
        bytes32 persistentHash = _readS(compatibleKey);
        require(persistentHash != 0, UnknownKey(compatibleKey));

        bytes32 dataHash = keccak256(data);
        require(persistentHash == dataHash, DataMismatchHash(dataHash, persistentHash));

        _writeT(compatibleKey, data);
    }

    /// @notice Reads data from `transient` storage, ensuring it is loaded
    /// @dev Reverts if the `persistent` storage is empty or if the data is not loaded or is corrupted
    /// @return data The data stored in combined storage at the key
    function read(bytes32 compatibleKey) internal view returns (bytes memory data) {
        bytes32 persistentHash = _readS(compatibleKey);
        require(persistentHash != 0, UnknownKey(compatibleKey));

        data = _readT(compatibleKey);

        bytes32 dataHash = keccak256(data);
        require(persistentHash == dataHash, DataNotLoaded(persistentHash));
    }

    /// @notice Writes data to both `persistent` and `transient` storage
    function write(bytes32 compatibleKey, bytes memory data) internal {
        bytes32 dataHash = keccak256(data);

        _writeS(compatibleKey, dataHash);
        _writeT(compatibleKey, data);

        emit Write(compatibleKey, data);
    }
}
