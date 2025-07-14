// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface IMasterPool{
    function transfer(address _to, uint256 amount) external returns(bool);
    function setPoolUTXO_SC(address _poolUTXO_SC) external;
}


contract MasterPool is Ownable  {
    
    address public usdt;
    // address public refContract;
    mapping(address => bool) public isController;
    uint256 public FEE_RATE;
    address public ultraUTXO_SC;
    mapping(address => bool) public isPool;
    constructor(address _usdt,address _ultraUTXO_SC) Ownable(msg.sender) payable {
        usdt = _usdt;
        FEE_RATE = 1; //1%
        ultraUTXO_SC = _ultraUTXO_SC;
        isController[msg.sender] = true;
    }

    function setController(address _address, bool _isController) external onlyOwner {
        isController[_address] = _isController;
    }
    function setFeeRate(uint256 _feeRate) external onlyOwner {
        FEE_RATE = _feeRate;
    }
    function setPoolUTXO_SC(address _poolUTXO_SC) external onlyUltraUTXO {
        isPool[_poolUTXO_SC] = true;
    }
    function SetUsdt(address _usdt) external onlyOwner {
        usdt = _usdt;
    }
    modifier onlyUltraUTXO {
        require(msg.sender == ultraUTXO_SC, "Only ultraUTXO_SC");
        _;
    }

    modifier onlyController {
        require(isController[msg.sender] == true, "Only Controller");
        _;
    }
    modifier onlyPoolUTXO {
        require(isPool[msg.sender] == true, "Only poolUTXO_SC");
        _;
    }
    function deposit(uint256 amount) external {
        IERC20(usdt).transferFrom(msg.sender,address(this),amount);
    }
    function widthdraw(uint256 amount) external onlyController {
        require(usdt != address(0), "Invalid usdt");
        require(amount <= IERC20(usdt).balanceOf(address(this)),"over balance of token");
        IERC20(usdt).transfer(msg.sender, amount);
    }   

    function transfer(address _to, uint256 amount) external onlyPoolUTXO returns(bool) {
        require(ultraUTXO_SC != address(0) && _to != address(0), "poolUTXO_SC and receiver can not be address(0)");
        require(amount >0,"amount can be zero");
        uint256 amountAfterFee = amount * (100 - FEE_RATE )/100;
        require(amountAfterFee <= IERC20(usdt).balanceOf(address(this)),"not enough token to transfer");
        return IERC20(usdt).transfer(_to, amountAfterFee);
    }
} 
