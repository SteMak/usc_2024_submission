// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./LightStorage.sol";

bytes32 constant CONFIG_KEY = bytes32(uint256(keccak256("compatibleKey.vesting.config")) - 1);
bytes32 constant VESTING_KEY = bytes32(uint256(keccak256("compatibleKey.vesting.vestingPrefix")) - 1);

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

contract LightVesting {
    using SafeERC20 for IERC20;
    using LightStorage for bytes32;

    uint256 constant DENOM = 100000; // 100%
    uint32 constant MAX_FEE = 1000; // 1%

    error NotAdmin();

    error TokenMismatch();
    error FeeOverMax();
    error PercentOverMax();

    error CliffOverMax();
    error AmountOverMax();
    error DurationOverMax();

    error VestingAlreadyExist();
    error NotBeneficiary();

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

    constructor(Config memory config) {
        require(config.admin == msg.sender, NotAdmin());
        require(config.fee <= MAX_FEE, FeeOverMax());
        require(config.maxCliffPercent <= DENOM, PercentOverMax());

        _setConfig(CONFIG_KEY, config);
    }

    function configurate(Config memory updated) external {
        Config memory config = getConfig(CONFIG_KEY);

        require(config.admin == msg.sender, NotAdmin());
        require(config.token == updated.token, TokenMismatch());
        require(updated.fee <= MAX_FEE, FeeOverMax());
        require(updated.maxCliffPercent <= DENOM, PercentOverMax());

        _setConfig(CONFIG_KEY, updated);
    }

    function create(
        address beneficiary,
        uint256 nonce,
        uint256 amount,
        uint32 start,
        uint32 duration,
        uint32 cliff
    ) external returns (bytes32 key) {
        key = keccak256(abi.encode(VESTING_KEY, beneficiary, msg.sender, nonce));
        require((key.status() == KeyStatus.Empty), VestingAlreadyExist());

        Config memory config = getConfig(CONFIG_KEY);

        require((duration * config.maxCliffPercent) / DENOM >= cliff, CliffOverMax());
        require(config.maxAmount >= amount, AmountOverMax());
        require(config.maxDuration >= duration, DurationOverMax());

        config.token.safeTransferFrom(msg.sender, address(this), amount);

        _setVesting(key, Vesting(beneficiary, amount, 0, start, duration, cliff));
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

    function withdrawable(bytes32 key) external view returns (uint256) {
        return _calcWithdrawable(getVesting(key));
    }

    function withdraw(bytes32 key) public {
        Vesting memory vesting = getVesting(key);
        require(vesting.user == msg.sender, NotBeneficiary());

        Config memory config = getConfig(CONFIG_KEY);

        uint256 unlocked = _calcWithdrawable(vesting);
        vesting.claimed += unlocked;

        _setVesting(key, vesting);

        config.token.safeTransfer(msg.sender, unlocked);
    }
}
