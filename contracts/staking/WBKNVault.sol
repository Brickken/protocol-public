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

/// @title WBKNVault
/// @custom:security-contact tech@brickken.com
contract WBKNVault is OwnableUpgradeable {
    using Math for uint256;
    using Address for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IWBKN;

    struct Vault {
        uint256 totalLocked; // Amount of BKN locked by depositors
        mapping(address => uint256) userLockedFunds; // How much each user has locked
        mapping(address => bool) userIsPresent; // Helper to identify users
    }

    struct PauseStatus {
        bool depositPaused;
        bool releasePaused;
        bool unlockPaused;
    }

    event DepositEvent(address indexed user, uint256 amount);
    event UnlockEvent(address indexed user, uint256 amount);
    event BlacklistedAddress(address indexed user, uint256 amount);
    event ReleaseEvent(address indexed user, uint256 amount);

    error NotHolder(address user);
    error NotAllowedAllWBKN(address user);
    error NotReleased();
    error NotContractAddress();
    error NotZeroAddress();
    error NotZeroValue();
    error NotUnlockable();
    error BlacklistedUser(address user);
    error NotUser(address user);

    uint256 public constant lockEnds = 1721908800; // July 25th 2024 - 12:00 UTC(GMT+0)

    IERC20Upgradeable public BKNToken;
    IWBKN public WBKNToken;

    Vault public wbknVault;

    mapping(address user => bool blacklisted) public blacklist;

    PauseStatus public pausedStatus;

    modifier whenNotPaused(bool isPaused) {
        require(!isPaused, "Function is paused");
        _;
    }

    uint256[46] __gap;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _WBKN,
        address _BKN,
        address _owner
    ) external initializer {
        if (!_WBKN.isContract()) revert NotContractAddress();
        if (!_BKN.isContract()) revert NotContractAddress();

        WBKNToken = IWBKN(_WBKN);
        BKNToken = IERC20Upgradeable(_BKN);

        __Ownable_init_unchained();
        __Context_init_unchained();
        transferOwnership(_owner);
    }

    receive() external payable {
        assert(false);
    }

    function transferUsers(
        address[] memory oldUsers,
        address[] memory newUsers
    ) external onlyOwner {
        for (uint256 i = 0; i < oldUsers.length; i++) {
            if (!wbknVault.userIsPresent[oldUsers[i]])
                revert NotUser(oldUsers[i]);

            uint256 cachedOldLockedAmount = wbknVault.userLockedFunds[
                oldUsers[i]
            ];

            // pass amounts from old to new
            wbknVault.userLockedFunds[oldUsers[i]] = 0;
            wbknVault.userLockedFunds[newUsers[i]] = cachedOldLockedAmount;

            // remove old one, add the new one
            wbknVault.userIsPresent[oldUsers[i]] = false;
            wbknVault.userIsPresent[newUsers[i]] = true;

            // copy the same blacklist status
            blacklist[newUsers[i]] = blacklist[oldUsers[i]];
        }
    }

    function withdrawERC20(
        IERC20Upgradeable token,
        uint256 amount,
        address to
    ) external onlyOwner {
        if (amount == 0) revert NotZeroValue();
        if (to == address(0)) revert NotZeroAddress();
        if (!address(token).isContract()) revert NotContractAddress();
        token.safeTransfer(to, amount); // This already emits an event, not emitting redundant one here
    }

    function blacklistUsers(
        address[] memory users,
        bool[] memory statuses
    ) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            if (statuses[i]) blacklist[users[i]] = true;
            else blacklist[users[i]] = false;
        }
    }

    function deposit() external whenNotPaused(pausedStatus.depositPaused) {
        address caller = _msgSender();

        // Validate if the user is a holder of WBKN token
        uint256 amount = WBKNToken.balanceOf(caller);
        if (amount == 0) revert NotHolder(caller);

        // Validate if the User has the WBKN token approved to the right amount
        uint256 allowed = WBKNToken.allowance(caller, address(this));
        if (allowed == 0) revert NotZeroValue();
        if (amount > allowed) revert NotAllowedAllWBKN(caller);

        // Transfer WBKN in the contract (user must approve first)
        WBKNToken.safeTransferFrom(caller, address(this), amount);

        bool success = WBKNToken.release(address(this), amount);
        if (!success) revert NotReleased();

        wbknVault.userLockedFunds[caller] += amount;
        wbknVault.userIsPresent[caller] = true;
        wbknVault.totalLocked += amount;

        emit DepositEvent(caller, amount);
    }

    function unlock() external whenNotPaused(pausedStatus.unlockPaused) {
        address caller = _msgSender();

        if (!isUnlockable()) revert NotUnlockable();
        if (!wbknVault.userIsPresent[caller]) revert NotUnlockable();
        if (blacklist[caller]) revert BlacklistedUser(caller);

        // Validate amount of BKN to unstake for the caller
        uint256 amount = getLockedAmount(caller);
        if (amount == 0) revert NotZeroValue();

        wbknVault.userLockedFunds[caller] = 0;
        wbknVault.userIsPresent[caller] = false;
        wbknVault.totalLocked -= amount;

        // Transfer BKN to the user
        BKNToken.safeTransfer(caller, amount);

        emit UnlockEvent(caller, amount);
    }

    function release() external whenNotPaused(pausedStatus.releasePaused) {
        address caller = _msgSender();

        // Validate if the user is a holder of WBKN token
        uint256 amount = WBKNToken.balanceOf(caller);
        if (amount == 0) revert NotHolder(caller);

        // Validate if the User has the WBKN token approved to the right amount
        uint256 allowed = WBKNToken.allowance(caller, address(this));
        if (allowed == 0) revert NotZeroValue();
        if (amount > allowed) revert NotAllowedAllWBKN(caller);

        // Transfer WBKN in the contract (user must approve first)
        WBKNToken.safeTransferFrom(caller, address(this), amount);

        bool success = WBKNToken.release(address(this), amount);
        if (!success) revert NotReleased();

        if (blacklist[caller]) {
            wbknVault.userLockedFunds[caller] += amount;
            wbknVault.userIsPresent[caller] = true;
            wbknVault.totalLocked += amount;

            emit BlacklistedAddress(caller, amount);
        } else {
            // Transfer BKN to the user
            BKNToken.safeTransfer(caller, amount);

            emit ReleaseEvent(caller, amount);
        }
    }

    function getLockedAmount(address user) public view returns (uint256) {
        return wbknVault.userLockedFunds[user];
    }

    function isUnlockable() public view returns (bool) {
        return block.timestamp >= lockEnds;
    }

    function changePauseStatus(
        bool depositStatus,
        bool unlockStatus,
        bool releaseStatus
    ) external onlyOwner{
        if(pausedStatus.depositPaused != depositStatus) pausedStatus.depositPaused = depositStatus;
        if(pausedStatus.unlockPaused != unlockStatus) pausedStatus.unlockPaused = unlockStatus;
        if(pausedStatus.releasePaused != releaseStatus) pausedStatus.releasePaused = releaseStatus;
    }
}
