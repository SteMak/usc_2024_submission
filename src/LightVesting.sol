// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./LightStorage.sol";

struct Config {
    address admin;
    uint256 maxAmount;
    uint256 maxDuration;
    uint256 maxCliffPercent;
    uint256 fee;
    IERC20 token;
}

struct Vesting {
    address user;
    uint256 amount;
    uint256 claimed;
    uint256 start;
    uint256 duration;
    uint256 cliff;
}

abstract contract LightStorageIntegration {
    using LightStorage for bytes32;

    bytes32 internal constant CONFIG_KEY = bytes32(uint256(keccak256("compatibleKey.vesting.config")) - 1);
    bytes32 internal constant VESTING_KEY = bytes32(uint256(keccak256("compatibleKey.vesting.vestingPrefix")) - 1);

    function keyStatus(bytes32 key) public view returns (KeyStatus) {
        return key.status();
    }

    function loadConfig(bytes32 key, Config memory config) public {
        key.load(abi.encode(config));
    }

    function loadVesting(bytes32 key, Vesting memory vesting) public {
        key.load(abi.encode(vesting));
    }

    function getConfig(bytes32 key) public view returns (Config memory) {
        return abi.decode(key.read(), (Config));
    }

    function getVesting(bytes32 key) public view returns (Vesting memory) {
        return abi.decode(key.read(), (Vesting));
    }

    function _setConfig(bytes32 key, Config memory config) internal {
        key.write(abi.encode(config));
    }

    function _setVesting(bytes32 key, Vesting memory vesting) internal {
        key.write(abi.encode(vesting));
    }
}

contract LightVesting is LightStorageIntegration {
    using SafeERC20 for IERC20;

    uint256 public constant DENOM = 100000; // 100%
    uint32 public constant MAX_FEE = 1000; // 1%

    error NotAdmin(address caller, address admin);

    error TokenMismatch(IERC20 token, IERC20 configured);
    error FeeOverMax(uint256 fee, uint256 max);
    error PercentOverMax(uint256 percent, uint256 max);

    error CliffOverMax(uint256 cliff, uint256 max);
    error AmountOverMax(uint256 amount, uint256 max);
    error DurationOverMax(uint256 duration, uint256 max);

    error VestingAlreadyExist(bytes32 key);
    error NotBeneficiary(address caller, address beneficiary);

    event Configuration(Config config, bool adminChanged);
    event VestingCreate(bytes32 indexed key, Vesting vesting, uint256 nonce);
    event VestingClaim(bytes32 indexed key, Vesting vesting, uint256 unlocked);

    constructor(Config memory config) {
        require(config.admin == msg.sender, NotAdmin(msg.sender, config.admin));
        require(config.fee <= MAX_FEE, FeeOverMax(config.fee, MAX_FEE));
        require(config.maxCliffPercent <= DENOM, PercentOverMax(config.maxCliffPercent, DENOM));

        _setConfig(CONFIG_KEY, config);

        emit Configuration(config, true);
    }

    function configurate(Config memory updated) public {
        Config memory config = getConfig(CONFIG_KEY);

        require(config.admin == msg.sender, NotAdmin(msg.sender, config.admin));
        require(config.token == updated.token, TokenMismatch(updated.token, config.token));
        require(updated.fee <= MAX_FEE, FeeOverMax(config.fee, MAX_FEE));
        require(updated.maxCliffPercent <= DENOM, PercentOverMax(config.maxCliffPercent, DENOM));

        _setConfig(CONFIG_KEY, updated);

        emit Configuration(config, config.admin != updated.admin);
    }

    function configurate(Config memory updated, Config memory config) external {
        loadConfig(CONFIG_KEY, config);
        configurate(updated);
    }

    function create(
        address beneficiary,
        uint256 nonce,
        uint256 amount,
        uint32 start,
        uint32 duration,
        uint32 cliff
    ) public returns (bytes32 key) {
        key = keccak256(abi.encode(VESTING_KEY, beneficiary, msg.sender, nonce));
        require((keyStatus(key) == KeyStatus.Empty), VestingAlreadyExist(key));

        Config memory config = getConfig(CONFIG_KEY);

        uint256 maxCliff = (duration * config.maxCliffPercent) / DENOM;
        require(maxCliff >= cliff, CliffOverMax(cliff, maxCliff));
        require(config.maxAmount >= amount, AmountOverMax(amount, config.maxAmount));
        require(config.maxDuration >= duration, DurationOverMax(duration, config.maxDuration));

        config.token.safeTransferFrom(msg.sender, address(this), amount);

        Vesting memory vesting = Vesting(beneficiary, amount, 0, start, duration, cliff);
        _setVesting(key, vesting);

        emit VestingCreate(key, vesting, nonce);
    }

    function create(
        address beneficiary,
        uint256 nonce,
        uint256 amount,
        uint32 start,
        uint32 duration,
        uint32 cliff,
        Config memory config
    ) external returns (bytes32 key) {
        loadConfig(CONFIG_KEY, config);
        return create(beneficiary, nonce, amount, start, duration, cliff);
    }

    function _calcTotalVested(
        uint256 start,
        uint256 cliff,
        uint256 duration,
        uint256 amount
    ) internal view returns (uint256) {
        if (block.timestamp >= start + duration) {
            return amount;
        } else if (block.timestamp < start + cliff) {
            return 0;
        } else {
            return (amount * (block.timestamp - start)) / duration;
        }
    }

    function _calcWithdrawable(Vesting memory vesting) internal view returns (uint256) {
        uint256 vestedAmount = _calcTotalVested(vesting.start, vesting.cliff, vesting.duration, vesting.amount);
        return vestedAmount - vesting.claimed;
    }

    function withdrawable(bytes32 key) public view returns (uint256) {
        return _calcWithdrawable(getVesting(key));
    }

    function withdrawable(bytes32 key, Vesting memory vesting) external returns (uint256) {
        loadVesting(key, vesting);
        return withdrawable(key);
    }

    function withdraw(bytes32 key) public {
        Vesting memory vesting = getVesting(key);
        require(vesting.user == msg.sender, NotBeneficiary(msg.sender, vesting.user));

        Config memory config = getConfig(CONFIG_KEY);

        uint256 unlocked = _calcWithdrawable(vesting);
        vesting.claimed += unlocked;

        _setVesting(key, vesting);

        config.token.safeTransfer(msg.sender, unlocked);

        emit VestingClaim(key, vesting, unlocked);
    }

    function withdraw(bytes32 key, Config memory config, Vesting memory vesting) external {
        loadConfig(CONFIG_KEY, config);
        loadVesting(key, vesting);
        withdraw(key);
    }
}
