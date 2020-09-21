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
    function getUserLpAmount(address to) external view returns (uint256);
    function getTotalLpAmount() external view returns(uint256);
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
    event Transfered(address indexed from, address to, uint256 fcAmount, uint256 cMoonAmount);

    address public fcAddr;
    address public cmoonAddr;

    struct Donation {
        uint256 totalAmount;
        uint256 balance;
        mapping(address => uint256) users;
        uint256 depositCount;
    }

    mapping(address => Donation) public donations;

    uint256 public startRecTime; // start receive time
    uint256 public totalAllocPoint;
    uint256 public constant ONE = 1e18;
    struct PoolInfo {
        uint256 allocPoint;
        address targetAddress; //  moonswapPair or stakingPool
    }

    mapping(address => PoolInfo) public targetPools;

    struct UserInfo {
        uint256 shareAmount; //
        uint256 withdrawFCAmount;
        uint256 withdrawcMoontAmount;
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
    }

    function setFcAddr(address _fcAddr) external onlyOwner {
        fcAddr = _fcAddr;
    }

    function setCmoonAddr(address _cmoonAddr) external onlyOwner {
       cmoonAddr = _cmoonAddr;
    }

    function setStartRecTime(uint256 _time) external onlyOwner {
        startRecTime = _time;
    }

    function setPool(address _targetAddress, uint256 _allocPoint) external onlyOwner {
        PoolInfo storage poolInfo = targetPools[_targetAddress];
        totalAllocPoint = totalAllocPoint.sub(poolInfo.allocPoint).add(_allocPoint);
        poolInfo.allocPoint = _allocPoint;
        poolInfo.targetAddress = _targetAddress;
    }

    function getTokenBalance(address _tokenAddress) external view returns(uint256) {
    	return IERC777(_tokenAddress).balanceOf(address(this));
    }

    function getUserReward(uint256 _totalReward, address _targetAddres, address _user) external view returns(uint256){
        return _calcUserReward(_totalReward, _targetAddres, _user);
    }

    function pendingToken(address _targetAddres, address _user) external view returns(uint256 fcAmount, uint256 cMoonAmount){
        UserInfo storage _userInfo = airdropUsers[_targetAddres][_user];

        if(fcAddr != address(0)) {
            Donation storage _donation = donations[fcAddr];
            uint256 _totalFcReward = _donation.totalAmount;
            uint256 _amount = _calcUserReward(_totalFcReward, _targetAddres, _user);
            fcAmount = _amount.sub(_userInfo.withdrawFCAmount);
        }

        if(cmoonAddr != address(0)){
          Donation storage _donation = donations[cmoonAddr];
          uint256 _totalMoonReward = _donation.totalAmount;
          uint256 _amount = _calcUserReward(_totalMoonReward, _targetAddres, _user);
          cMoonAmount = _amount.sub(_userInfo.withdrawcMoontAmount);
        }
    }

    function _calcUserReward(uint256 _totalReward, address _targetAddres, address _user) internal view returns(uint256){
        PoolInfo storage poolInfo = targetPools[_targetAddres];
        require(poolInfo.targetAddress != address(0), "address is not exists");
        uint256 _poolReward = _totalReward.mul(poolInfo.allocPoint).div(totalAllocPoint);
        uint256 _totalShareAmount = IFundHost(_targetAddres).getTotalLpAmount();
        uint256 _userShareAmount = IFundHost(_targetAddres).getUserLpAmount(_user);
        if(_totalShareAmount > 0){
            return _poolReward.mul(_userShareAmount).div(_totalShareAmount);
        }else{
            return 0;
        }
    }


    function harvest(address _targetAddres) external {
        require(block.timestamp >= startRecTime, "Donation: no start time");

        UserInfo storage _userInfo = airdropUsers[_targetAddres][msg.sender];
        uint256 _userShareAmount = IFundHost(_targetAddres).getUserLpAmount(msg.sender);
        _userInfo.shareAmount = _userShareAmount;
        //
        uint256 _withdrawFCAmount;
        uint256 _withdrawcMoonAmount;
        // airdrop FC
        if(fcAddr != address(0)) {
            Donation storage _donation = donations[fcAddr];
            uint256 _totalFcReward = _donation.totalAmount;
            uint256 _amount = _calcUserReward(_totalFcReward, _targetAddres, msg.sender);
            if(_amount > 0 && _userInfo.withdrawFCAmount < _amount) {
              uint256 _withdrawAmount = _amount.sub(_userInfo.withdrawFCAmount);
              _userInfo.withdrawFCAmount = _userInfo.withdrawFCAmount.add(_withdrawAmount);

              _donation.balance = _donation.balance.sub(_withdrawAmount);
              IERC777(fcAddr).send(address(msg.sender), _withdrawAmount, "");

              _withdrawFCAmount = _withdrawAmount;

            }
        }

        if(cmoonAddr != address(0)){
            Donation storage _donation = donations[cmoonAddr];
            uint256 _totalMoonReward = _donation.totalAmount;
            uint256 _amount = _calcUserReward(_totalMoonReward, _targetAddres, msg.sender);
            if(_amount > 0 && _userInfo.withdrawcMoontAmount < _amount) {
              uint256 _withdrawAmount = _amount.sub(_userInfo.withdrawcMoontAmount);
              _userInfo.withdrawcMoontAmount = _userInfo.withdrawcMoontAmount.add(_withdrawAmount);


              _donation.balance = _donation.balance.sub(_withdrawAmount);
              IERC777(cmoonAddr).send(address(msg.sender), _withdrawAmount, "");

              _withdrawcMoonAmount = _withdrawAmount;
            }
        }

        emit Transfered(address(this), msg.sender, _withdrawFCAmount, _withdrawcMoonAmount);

    }

    // MultiSigWalletWithTimeLock future
    // Withdraw EMERGENCY ONLY.
    function emergencyWithdraw(address tokenAddress, address to, uint256 _amount) external onlyOwner {
        Donation storage _donation = donations[tokenAddress];
        //require(_donation.balance >= _amount, "emergencyWithdraw: balance no enough~");
        require(to != address(0), "Donation: to address is zero");
        _donation.balance = _donation.balance.sub(_amount);
        IERC777(tokenAddress).send(to, _amount, "");
    }

    function tokensReceived(address operator, address from, address to, uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData) external {

        require(msg.sender == fcAddr || msg.sender == cmoonAddr, "only receive fc token");

        Donation storage _donation = donations[msg.sender];
        _donation.totalAmount = _donation.totalAmount.add(amount);
        _donation.balance = _donation.balance.add(amount);
        _donation.depositCount = _donation.depositCount.add(1);
        _donation.users[from] = _donation.users[from].add(amount);

        emit TokenTransfer(msg.sender, from, to, amount);
    }

}
