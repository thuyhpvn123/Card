// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ICode.sol";
contract MigrateDataSC is Ownable {

    mapping(address => address) public mOldeAddToNewAdd;
    ICode public codeContract;
    IMiningCode public miningCodeSC;
    MiningCode [] public codeArr;
    MigrateData[] public amountDataArr;

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
    function BEmigrateData(
        address _user,
        uint256 _boostRate,        -
        uint256 _maxDuration,
        uint256 _expireTime,
        uint256 _amount,
        uint256 _activeTime
    )external onlyBE {

    }
    function checkUserExist ()internal returns(bool){

    }
    // function userMigrateAdd(address user) external {
    //     require(checkUserExist(user),"user data doesnt exist");
    // }
    function FEMigrate(address _oldWallet, bytes memory _publicKeyBls) external {
        address newWallet = msg.sender;
        require (checkUserExist(_oldWallet), "user doesnt exist");
        require (_oldWallet != 0,"address is zero");
        mOldeAddToNewAdd[_oldWallet] = newWallet;
        MiningCode [] memory codeDirectArr = new MiningCode []();
        MigrateData[] memory datas = new MigrateData[]();
        for(){
            codeContract.createCodeDirect(
                _publicKeyBls,
                dataUser.boostRate,
                dataUser.maxDuration,
                dataUser.assignedTo,
                address(0),
                0,
                false,
                dataUser.expireTime
            );
            migrateAmount(
                dataUser.assignedTo,
                dataUser.privateCode,
                dataUser.activeTime, 
                dataUser.amount
            );

        }
    }

}