pragma solidity ^0.8.19;
interface PublicKeyFromPrivateKey {
    function getPublicKeyFromPrivate(bytes32 _privateCode) external returns (bytes memory);
}

/// Contract gọi tới FullDB
contract CallerContract {
    // Gán contract FullDB với địa chỉ đã triển khai sẵn C81FF5A1
    PublicKeyFromPrivateKey public wallet = PublicKeyFromPrivateKey(0x00000000000000000000000000000000c81fF5a1);

    // Biến public để lưu kết quả trả về
    bytes public lastPublicKey;

    // Gọi hàm lấy public key từ private code và lưu vào biến public
    function getPublicKeyFromPrivate(bytes32 _privateCode) public returns (bytes memory) {
        bytes memory pubKey = wallet.getPublicKeyFromPrivate(_privateCode);
        lastPublicKey = pubKey;
        return pubKey;
    }
}
contract Test{
    PublicKeyFromPrivateKey public keyContract;
    constructor(address _keyContractAddress){
        keyContract = PublicKeyFromPrivateKey(_keyContractAddress); // Khởi tạo địa chỉ của contract lấy public key

    }


    function get2(bytes memory privateCode,bytes memory secret, address user)external pure returns(bytes32){
        return keccak256(abi.encodePacked(privateCode,secret,user));
    }
    function get(bytes32 _privateCode)external returns(bytes memory){
        return keyContract.getPublicKeyFromPrivate(_privateCode); 
    }
}