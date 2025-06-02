// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/code.sol";
import {console} from "forge-std/console.sol";

contract CodeTest is Test {
    Code codeContract;
    address deployer = address(0x111);
    address[] daoMemberArr;
    // address user1 = address(0x555);
    uint256 private constant PRIVATE_KEY = 1;
    address private  user1 = vm.addr(PRIVATE_KEY);
    // bytes32 private  PUBLIC_KEY_BYTES = bytes32(uint256(1));
    // bytes  PUBLIC_KEY = vm.toPublicKey(PRIVATE_KEY);
    address user2 = address(0x666);
    // address user1 = address(0x555);
    address userA = 0xdf182ed5CF7D29F072C429edd8BFCf9C4151394B;
    address userDAO = generateAddress(1);
    constructor() {
        for (uint i=1;i<=12;i++){
            address daoMember = generateAddress(i);
            daoMemberArr.push(daoMember);
        }

        vm.prank(deployer);
        codeContract = new Code(daoMemberArr);     
        // vm.prank(deployer);
        // codeContract.setMintLimit(userA, 100); 
        // vm.prank(deployer);
        // codeContract.setMintLimit(user1, 100);
    }
     function testActivateCodeFlow() public {
        // Tạo publicKey giả lập
        bytes memory publicKey = hex'43ecc93c2949c17cbc9d525e910f91ffc13835786d6da1ddd49347bad123f6fe2fb89c7dcbba6ba85fb976956229fc4daa6ef3676a5df3a89cb5bbb3fe68b327';
        // Thông số cho code
        uint256 boostRate = 100;
        uint256 maxDuration = block.timestamp + 30 days;
        bool transferable = true;
        
        // User1 yêu cầu tạo code mới
        vm.startPrank(userDAO);
        bytes memory newCode = codeContract.requestCode(
            publicKey,
            boostRate,
            maxDuration,
            userA, // assignedTo
            address(0x123), // can có người giới thiệu moi activate dc code
            0, // không có phần thưởng giới thiệu
            transferable
        );
        vm.stopPrank();
        // Kiểm tra code đã được tạo với trạng thái pending
        (
            bytes memory storedPublicKey,
            uint256 storedBoostRate,
            uint256 storedMaxDuration,
            Code.CodeStatus status,
            address assignedTo,
            address referrer,
            uint256 referralReward,
            bool isTransferable,
            uint256 lockUntil,
            Code.LockType lockType
        ) = codeContract.miningCodes(newCode);

        assertEq(keccak256(storedPublicKey), keccak256(publicKey), "Public key should match");
        assertEq(storedBoostRate, boostRate, "Boost rate should match");
        assertEq(storedMaxDuration, maxDuration, "Max duration should match");
        assertEq(uint(status), uint(Code.CodeStatus.Pending), "Status should be Pending");
        assertEq(assignedTo, userA, "Assigned to should be userA");

        // DAO members vote để phê duyệt code
        for (uint i = 0; i < 9; i++) {
            // Cần 9 phiếu phê duyệt
            address voter = daoMemberArr[i];          
          // DAO member vote
            vm.prank(voter);
            codeContract.voteCode(newCode, true);
        }

        // Kiểm tra code đã được phê duyệt
        (,,,status,,,,,, ) = codeContract.miningCodes(newCode);
        assertEq(uint(status), uint(Code.CodeStatus.Approved), "Status should be Approved");
        bytes[] memory codesArr = codeContract.getCodesByOwner(userA);
        console.log("codesArr.length:",codesArr.length);

        // Kích hoạt code
        vm.prank(userA);
        (uint256 returnedBoostRate, uint256 returnedMaxDuration, uint256 expireTime) = codeContract.activateCode(1,userA);
        
        // Kiểm tra các giá trị trả về
        assertEq(returnedBoostRate, boostRate, "Returned boost rate should match");
        assertEq(returnedMaxDuration, maxDuration, "Returned max duration should match");
        assertEq(expireTime, 365 days, "Expire time should be 365 days");

        // Kiểm tra trạng thái code sau khi kích hoạt
        (,,,status,,,,,, ) = codeContract.miningCodes(newCode);
        assertEq(uint(status), uint(Code.CodeStatus.Actived), "Status should be Actived");
        transferCode(newCode,publicKey);
        GetByteCode();
    }
    function GetByteCode()public {
        address user3 = 0xdf182ed5CF7D29F072C429edd8BFCf9C4151394B;
        bytes memory bytesCodeCall = abi.encodeCall(
            codeContract.getCodesByOwner,
            (    
                user3        
            )
        );
        console.log("Code getCodesByOwner: ");
        console.logBytes(bytesCodeCall);
        console.log(
            "-----------------------------------------------------------------------------"
        );

        // requestCode
        bytes memory publicKey1 = hex'43ecc93c2949c17cbc9d525e910f91ffc13835786d6da1ddd49347bad123f6fe2fb89c7dcbba6ba85fb976956229fc4daa6ef3676a5df3a89cb5bbb3fe68b327';
        uint256 boostRate = 100;
        uint256 maxDuration = 1748430097 + 360 days;
        bool transferable = true;

        bytesCodeCall = abi.encodeCall(
            codeContract.requestCode,
            (            
                publicKey1,
                boostRate,
                maxDuration,
                user3, // assignedTo
                address(0x123), // can có người giới thiệu moi activate dc code
                0, // không có phần thưởng giới thiệu
                transferable
            )
        );
        console.log("Code requestCode: ");
        console.logBytes(bytesCodeCall);
        console.log(
            "-----------------------------------------------------------------------------"
        );
    }

     function transferCode(bytes memory oldCodeHash,bytes memory publicKey) public {
        // Prepare transfer message and signature
        string memory command = "transfer";
        uint256 newPublicKeyParam = 2; // Different public key
        bytes memory message = abi.encode(command, newPublicKeyParam);
        // // Setup: Request, approve and activate a code first
        // bytes memory oldCodeHash = _setupActiveCode();

        bytes memory signature = hex'd2e72816fed61387c3f6aa63249a7d4b9ee85429272b947f76f01aac0baefc6d7922b6088416a4883fa6255de11478fde982fc8465cd5329356c0c2efcb62edc01';
        
        // Generate new code hash for comparison
        bytes memory newPublicKey = abi.encodePacked(bytes32(newPublicKeyParam));
        bytes memory newCodeHash = codeContract.generateCode(newPublicKey);
        
        // Transfer the code
        codeContract.transferCode(publicKey, message, signature);

        // Verify old code is deleted
        (,,,Code.CodeStatus oldStatus,,,,,,) = codeContract.miningCodes(oldCodeHash);
        assertEq(uint256(oldStatus), 0);

        // Verify new code exists
        (,,,Code.CodeStatus newStatus,,,,,,) = codeContract.miningCodes(newCodeHash);
        assertEq(uint256(newStatus), uint256(Code.CodeStatus.Actived));
    }
    function testIsValidCode_ValidCode() public view{
        bytes memory publicKey = hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        bytes memory generatedCode = codeContract.generateCode(publicKey);
        bool isValid = codeContract.isValidCode(generatedCode);
        assertTrue(isValid, "Valid code should be recognized correctly");
    }

    function testIsValidCode_InvalidChecksum() public view{
        bytes memory publicKey = hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        bytes memory generatedCode = codeContract.generateCode(publicKey);
        
        // Modify the checksum byte
        generatedCode[32] = bytes1(uint8(generatedCode[32]) + 1);
        bool isValid = codeContract.isValidCode(generatedCode);
        assertFalse(isValid, "Code with invalid checksum should be rejected");
    }

    function testIsValidCode_InvalidLength() public view {
        bytes memory invalidCode = hex"1234"; // Too short
        
        bool isValid;
        try codeContract.isValidCode(invalidCode) returns (bool result) {
            isValid = result;
        } catch {
            isValid = false;
        }
        
        assertFalse(isValid, "Code with invalid length should be rejected");
    }
    function testRequestCode() public {

        bytes memory publicKey = hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"; // Example public key
        uint256 boostRate = 2;
        uint256 maxDuration = 3600;
        address assignedTo = address(2);
        address referrer = address(3);
        uint256 referralReward = 100;
        bool transferable = true;

        vm.prank(userDAO); // Simulate the transaction coming from `owner`
        bytes memory code = codeContract.requestCode(
            publicKey,
            boostRate,
            maxDuration,
            assignedTo,
            referrer,
            referralReward,
            transferable
        );

        // Validate that the request was processed
        assertTrue(code.length >0, " should be greater than 0");
        
    }
    function testVoteCodeAsDAOMember() public {
        //
        //  uint256 limit = 100;
        // vm.prank(deployer);
        // codeContract.setMintLimit(user1,limit);

        bytes memory publicKey = hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"; // Example public key
        uint256 boostRate = 2;
        uint256 maxDuration = 3600;
        address assignedTo = address(2);
        address referrer = address(3);
        uint256 referralReward = 100;
        bool transferable = true;

        vm.prank(userDAO); // Simulate the transaction coming from `owner`
        bytes memory code = codeContract.requestCode(
            publicKey,
            boostRate,
            maxDuration,
            assignedTo,
            referrer,
            referralReward,
            transferable
        );
        //
        vm.prank(daoMemberArr[0]);
        codeContract.voteCode(code, true);

        Code.Vote memory vote = codeContract.getCodeStatus(code);
        assertEq(vote.approveVotes, 1);
        assertEq(vote.denyVotes, 0);

        vm.prank(address(0x9));
        vm.expectRevert("Only DAO members can call this function");
        codeContract.voteCode(code, true);
    }

    function testDenyCode() public {
        // uint256 limit = 100;
        // vm.prank(deployer);
        // codeContract.setMintLimit(user1,limit);

        bytes memory publicKey = hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        
        vm.prank(userDAO);
        bytes memory generatedCode = codeContract.requestCode(publicKey, 100, 3600, user1, address(0), 0, true);
        for (uint i=0; i< 9; i++){
            vm.prank(daoMemberArr[i]);
            codeContract.voteCode(generatedCode, false);
        }
        
        Code.Vote memory vote = codeContract.getCodeStatus(generatedCode);
        assertEq(vote.approveVotes, 0, "Approve votes should be 0");
        assertEq(vote.denyVotes, 9, "Deny votes should be 9");
        
        // Check that the code has been deleted after reaching required denial votes
        (bytes memory publicKeyKq,uint256 boostRate,,Code.CodeStatus status,,,,,,) = codeContract.miningCodes(generatedCode);
        assertEq(publicKeyKq.length,0, "Code should be deleted after denial");
        assertEq(uint8(status),0,"Status of code should be pending");
        assertEq(boostRate,0,"boostRate of code should be 0");

    }
    // function testMintLimit() public {
    //     vm.prank(deployer);
    //     // uint256 limit = 2;
    //     // codeContract.setMintLimit(user1,limit);

    //     vm.startPrank(userDAO);
    //     codeContract.requestCode(hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", 100, 3600, user1, address(0), 0, true);
    //     codeContract.requestCode(hex"2234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", 200, 3600, user1, address(0), 0, true);

    //     vm.expectRevert("Mint limit exceeded");
    //     codeContract.requestCode(hex"3234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", 300, 3600, user1, address(0), 0, true);
    //     vm.stopPrank();
    // }

    // function test_TransferCode_Fails_WhenNotOwner() public {
    //     vm.prank(recipient);
    //     vm.expectRevert("Only owner can transfer");
    //     codeContract.transferCode(testCode, recipient);
    // }

    // function test_LockCode_Success() public {
    //     vm.prank(owner);
    //     codeContract.lockCode(testCode);

    //     // Try to transfer after locking
    //     vm.prank(owner);
    //     vm.expectRevert("Code is locked");
    //     codeContract.transferCode(testCode, recipient);
    // }

    // function test_VoteCode_Success() public {
    //     vm.prank(voter);
    //     codeContract.voteCode(testCode, true); // Voter votes on the code

    //     // No revert = successful vote
    //     assertTrue(true, "Vote should be successful");
    // }

    // function test_VoteCode_Fails_WhenInvalidCode() public {
    //     vm.prank(voter);
    //     vm.expectRevert("Code does not exist");
    //     codeContract.voteCode("FAKECODE", true);
    // }
    function generateAddress(uint256 num) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(num)))));
    }
     // Helper function to set up an active code for testing
    // function _setupActiveCode() internal returns (bytes memory) {
    //     // Request code
    //     bytes memory publicKey = vm.toPublicKey(PRIVATE_KEY);

    //     vm.prank(user1);
    //     bytes memory codeHash = codeContract.requestCode(
    //         publicKey,
    //         100,
    //         block.timestamp + 1 days,
    //         user1,
    //         address(0),
    //         0,
    //         true
    //     );

    //     // Approve code
    //     for (uint256 i = 0; i < 9; i++) {
    //         vm.prank(daoMemberArr[i]);
    //         codeContract.voteCode(codeHash, true);
    //     }

    //     // Activate code
    //     string memory command = "activate";
    //     bytes memory message = abi.encode(command, uint256(0));
    //     bytes memory signature = _sign(PRIVATE_KEY, keccak256(message));
    //     codeContract.activateCode(publicKey, message, signature);

    //     return codeHash;
    // }
    function _sign(uint256 privateKey, bytes32 messageHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }
// function getPublicKeyFromSignature(bytes32 r) public pure returns (bytes memory) {
//     return abi.encodePacked(r); // Returns only the X coordinate (32 bytes)
// }
    function getPublicKeyFromSignature(bytes32 r, bytes32 s) public pure returns (bytes memory) {
        // Precompiled contract for secp256k1 public key recovery is at address 0x01
        uint256 x = uint256(r);
        uint256 y = uint256(s);

        // Concatenate x and y coordinates to get the full uncompressed public key (0x04 + X + Y)
        bytes memory publicKey = abi.encodePacked(bytes1(0x04), r, s);
        return publicKey;
    }
    // Split a signature into r, s, and v
    function _splitSignature(bytes memory sig)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        require(sig.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }


}
