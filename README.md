# Underhanded Solidity Contest 2024 Submission

## Idea / Use-cases

The implementation of `transient` storage enables an efficient ability to create lightweight smart contracts. Lightweight means that only a data hash is stored in `persistent` storage, while any data needed by transactions is attached additionally. The `transient` storage is accessible from different execution contexts, which allows the division of responsibility between preloading data and the requests execution. Additionally, this provides significant optimization opportunities, as the data can be loaded once per a batch transaction, and possibly can be integrated with the transaction access lists in the far future.

### Composability

The idea involves `transient` storage being retained after the execution context ends, which may potentially cause composability issues. To address this, the implementation __MUST__ process any __sequence of calls that succeed in isolated execution__ in the same way, regardless of whether the calls are executed in isolation or not. This ensures backward compatibility and enables the contract to provide __additional__ functionality based on `transient` storage utilization.

To satisfy this condition, it is enough to ensure any succesfull isolated call executes `tstore(key, ...)` prior to `tload(key)`. As each accessed data slot is rewritten before the read, any data in `transient` storage does not impact the execution. Thus, the call can be safely composed with other ones.

## Submission

The submission consists of the following components:
- The `LightStorage` library, which wraps all `transient` storage operations and provides a simple interface for reading and writing `bytes memory` data.
- The `LightStorageIntegration` abstract contract, which wraps `LightStorage` library functions to process specific structs instead of raw byte arrays.
- The `LightVesting` target contract, which allows users to create and claim vestings of a specified token and implements a __RUG PULL__ possibility (hope you'll be happy to find it).

## Light Storage

More details on how the `LightStorage` library works:
- `write(bytes32 combinedKey, bytes memory data)` stores the `data hash` at `combinedKey` in `persistent` storage and stores the `data` at `combinedKey` (and subsequent slots) in `transient` storage.
- `load(bytes32 combinedKey, bytes memory data)` stores the `data` at `combinedKey` (and subsequent slots) in `transient` storage. It aborts if no `data hash` is recorded in `persistent` storage or if the provided `data` does not match the recorded `data hash`.
- `read(bytes32 combinedKey) returns (bytes memory data)` returns the `data` stored at `combinedKey` (and subsequent slots) in `transient` storage. It aborts if the `data` is not loaded into `transient` storage, if no `data hash` is recorded in `persistent` storage, or if the `data` in `transient` storage is corrupted and does not match the recorded `data hash`.
- `status(bytes32 combinedKey) returns (KeyStatus)` returns whether the key is empty, if `data` is loaded into `transient` storage, or if it is not loaded (including cases of data corruption).

### Composability

In the context of an isolated call, the `read` function may succeed without prior `transient` data set only for reading zero length bytes array. Otherwise, the execution fails due to the recorded hash mismatch. Zero length arrays are not used in the project.

Additionally, that the `status` function does not follow the composability requirement. However, in context of the project it is not used that way.

### Data Packing

```py
Persistent Storage

[combinedKey] keccak256(data)
```

```py
Transient Storage

# Number of full 32-byte words in data
full_data_slots = data.length / 0x20
# Length field takes 1 more word
full_slots = full_data_slots + 1

[combinedKey]              data.length

0 < k <= full_data_slots
[combinedKey + k]          data[(k - 1) * 0x20 : k * 0x20]

[combinedKey + full_slots] 00..00 concat data[full_data_slots * 0x20 : data.length]
```

To avoid conflicts, keys __MUST__ be sufficiently far apart, such as those generated by the `keccak256` function.

## Light Storage Integration

The integration contract provides wrappers over the `LightStorage` library to read/write `Vesting` and `Config` structures instead of raw `bytes memory` arrays. It also offers public functions for preloading data into `transient` storage.

## Light Vesting

The target contract implements linear vesting functionality with a cliff. Anyone can create a vesting, and the admin can slightly modify the vesting creation rules.

Configuration is stored at specified `CONFIG_KEY` slot.

Vestings are stored at `keccak256(VESTING_KEY, beneficiary, creator, nonce))` slot what allows multiple vesttings per user and enforses `nonce` front running protection by adding the `creator` address to generation.

### Data Preloading

Smart contracts can preload data into `transient` storage using the `loadConfig` and `loadVesting` functions.

EOA actors are provided with overloaded functions that accept `Config` and `Vesting` structures as additional parameters.
