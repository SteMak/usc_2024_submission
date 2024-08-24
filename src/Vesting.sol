// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Vesting {
    using SafeERC20 for IERC20;

    error CliffDurationLongerThanVestingDuration();

    struct Vesting {
        uint32 vestingStartTime;
        uint32 vestingDuration;
        uint32 cliffDuration;
        uint amount;
        uint claimedAmount;
        address token;
    }

    mapping(address => Vesting[]) public vestings;

    function createVestingSchedule(
        address beneficiary,
        uint32 vestingStartTime,
        uint32 cliffDuration,
        uint32 vestingDuration,
        address token,
        uint amount
    ) external {
        if (vestingDuration < cliffDuration) {
            revert CliffDurationLongerThanVestingDuration();
        }
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        vestings[beneficiary].push(
            Vesting(
                vestingStartTime,
                vestingDuration,
                cliffDuration,
                amount,
                0,
                token
            )
        );
    }

    function _calculateTotalVestedAmount(
        uint32 vestingStartTime,
        uint32 cliffDuration,
        uint32 vestingDuration,
        uint amount
    ) internal view returns (uint) {
        if (block.timestamp >= vestingStartTime + vestingDuration) {
            return amount;
        } else if (block.timestamp < vestingStartTime + cliffDuration) {
            return 0;
        } else {
            return
                (amount * (block.timestamp - vestingStartTime)) /
                vestingDuration;
        }
    }

    function _calculateWithdrawableAmount(
        Vesting storage vesting
    ) internal view returns (uint) {
        uint vestedAmount = _calculateTotalVestedAmount(
            vesting.vestingStartTime,
            vesting.cliffDuration,
            vesting.vestingDuration,
            vesting.amount
        );
        return vestedAmount - vesting.claimedAmount;
    }

    function withdrawable(uint id) public view returns (uint) {
        Vesting storage vesting = vestings[msg.sender][id];
        return _calculateWithdrawableAmount(vesting);
    }

    function withdraw(uint id) public {
        Vesting storage vesting = vestings[msg.sender][id];
        uint withdrawableAmount = _calculateWithdrawableAmount(vesting);
        vesting.claimedAmount += withdrawableAmount;
        IERC20(vesting.token).safeTransfer(msg.sender, withdrawableAmount);
    }
}