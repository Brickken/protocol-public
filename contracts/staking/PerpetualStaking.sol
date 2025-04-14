/// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title PerpetualStaking
/// @custom:security-contact tech@brickken.com
contract PerpetualStaking is OwnableUpgradeable {
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Instances of BKN
    IERC20Upgradeable public BKNToken;

    uint256 private constant ONE = 1000000000000000000; // 100 % 1e18

    bool public isDepositable;
    bool public isClaimable;

    uint256 private DEPRECATED_1;
    uint256 private DEPRECATED_2;
    uint256 public yieldPerYear; // 15% per year, 15e16
    uint256 public yieldPerSecond; // yieldPerYear / (365 * 24 * 60 * 60)
    uint256 private DEPRECATED_3;

    /*
        In order to calculate solvency (the ability of the contract to pay everyone at once in any given moment)
        We need to find a formula that gives us the minimum balance that the contract should have at any moment.
        Let's define some variables:

        - d0_i -> The initial deposit of user i
        - t0_i -> Time at which user i deposited
        - yieldPerSecond -> yield generated for each second
        
        So we can write the solvency condition as dependant on any given time 't'

        S(t) = SUM (d0_i + d0_i * yieldPerSecond * (t - t0_i)) 
        
        Which represents the sum of all initial deposits plus the yielded amount for each user i 
        at any time t relative to the initial deposit time t0_i

        And we can split into three components

        - SUM(d0_i) -> totalDeposited
        - SUM(yieldPerSecond * d0_i) -> tokensYieldPerSecond
        - SUM(yieldPerSecond * d0_i * t0_i) -> yieldUpToDeposit

        So that our formula becomes

        S(t) = totalDeposited + t * tokensYieldPerSecond - yieldUpToDeposit

        Whenever a new user deposit, totalDeposited, tokensYieldPerSecond and yieldUpToDeposit will increment
        Conversely, when an user exits the same variables will be reduced.
    */
        
    uint256 public totalDeposited;
    uint256 public tokensYieldPerSecond;
    uint256 public yieldUpToDeposit;

    struct UserStake {
        uint256 amountDeposited;
        uint256 latestDepositTimestamp;
    }

    mapping(address => UserStake) public userStakes;

    bool public isCompoundable;
    uint256 public endTimeForYielding; // Yield accumulates up to this timestamp at most

    error DepositsAreClosed();
    error ClaimsAreClosed();
    error CompoundIsClosed();
    error NotEnoughTimeStaked();
    error NotEnoughToClaim();
    error LengthMismatch();
    error ContractHasNotEnoughBalance(uint256 claimingAmount, uint256 balance);
    error AlreadyDeposited(address user);
    error InvalidEndTime();
    error CantDepositAfterEndtime();

    uint256[35] __gap;

    modifier whenDepositable() {
        if(!isDepositable) revert DepositsAreClosed();
        _;
    }

    modifier whenClaimable() {
        if(!isClaimable) revert ClaimsAreClosed();
        _;
    }

    modifier whenCompoundable() {
        if(!isCompoundable) revert CompoundIsClosed();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _BKN, address _owner) initializer() external {
        BKNToken = IERC20Upgradeable(_BKN);

        __Ownable_init_unchained();
        __Context_init_unchained();
        _transferOwnership(_owner);

        isClaimable = true;
        isDepositable = true;
        isCompoundable = true;
        yieldPerYear = 150000000000000000; // 15% per year, 15e16
        yieldPerSecond = yieldPerYear / (365 * 24 * 60 * 60); // yieldPerYear / (365 * 24 * 60 * 60)
    }

    receive() external payable {
        assert(false);
    }

    function pauseDeposit() external onlyOwner {
        isDepositable = false;
    }

    function unpauseDeposit() external onlyOwner {
        isDepositable = true;
    }

    function pauseCompound() external onlyOwner {
        isCompoundable = false;
    }

    function unpauseCompound() external onlyOwner {
        isCompoundable = true;
    }

    function pauseClaim() external onlyOwner {
        isClaimable = false;
    }

    function unpauseClaim() external onlyOwner {
        isClaimable = true;
    }

    function removeTokens(IERC20Upgradeable token, address to, uint256 amount) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    function changeUserAddress(address from, address to) external onlyOwner {
        userStakes[to] = userStakes[from];
        delete userStakes[from];
    }

    function setEndTime(uint256 value) external onlyOwner {
        if(value <= block.timestamp) revert InvalidEndTime();
        endTimeForYielding = value;
    }

    function deposit(address user, uint256 amount) external whenDepositable {
        if(userStakes[user].amountDeposited > 0) revert AlreadyDeposited(user);
        BKNToken.safeTransferFrom(user, address(this), amount);

        userStakes[user].amountDeposited += amount;
        uint256 currentTimestamp = block.timestamp;
        if(currentTimestamp > endTimeForYielding) revert CantDepositAfterEndtime();
        userStakes[user].latestDepositTimestamp = currentTimestamp;
        
        // Adjust solvency accounting
        totalDeposited += amount;
        tokensYieldPerSecond += yieldPerSecond * amount;
        yieldUpToDeposit += yieldPerSecond * amount * currentTimestamp;
    }

    function compoundAndDeposit(address user, uint256 amount) external whenCompoundable {
        uint256 claimingAmount = getWithdrawableUserBalance(user);
        if(!(claimingAmount > 0)) revert NotEnoughToClaim();

        if(!isDepositable && amount != 0) revert DepositsAreClosed();

        if(amount > 0) {
            BKNToken.safeTransferFrom(user, address(this), amount);
        }

        uint256 newTotalAmount = claimingAmount + amount;
        uint256 oldDepositedAmount = userStakes[user].amountDeposited;
        uint256 oldDepositedTimestamp = userStakes[user].latestDepositTimestamp;

        userStakes[user].amountDeposited = newTotalAmount;
        uint256 currentTimestamp = block.timestamp;
        if(currentTimestamp > endTimeForYielding) revert CantDepositAfterEndtime();
        userStakes[user].latestDepositTimestamp = currentTimestamp;

        // Adjust solvency by summing the new deposits values and removing the old ones next (to avoid underflows)

        totalDeposited += newTotalAmount;
        totalDeposited -= oldDepositedAmount;

        tokensYieldPerSecond += yieldPerSecond * newTotalAmount;
        tokensYieldPerSecond -= yieldPerSecond * oldDepositedAmount;

        yieldUpToDeposit += yieldPerSecond * newTotalAmount * userStakes[user].latestDepositTimestamp;
        yieldUpToDeposit -= yieldPerSecond * oldDepositedAmount * oldDepositedTimestamp;
    }

    function claim(address user) external whenClaimable {
        uint256 claimingAmount = getWithdrawableUserBalance(user);
        if(!(claimingAmount > 0)) revert NotEnoughToClaim();
    
        uint256 initialDeposit = userStakes[user].amountDeposited;

        // Adjust solvency accounting
        totalDeposited -= initialDeposit;
        tokensYieldPerSecond -= yieldPerSecond * initialDeposit;
        yieldUpToDeposit -= yieldPerSecond * initialDeposit * userStakes[user].latestDepositTimestamp;

        delete userStakes[user];

        if(claimingAmount > BKNToken.balanceOf(address(this)))
            revert ContractHasNotEnoughBalance(claimingAmount, BKNToken.balanceOf(address(this)));

        BKNToken.safeTransfer(user, claimingAmount);
    }

    function getTotalFundsNeeded() public view returns(uint256) {
        uint256 currentTime = block.timestamp;
        uint256 time = endTimeForYielding > 0 ? Math.min(currentTime, endTimeForYielding) : currentTime;

        return totalDeposited + tokensYieldPerSecond.mulDiv(time, ONE) - yieldUpToDeposit.mulDiv(1, ONE);
    }

    function getNetOwed() external view returns(uint256) {
        uint256 currentLiabilities = getTotalFundsNeeded();
        uint256 currentAssets = BKNToken.balanceOf(address(this));

        if(currentLiabilities > currentAssets) {
            return currentLiabilities - currentAssets;
        } else return 0;
    }

    function getWithdrawableUserBalance(address user) public view returns(uint256) {
        uint256 currentYieldingAmount = userStakes[user].amountDeposited;
        uint256 time = endTimeForYielding > 0 ? Math.min(block.timestamp, endTimeForYielding) : block.timestamp;
        uint256 howManySecondsHavePassed = time - userStakes[user].latestDepositTimestamp;
        
        if(currentYieldingAmount == 0 || howManySecondsHavePassed == 0) return currentYieldingAmount;

        uint256 percentageReward = howManySecondsHavePassed * yieldPerSecond;
        uint256 yieldedAmount = currentYieldingAmount.mulDiv(percentageReward, ONE);

        return currentYieldingAmount + yieldedAmount;
    }
}