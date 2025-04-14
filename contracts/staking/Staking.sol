/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IWBKN is IERC20Upgradeable {
    function release(address account, uint256 amount) external returns (bool);
}

/// @title Staking
/// @custom:security-contact tech@brickken.com
contract Staking is OwnableUpgradeable {
    using Math for uint256;
    using Address for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IWBKN;

    /// The `user` is not WBKN holder
    error NotHolder(address user);
    /// The `user` has not allowed this contract to spend all WBKN Tokens
    error NotAllowedAllWBKN(address user);
    /// The period is not valid
    error InvalidPeriod();
    /// BKN not released
    error NotReleased();
    /// The `user` is already staking
    error AlreadyStaked(address user);
    /// The `user` is not staking
    error NotStaker(address user);
    /// The address is not a contract
    error NotContractAddress();
    /// The address can't be the zero address
    error NotZeroAddress();
    /// The variable can't have zero value
    error NotZeroValue();
    /// The amount is not valid, exceed the max amount to lock
    error MaxToLockExceeded(address user, uint256 available);
    /// The round is paused
    error RoundPaused();
    /// User provided an invalid round number to stake on
    error InvalidRoundNumber();
    /// User is not able to unstake
    error UnableStake();

    // Withdrawal windows

    // window 1: 2024-01-01 00:00:00 UTC to 2024-01-31 23:59:59 UTC
    uint64 private constant window1Start = 1704067200;
    uint64 private constant window1End = 1706745599;

    // window 2: 2024-07-01 00:00:00 UTC to 2024-07-31 23:59:59 UTC
    uint64 private constant window2Start = 1719792000;
    uint64 private constant window2End = 1722470399;

    // window 3: 2025-01-01 00:00:00 UTC to indefinite
    uint64 private constant window3Start = 1735689600;

    // 2023-01-01 00:00:00 UTC
    uint64 private constant stakingStart = 1672531200;

    // Instances of BKN and WBKN
    IERC20Upgradeable public BKNToken;
    IWBKN public WBKNToken;

    struct TransferUsers {
        uint8 from; // 1 for first round, 2 for second, 3 for third
        uint8 to; // 2 for second round, 3 for third
        address[] users; // users to move
    }

    struct StakingRound {
        bool statusPaused; // Variable to pause the round
        bool unstakeUnlocked; // Variable to unlock the unstake
        uint256 amountToDistribute; // Fixed amount of BKN to distribute in this round
        uint256 totalLocked; // Amount of BKN locked in this round by depositors, this will increment with time
        uint256 maxToLock; // Max amount that can be locked in this round
        mapping(address => uint256) userLockedFunds; // How much each user has staked
        mapping(address => bool) userIsPresent; // Helper to identify users in each round
        uint256 whenItWillUnlock; // 12/18/24 months starting on Jan 1 2023
    }

    /// @dev StakingRounds by stakingRound index
    mapping(uint256 => StakingRound) public stakingRounds;

    /// @dev Gap variable for future upgrades
    uint256[45] __gap;

    /// @dev Issuance Index ---> Address of investor ---> Investor struct
    // mapping(uint256 => mapping(address => StakingRound)) public stakingRounds;

    /**
     * @dev Event when a staking position is opened
     * @param user address of the WBKN holder
     * @param amount amount of BKN staked
     */
    event StakingEvent(address indexed user, uint256 amount);

    /**
     * @dev Event when a staking position is closed
     * @param user address of the BKN holder
     * @param amount amount of BKN unstaked
     * @param round from which it has been unstaked
     */
    event UnstakingEvent(address indexed user, uint256 amount, uint8 round);

    /**
     * @dev Event when a round is paused/unpaused
     * @param round either 1, 2 or 3
     * @param status true/false for paused/unpaused
     */
    event RoundPausedEvent(uint8 round, bool status);

    /**
     * @dev Event when a round unstaking is unlocked/locked
     * @param round either 1, 2 or 3
     * @param status true/false for unlocked/locked
     */
    event UnlockUnstakeEvent(uint8 round, bool status);

    // transfer users
    /**
     * @dev Event when a round unstaking is unlocked/locked
     * @param amount amount of users transferred
     */
    event TransferUsersEvent(uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _WBKN, address _BKN, address _owner) initializer() external {
        if (!_WBKN.isContract()) revert NotContractAddress();
        if (!_BKN.isContract()) revert NotContractAddress();

        WBKNToken = IWBKN(_WBKN);
        BKNToken = IERC20Upgradeable(_BKN);

        __Ownable_init_unchained();
        __Context_init_unchained();
        transferOwnership(_owner);

        // 2023-12-31 23:59:59 UTC stage 1 end Date
        stakingRounds[1].whenItWillUnlock = 1704063600;

        // 2024-06-30 23:59:59 UTC stage 2 end Date
        stakingRounds[2].whenItWillUnlock = 1717192800;

        // 2024-12-31 23:59:59 UTC stage 3 end Date
        stakingRounds[3].whenItWillUnlock = 1735686000;

        // Max To locked
        stakingRounds[1].maxToLock = 6e24;
        stakingRounds[2].maxToLock = 8e24;
        stakingRounds[3].maxToLock = 11e24;

        // Amount to distribute
        stakingRounds[1].amountToDistribute = 6e23;
        stakingRounds[2].amountToDistribute = 10e23;
        stakingRounds[3].amountToDistribute = 14e23;
    }

    /**
     * @dev Receive fallback payable method. Don't accept ETH.
     */
    receive() external payable {
        assert(false);
    }

    /**
     * @dev Reverts if a given address is equal to address(0)
     * @param to the address to check
     */
    modifier validAddress(address to) {
        if (to == address(0)) revert NotZeroAddress();
        /* solcov ignore next */
        _;
    }

    // External functions

    /**
     * @dev Method to pause or unpause the staking round
     */
    function pauseRound(uint8 round, bool status) external onlyOwner {
        (
            StakingRound storage correctRound,
            bool itExists
        ) = _getStakingRoundById(round);
        if(!itExists) revert InvalidRoundNumber();

        correctRound.statusPaused = status;
        emit RoundPausedEvent(round, status);
    }

    /**
     * @dev Method to withdraw any ERC20 from the contract
     * @param token address of the ERC20 token
     * @param amount amount of ERC20 token to withdraw<
     */
    function withdrawERC20(
        IERC20Upgradeable token,
        uint256 amount,
        address to
    ) external validAddress(to) onlyOwner {
        if (amount == 0) revert NotZeroValue();
        if (!address(token).isContract()) revert NotContractAddress();
        token.safeTransfer(to, amount); // This already emits an event, not emitting redundant one here
    }

    /**
     * @dev Method to unlock the unstaking feature of each round.
     * @param round number of the round
     * @param status true or false to unlock/lock the staking round unstake
     */
    function unlockStaking(uint8 round, bool status) external onlyOwner {
        (
            StakingRound storage correctRound,
            bool itExists
        ) = _getStakingRoundById(round);
        if (!itExists) revert InvalidRoundNumber();

        correctRound.unstakeUnlocked = status;

        emit UnlockUnstakeEvent(round, status);
    }

    /**
     * @dev Method for transfer user from one round to another
     * @param transfer struct with the data to transfer
     */
    function transferUsers(TransferUsers memory transfer) external onlyOwner {
        //Remove each transfer.users from "from" staking round and add it to "to" staking round
        for (uint256 i = 0; i < transfer.users.length; i++) {
            address user = transfer.users[i];
            uint256 amount = getDepositedAmount(user);
            if (amount == 0) revert NotZeroValue();

            // Can't move from the last round
            // Can't transfer to the same round or a previous round
            if (transfer.from == 3 || transfer.to <= transfer.from)
                revert InvalidRoundNumber();

            // _getStakingRoundById will return false for every value except for 1,2 and 3
            (
                StakingRound storage fromRound,
                bool itExists
            ) = _getStakingRoundById(transfer.from);
            (
                StakingRound storage toRound,
                bool itAlsoExists
            ) = _getStakingRoundById(transfer.to);
            if (!itExists || !itAlsoExists) revert InvalidRoundNumber();

            fromRound.userLockedFunds[user] = 0;
            fromRound.totalLocked -= amount;
            fromRound.userIsPresent[user] = false;

            toRound.userLockedFunds[user] = amount;

            if ((toRound.totalLocked + amount) > toRound.maxToLock)
                revert MaxToLockExceeded(
                    user,
                    toRound.maxToLock - toRound.totalLocked
                );

            toRound.totalLocked += amount;
            toRound.userIsPresent[user] = true;
        }

        emit TransferUsersEvent(transfer.users.length);
    }

    /**
     * @dev Method to allow user staking. Conditions:
     *  - The timestamp must be in a valid staking period
     *  - The round should not be paused
     *  - The user should not be a staker already
     *  - The user must have the WBKN token approved to be spended by this contract
     *  - The amount should not exceed the maxToLock of the corresponding round
     */
    function deposit(uint8 round) external {
        address caller = _msgSender();

        // Validate if the user is in the staking period
        if (!isStakingPeriod()) revert InvalidPeriod();

        (
            StakingRound storage correctRound,
            bool itExists
        ) = _getStakingRoundById(round);

        if (!itExists) revert InvalidRoundNumber();

        if (correctRound.statusPaused) revert RoundPaused();

        // Validate if the user is a staker
        (bool isUserStaker, ) = isStaker(caller);
        if (isUserStaker) revert AlreadyStaked(caller);

        // Validate if the user is a holder of WBKN token
        uint256 amount = WBKNToken.balanceOf(caller);
        if (amount == 0) revert NotHolder(caller);

        // Validate if the User has the WBKN token approved to the right amount
        uint256 allowed = WBKNToken.allowance(caller, address(this));
        if (allowed == 0) revert NotZeroValue();
        if (amount > allowed) revert NotAllowedAllWBKN(caller);

        // Validate the max locked amount is raised in each round
        if ((correctRound.totalLocked + amount) > correctRound.maxToLock)
            amount = correctRound.maxToLock - correctRound.totalLocked;
        if (amount == 0) revert MaxToLockExceeded(caller, amount);

        // Transfer WBKN in the contract (user must approve first)
        WBKNToken.safeTransferFrom(caller, address(this), amount);

        bool success = WBKNToken.release(address(this), amount);
        if (!success) revert NotReleased();

        correctRound.userLockedFunds[caller] = amount;
        correctRound.userIsPresent[caller] = true;
        correctRound.totalLocked += amount;

        emit StakingEvent(caller, amount);
    }

    /**
     * @dev Method to allow user unstaking. Conditions:
     *  - The timestamp must be in a valid unstaking period
     *  - The user should be a staker already
     *  - The user should have a positive amount of locked funds
     * @param round number of the round
     */
    function unlock(uint8 round) external {
        if (!isUnstakeable(round)) revert UnableStake();

        address caller = _msgSender();

        (
            StakingRound storage correctRound,
            ,
            bool itExists
        ) = _getStakingRoundByStaker(caller);

        // Validate if the user is a staker
        if (!itExists) revert NotStaker(caller);

        if (
            !(block.timestamp >= correctRound.whenItWillUnlock) ||
            !correctRound.unstakeUnlocked
        ) revert UnableStake();

        // Validate amount of BKN to unstake for the caller
        uint256 amount = getProjectedAmount(caller);
        if (amount == 0) revert NotZeroValue();

        correctRound.userLockedFunds[caller] = 0;
        correctRound.userIsPresent[caller] = false;

        // Transfer BKN to the user
        BKNToken.safeTransfer(caller, amount);

        emit UnstakingEvent(caller, amount, round);
    }

    // Public functions

    /**
     * @dev Method to get the deposited amount for any user in all round
     * @param user address of the user
     */
    function getDepositedAmount(address user) public view returns (uint256) {
        (
            StakingRound storage correctRound,
            ,
            bool itExists
        ) = _getStakingRoundByStaker(user);

        if (!itExists) return 0;
        else return correctRound.userLockedFunds[user];
    }

    /**
     * @dev Method to get true or false if getTimestamp() is into a valid staking period
     */
    function isStakingPeriod() public view returns (bool result) {
        (result, ) = _getStakingPeriod(uint64(_getTimestamp()));
    }

    /**
     * @dev Method to get true or false if _getTimestamp() is into a valid withdraw window
     */
    function isWithdrawPeriod() public view returns (bool result) {
        result = _isWithdrawPeriod(uint64(_getTimestamp()));
    }

    /**
     * @dev Method to verify if the user is a staker
     * @param user address of the user
     */
    function isStaker(
        address user
    ) public view returns (bool isUserStaker, uint roundId) {
        (, uint rountId, bool itExists) = _getStakingRoundByStaker(user);
        if (!itExists) return (false, rountId);
        return (true, rountId);
    }

    /**
     * @dev Method to verify if the user can or can't unstake BKN tokens
     * @param round number of the round
     */
    function isUnstakeable(uint8 round) public view returns (bool) {
        (
            StakingRound storage correctRound,
            bool itExists
        ) = _getStakingRoundById(round);
        if (!itExists) revert InvalidRoundNumber();
        if (
            block.timestamp >= correctRound.whenItWillUnlock &&
            correctRound.unstakeUnlocked
        ) return true;
        else return false;
    }

    /**
     * @dev Method to get the expected amount of BKN tokens that the user can withdraw.
     * @param user address of the user
     */
    function getProjectedAmount(address user) public view returns (uint256) {
        (
            StakingRound storage correctRound,
            ,
            bool itExists
        ) = _getStakingRoundByStaker(user);

        if (!itExists) return 0;

        uint256 lockedAmount = correctRound.userLockedFunds[user];

        if (lockedAmount == 0) return 0;
        else
            return
                lockedAmount +
                lockedAmount.mulDiv(
                    correctRound.amountToDistribute,
                    correctRound.totalLocked
                );
    }

    // Internal functions

    function _getStakingRoundByStaker(
        address user
    )
        internal
        view
        returns (
            StakingRound storage correctRound,
            uint256 roundId,
            bool itExists
        )
    {
        return
            stakingRounds[1].userIsPresent[user]
                ? (stakingRounds[1], 1, true)
                : (
                    stakingRounds[2].userIsPresent[user]
                        ? (stakingRounds[2], 2, true)
                        : (
                            stakingRounds[3].userIsPresent[user]
                                ? (stakingRounds[3], 3, true)
                                : (stakingRounds[1], 1, false)
                        )
                );
    }

    function _getStakingRoundById(
        uint8 round
    ) internal view returns (StakingRound storage correctRound, bool itExists) {
        return
            round == 1
                ? (stakingRounds[1], true)
                : (
                    round == 2
                        ? (stakingRounds[2], true)
                        : (
                            round == 3
                                ? (stakingRounds[3], true)
                                : (stakingRounds[1], false)
                        )
                );
    }

    /**
     * @dev Method to get whether the provided timestamp is in a valid staking period
     * and when the period will unlock the stake.
     */
    function _getStakingPeriod(
        uint64 timeStamp
    ) internal view returns (bool, uint256) {
        if (timeStamp < stakingStart) return (false, 0);
        if (
            timeStamp >= stakingStart &&
            timeStamp < stakingRounds[1].whenItWillUnlock
        ) return (true, stakingRounds[1].whenItWillUnlock);
        else if (
            timeStamp >= stakingRounds[1].whenItWillUnlock &&
            timeStamp < stakingRounds[2].whenItWillUnlock
        ) return (true, stakingRounds[2].whenItWillUnlock);
        else if (
            timeStamp >= stakingRounds[2].whenItWillUnlock &&
            timeStamp < stakingRounds[3].whenItWillUnlock
        ) return (true, stakingRounds[3].whenItWillUnlock);
        return (false, 0);
    }

    /**
     * @dev Method to know if a given timestamp is withing a valid withdraw window
     */
    function _isWithdrawPeriod(uint64 timeStamp) internal pure returns (bool) {
        if (timeStamp < window1Start) return false;
        else if (timeStamp >= window1Start && timeStamp < window1End)
            return true;
        else if (timeStamp >= window2Start && timeStamp < window2End)
            return true;
        else if (timeStamp >= window3Start) return true;
        else return false;
    }

    /**
     * @dev Method to get the current block.timestamp
     */
    function _getTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }
}
