pragma solidity ^0.5.11;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";

contract SponsorWhitelistControl {
    // ------------------------------------------------------------------------
    // Someone will sponsor the gas cost for contract `contract_addr` with an
    // `upper_bound` for a single transaction.
    // ------------------------------------------------------------------------
    function set_sponsor_for_gas(address contract_addr, uint upper_bound) public payable {
    }

    // ------------------------------------------------------------------------
    // Someone will sponsor the storage collateral for contract `contract_addr`.
    // ------------------------------------------------------------------------
    function set_sponsor_for_collateral(address contract_addr) public payable {
    }

    // ------------------------------------------------------------------------
    // Add commission privilege for address `user` to some contract.
    // ------------------------------------------------------------------------
    function add_privilege(address[] memory) public {
    }

    // ------------------------------------------------------------------------
    // Remove commission privilege for address `user` from some contract.
    // ------------------------------------------------------------------------
    function remove_privilege(address[] memory) public {
    }
}

interface IFundHost {
    function getLpTokenBal(address to) external view returns (uint256);
    function getTotalLpTokenBal() external view returns(uint256);
}

contract DonationFC is IERC777Recipient, Ownable
{
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    IERC1820Registry private _erc1820 = IERC1820Registry(0x866aCA87FF33a0ae05D2164B3D999A804F583222);
    // keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
      0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));

    event TokenTransfer(address indexed tokenAddress, address from, address  to, uint256 value);
    event Transfered(address indexed from, address to, uint256 amount);

    address public fcAddr;
    struct Donation {
        uint256 totalAmount;
        uint256 balance;
        mapping(address => uint256) users;
        uint256 depositCount;
    }

    mapping(address => Donation) public donations;

    uint256 public tlv; // total locked value
    uint256 public totalReward;
    uint256 public totalAllocPoint;
    uint256 public constant ONE = 1e18;
    struct PoolInfo {
        uint256 allocPoint;
        address targetAddress; //  moonswapPair or stakingPool
    }

    mapping(address => PoolInfo) public targetPools;

    struct UserInfo {
        uint256 lpTokenBalance; // LpToken Balance
        uint256 withdrawFCAmount;
    }

    // targetAddres => userWallet
    mapping(address => mapping(address => UserInfo)) public airdropUsers;

    constructor()
        Ownable()
        public
    {

         _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

         // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.add_privilege(users);

        // fcAddr =
    }

    function setFcAddr(address _fcAddr) external onlyOwner {
        fcAddr = _fcAddr;
    }

    function setPool(address _targetAddress, uint256 _allocPoint) external onlyOwner {
        PoolInfo storage poolInfo = targetPools[_targetAddress];
        totalAllocPoint = totalAllocPoint.sub(poolInfo.allocPoint).add(_allocPoint);
        poolInfo.allocPoint = _allocPoint;
    }

    function queryTotalReward(uint256 _tlv) external view returns(uint256 _totalReward){
        _totalReward = _calcTotalReward(_tlv);
    }

    function _calcTotalReward(uint256 _tlv) internal view returns(uint256 _totalReward){
        uint256 level1 = 33500;
        uint256 level2 = 84000;
        uint256 level3 = 242000;
        uint256 level4 = 317000;
        uint256 level5 = 370000;
        if( _tlv >= 1e8){
            _totalReward = level5.add(level4).add(level3).add(level2).add(level1);
        }else if( _tlv >= 5e7){
            _totalReward = level4.add(level3).add(level2).add(level1);
        }else if( _tlv >= 15 * 1e6) {
            _totalReward = level3.add(level2).add(level1);
        }else if( _tlv >= 5e6){
            _totalReward = level2.add(level1);
        }else if( _tlv >= 1e6){
            _totalReward = level1;
        }
    }

    function setTLV(uint256 _tlv) external onlyOwner {
        tlv = _tlv;
        totalReward = _calcTotalReward(tlv);
    }


    function getFcBalance() external view returns(uint256) {
    	return IERC777(fcAddr).balanceOf(address(this));
    }

    function getUserReward(address _targetAddres, address _user) external view returns(uint256){
        return _calcUserReward(_targetAddres, _user);
    }

    function _calcUserReward(address _targetAddres, address _user) internal view returns(uint256){
        PoolInfo storage poolInfo = targetPools[_targetAddres];
        uint256 _poolReward = totalReward.mul(ONE).mul(poolInfo.allocPoint).div(totalAllocPoint);
        uint256 _totalLpTokenBalance = IFundHost(_targetAddres).getTotalLpTokenBal();
        uint256 _userBalance = IFundHost(_targetAddres).getLpTokenBal(_user);
        if(_totalLpTokenBalance > 0){
            return _poolReward.mul(_userBalance).div(_totalLpTokenBalance);
        }else{
            return 0;
        }
    }

    function harvest(address _targetAddres) external {
        uint256 _amount = _calcUserReward(_targetAddres, msg.sender);
        require(_amount > 0, "harvest: not amount");
        UserInfo storage _userInfo = airdropUsers[_targetAddres][msg.sender];

        uint256 _lpTokenBalance = IFundHost(_targetAddres).getLpTokenBal(msg.sender);

        _userInfo.lpTokenBalance = _lpTokenBalance;
        require(_userInfo.withdrawFCAmount < _amount, "harvest: no balance");
        uint256 _withdrawAmount = _amount.sub(_userInfo.withdrawFCAmount);
        _userInfo.withdrawFCAmount = _userInfo.withdrawFCAmount.add(_withdrawAmount);
        Donation storage _donation = donations[fcAddr];
        _donation.balance = _donation.balance.sub(_withdrawAmount);
        IERC777(fcAddr).send(address(msg.sender), _withdrawAmount, "");

        emit Transfered(address(this), msg.sender, _withdrawAmount);
    }

    // MultiSigWalletWithTimeLock future
    // Withdraw without rewards. EMERGENCY ONLY.
    function emergencyWithdraw(address tokenAddress, address to, uint256 _amount) external onlyOwner {
        Donation storage _donation = donations[tokenAddress];
        //require(_donation.balance >= _amount, "emergencyWithdraw: balance no enough~");
        _donation.balance = _donation.balance.sub(_amount);
        IERC777(tokenAddress).send(to, _amount, "");
    }

    function tokensReceived(address operator, address from, address to, uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData) external {

        require(msg.sender == fcAddr, "only receive fc token");

        Donation storage _donation = donations[fcAddr];
        _donation.totalAmount = _donation.totalAmount.add(amount);
        _donation.balance = _donation.balance.add(amount);
        _donation.depositCount = _donation.depositCount.add(1);
        _donation.users[from] = _donation.users[from].add(amount);

        emit TokenTransfer(msg.sender, from, to, amount);
    }

}
