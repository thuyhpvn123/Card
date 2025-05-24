// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMasterPool} from "./masterpool.sol";
import "forge-std/console.sol";

contract UltraUTXO {
    address public owner; // Contract owner
    address public pendingOwner;

    struct Child {
        uint256 value;
        bool spent;
        address pool;
        address owner;
        address token; // Token address
    }

    mapping(bytes32 => Child) public childUTXOs;
    mapping(address => bool) public isAdmin;
    address public masterpool;

    constructor() {
        owner = msg.sender;
        isAdmin[msg.sender] =  true ;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }
    modifier onlyAdmin() {
        require(isAdmin[msg.sender] == true, "Only admin allowed");
        _;
    }
    function setMasterPool(address _masterpool)external onlyOwner {
        masterpool = _masterpool;        
    }
    function setAdmin(address _admin, bool _setOK)external onlyOwner {
        isAdmin[_admin] = _setOK;
    }

    function initiateOwnershipTransfer(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid address");
        pendingOwner = newOwner;
    }

    function acceptOwnership() public {
        require(msg.sender == pendingOwner, "Not pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function mint(
        // address recipient,
        bytes32 hash,
        uint256 value,
        address ownerPool,
        address token
    ) external onlyAdmin returns (address pool) {
        // require(recipient != address(0), "Invalid recipient address");
        require(masterpool != address(0), "masterpool address not set yet");
        require(childUTXOs[hash].value == 0, "UTXO already exists");
        require(token != address(0), "Invalid token address");
        require(ownerPool != address(0), "Invalid ownerPool address");
        uint256 expiry = block.timestamp + 720 days; // 2 years expiry
        address newPool = address(new PoolUTXO(value, ownerPool, hash, expiry, token,masterpool));

        childUTXOs[hash] = Child({
            value: value,
            spent: false,
            pool: newPool,
            owner: ownerPool,
            token: token
        });
        IMasterPool(masterpool).setPoolUTXO_SC(newPool);
        return newPool;
    }
}

contract PoolUTXO is ReentrancyGuard {
    enum ChildStatus { Unspent, Spent, Redeemed }

    struct Child {
        uint256 value;
        ChildStatus spent;
        address token; // Token address
    }

    struct ParentUTXO {
        uint256 value;
        address owner;
        bytes32 previousParentHash;
        uint256 activeTime;
        bool spent; // New field to track if the UTXO is fully consumed
        address token; // Token address
    }

    // mapping(address => Child) public children; // address(owner) => Child
    // Change the children mapping to include parent hash
    mapping(bytes32 => mapping(address => Child)) public children; // parentHash => ownerAddress => Child

    mapping(bytes32 => ParentUTXO) public parentUTXOs;
    uint256 public expirationTime;
    bytes32 public previousParentHashRoot;
    address public masterpool;
    event ParentUTXOCreated(bytes32 indexed parentHash, address indexed owner, uint256 value, bytes32 previousParentHash);
    event ChildUTXOCreated(bytes32 indexed parentHash, address[] childOwners, uint256[] values, address token);
    event ChildUTXOSpent(bytes32 indexed parentHash, address indexed childOwner, uint256[] values, address[] recipients);
    event ChildUTXORedeem(bytes32 indexed parentHash, address indexed childOwner, bytes32 tokenCard, uint256 value);
    event ChildUTXOWithdraw(bytes32 indexed parentHash, address indexed childOwner, bytes32 tokenCard, uint256 value);
    // receive() external payable {}

    constructor(
        uint256 value,
        address recipient,
        bytes32 previousParentHash,
        uint256 expiry,
        address token,
        address _masterpool
    ) {
        require(value >= 1, "Value must be greater than 1");
        require(token != address(0), "Invalid token address");

        bytes32 parentHash = keccak256(abi.encodePacked(msg.sender, value, block.timestamp, block.number));
        require(parentUTXOs[parentHash].owner == address(0), "ParentHash exists");

        ParentUTXO storage parent = parentUTXOs[parentHash];
        parent.value = value;
        parent.owner = recipient;
        parent.previousParentHash = previousParentHash;
        parent.activeTime = block.timestamp + 60 days;
        parent.token = token;
        expirationTime = expiry;
        previousParentHashRoot = parentHash;
        masterpool = _masterpool;

        emit ParentUTXOCreated(parentHash, recipient, value, previousParentHash);
    }

    modifier notExpired() {
        require(block.timestamp < expirationTime, "Pool expired");
        _;
    }
    function createParentUTXO(
        bytes32 previousParentHash,
        uint256 value,
        uint256[] memory values,
        address[] memory recipients,
        address token
    ) public notExpired returns (bytes32) {
        require(value >= 1, "Value must be greater than 1");
        require(values.length == recipients.length, "Mismatched values and recipients");
        require(values.length <= 50, "Exceeds maximum 50");
        require(token != address(0), "Invalid token address");

        ParentUTXO storage previousParent = parentUTXOs[previousParentHash];
        require(previousParent.value > 0 || previousParent.spent, "Previous parent UTXO does not exist");

        bytes32 parentHash = keccak256(abi.encodePacked(msg.sender, value, block.timestamp, block.number));

        ParentUTXO storage parent = parentUTXOs[parentHash];
        require(parent.owner == address(0), "ParentHash exists");

        parent.value = value;
        parent.owner = msg.sender;
        parent.previousParentHash = previousParentHash;
        parent.activeTime = block.timestamp + 60 days;
        parent.token = token;

        createChildUTXOs(parentHash, values, recipients, token);

        emit ParentUTXOCreated(parentHash, msg.sender, value, previousParentHash);
        return parentHash;
    }

    function createChildUTXOs(
        bytes32 parentHash,
        uint256[] memory values,
        address[] memory recipients,
        address token
    ) public notExpired {
        require(values.length <= 50, "Exceeds maximum 50");
        require(token != address(0), "Invalid token address");

        ParentUTXO storage parent = parentUTXOs[parentHash];
        require(parent.owner == msg.sender, "Not the owner of parent UTXO");
        require(values.length == recipients.length, "Mismatched values and recipients");
        require(parent.value > 0, "Parent value must be greater than 0");
        require(!parent.spent, "Parent UTXO is already spent");

        uint256 totalValue = 0;
        for (uint256 i = 0; i < values.length; i++) {
            require(values[i] >= 1, "Value must be greater than 1");
            require(recipients[i] != address(0), "Invalid recipient address");

            totalValue += values[i];
            require(totalValue <= parent.value, "Total value exceeds parent UTXO");

            if (children[parentHash][recipients[i]].value > 0) {
                children[parentHash][recipients[i]].value += values[i];
            } else {
                children[parentHash][recipients[i]] = Child({ value: values[i], spent: ChildStatus.Unspent, token: token });
            }
        }

        parent.value -= totalValue;
        if (parent.value == 0) {
            parent.spent = true;
        }

        emit ChildUTXOCreated(parentHash, recipients, values, token);
    }

    function transferChildUTXO(
        bytes32 parentHash,
        uint256[] memory values,
        address[] memory recipients,
        address token
    ) public nonReentrant notExpired returns (bytes32) {
        require(values.length == recipients.length, "Mismatched values and recipients");
        require(values.length <= 50, "Exceeds maximum 50");

        address sender = msg.sender;
        require(children[parentHash][sender].value > 0, "Child UTXO does not exist");
        require(children[parentHash][sender].spent == ChildStatus.Unspent, "Child UTXO already spent");

        uint256 value = children[parentHash][sender].value;
        uint256 totalValue = 0;

        for (uint256 i = 0; i < values.length; i++) {
            require(values[i] >= 1, "Value must be greater than 1");
            require(recipients[i] != address(0), "Invalid recipient address");

            totalValue += values[i];
            require(totalValue <= value, "Total value exceeds child UTXO");

            if (children[parentHash][recipients[i]].value > 0) {
                children[parentHash][recipients[i]].value += values[i];
            } else {
                children[parentHash][recipients[i]] = Child({
                    value: values[i],
                    spent: ChildStatus.Unspent,
                    token: token
                });
            }
        }

        children[parentHash][sender].spent = ChildStatus.Spent;

        bytes32 newParentHash = createParentUTXO(parentHash, value, values, recipients, token);
        emit ChildUTXOSpent(parentHash, sender, values, recipients);
        return newParentHash;
    }
    function withdrawChildUTXO(
        bytes32 parentHash,
        bytes32 tokenCard,
        address token
    ) public nonReentrant notExpired {
        address recipient = msg.sender;

        ParentUTXO storage parent = parentUTXOs[parentHash];
        require(parent.token == token, "Invalid token");

        require(children[parentHash][recipient].value > 0, "Child UTXO does not exist");
        require(children[parentHash][recipient].spent == ChildStatus.Unspent, "Child UTXO already spent");

        uint256 value = children[parentHash][recipient].value;
        children[parentHash][recipient].spent = ChildStatus.Redeemed;

        IMasterPool(masterpool).transfer(recipient, value * 1e18 );

        emit ChildUTXOWithdraw(parentHash, recipient, tokenCard, value * 1e18 );
    }

    function redeemChildUTXO(
        bytes32 parentHash,
        bytes32 tokenCard,
        address token
    ) public nonReentrant notExpired {
        address recipient = msg.sender;

        ParentUTXO storage parent = parentUTXOs[parentHash];
        require(block.timestamp >= parent.activeTime, "Child UTXO not yet active");
        require(parent.token == token, "Invalid token");

        require(children[parentHash][recipient].value > 0, "Child UTXO does not exist");
        require(children[parentHash][recipient].spent == ChildStatus.Unspent, "Child UTXO already spent");

        uint256 value = children[parentHash][recipient].value;
        children[parentHash][recipient].spent = ChildStatus.Redeemed;

        // IMasterPool(masterpool).transfer(recipient, value);

        emit ChildUTXORedeem(parentHash, recipient, tokenCard, value);
    }
    function getParentUTXO(bytes32 parentHash) 
        public view returns (uint256 value, address owner, bytes32 previousParentHash) 
    {
        ParentUTXO storage parent = parentUTXOs[parentHash];
        return (parent.value, parent.owner, parent.previousParentHash);
    }
    function getChildUTXO(bytes32 parentHash, address childOwner)
    public
    view
    returns (uint256 value, ChildStatus spent)
    {
        ParentUTXO storage parent = parentUTXOs[parentHash];
        require(parent.owner != address(0), "Parent UTXO does not exist");
        require(children[parentHash][childOwner].value > 0, "Child UTXO does not exist");

        Child storage child = children[parentHash][childOwner];
        require(child.value > 0, "Child UTXO does not exist");
        return (child.value, child.spent);
    }


}
