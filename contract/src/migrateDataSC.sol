// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ICode.sol";
contract MigrateDataSC is Ownable {


    uint256 public totalAmount;
    mapping(address => address) public mOldeAddToNewAdd;
    ICode public codeContract;
    IMiningCode public miningCodeSC;
    mapping(address => MigrateDataUser[]) public mAddToDataUsers;
    MigrateDataUser[] public userDataArr;
    mapping(address => bool) public isOldAddExist;
    mapping(address => mapping(uint256 => bool)) public isAddIndexMigrated;
    constructor() Ownable(msg.sender){}

    function setCodeContract(address _codeContract) external onlyOwner {
        codeContract = ICode(_codeContract);
    }
    function setMiningCodeContract(address _miningCodeSC) external onlyOwner {
        miningCodeSC = IMiningCode(_miningCodeSC);
    }

    function setOldAddToNewAddress(address _oldAddress, address _newAddress)external onlyOwner{
        mOldeAddToNewAdd[_oldAddress] = _newAddress;
    }
    function BEmigrateData(MigrateDataUser[] memory dataUsers)external onlyOwner {
        for (uint256 i; i<dataUsers.length; i++){
            // require(!isOldAddExist[dataUsers[i].assignedTo],"address already exists");
            mAddToDataUsers[dataUsers[i].assignedTo].push(dataUsers[i]);
            userDataArr.push(dataUsers[i]);
            isOldAddExist[dataUsers[i].assignedTo] = true;
            totalAmount += dataUsers[i].amount;
        }
        
    }
    function getAllMigrateDataUsers() external view returns(MigrateDataUser[] memory ){
        return userDataArr;
    }
    function checkUserExist (address user)internal view returns(bool){
        return isOldAddExist[user] ;
    }
    function getMigrateDataUsers(address user) external view returns(MigrateDataUser[] memory ){
        require(checkUserExist(user),"user data doesnt exist");
        return mAddToDataUsers[user];
    }
    function FEMigrate(address _oldWallet, bytes memory _publicCode, bytes32 _privateCode, uint256 _index, bytes32 _hashDeviceId) external {
        address newWallet = msg.sender;
        require (checkUserExist(_oldWallet), "user doesnt exist");
        require (_oldWallet != address(0),"address is zero");
        require(_index < mAddToDataUsers[_oldWallet].length,"index not in data users");
        require(!isAddIndexMigrated[_oldWallet][_index], "code address in this index already migrated");
        mOldeAddToNewAdd[_oldWallet] = newWallet;
        MigrateDataUser memory dataUser = mAddToDataUsers[_oldWallet][_index];
        codeContract.createCodeDirect(
            _publicCode,
            dataUser.boostRate,
            dataUser.maxDuration,
            msg.sender,
            address(0),
            0,
            false,
            0
        );
        miningCodeSC.migrateAmount(
            msg.sender,
            _privateCode,
            dataUser.activeTime, 
            dataUser.amount,
            _hashDeviceId,
            dataUser.boostRate,
            dataUser.maxDuration,
            _publicCode
        );
        isAddIndexMigrated[_oldWallet][_index] = true;
        mAddToDataUsers[_oldWallet][_index].isMigrated = true;

    }

}