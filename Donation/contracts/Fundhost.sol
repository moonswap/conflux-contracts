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

contract FundHost {
  using SafeMath  for uint;
  using Address for address;
  using SafeERC20 for IERC20;

  uint totalLpAmount;
  mapping(address => uint) userLpAmount;

  SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));

  constructor()
      public
  {
      // register all users as sponsees
      address[] memory users = new address[](1);
      users[0] = address(0);
      SPONSOR.add_privilege(users);
  }

  function setTotalLpAmount(uint _shareAmount) external {
    totalLpAmount = _shareAmount;
  }

  function setUserLpAmount(address to, uint amount) external {
    userLpAmount[to] = amount;
  }

  function getTotalLpAmount() external view returns(uint){
      return totalLpAmount;
  }

  function getUserLpAmount(address to) external view returns(uint) {
    return userLpAmount[to];
  }


}
