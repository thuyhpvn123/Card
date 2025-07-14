// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/mining.sol";
import "../src/code.sol";
import "../src/usdt.sol";
// import "../src/PublicKeyFromPrivateKey.sol";
// Mock contract for PublicKeyFromPrivateKey
contract PublicKeyFromPrivateKeyMock  {
   function getPublicKeyFromPrivate(bytes32 _privateKey) external pure returns (bytes memory) {
        // Mock implementation: Return a deterministic result based on the hash of the private key
        return hex"43ecc93c2949c17cbc9d525e910f91ffc13835786d6da1ddd49347bad123f6fe2fb89c7dcbba6ba85fb976956229fc4daa6ef3676a5df3a89cb5bbb3fe68b327";
    }
}

// Mock ERC20 Token for testing
// contract MockERC20 is ERC20 {
//     constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
//     function mint(address to, uint256 amount) public {
//         _mint(to, amount);
//     }
// }
contract MockCode {
    function activateCode(uint256 indexCode, address user) external returns (uint256 boostRate, uint256 maxDuration, uint256 expireTime) {
        // Mock implementation that returns predefined values
        return (100000*indexCode, 30 days+indexCode, block.timestamp + 365 days+indexCode);
    }
}
contract MiningContractsTest is Test {
    // Contracts
    GetJob public getJob;
    MiningDevice public miningDevice;
    MiningUser public miningUser;
    PendingMiningDevice public pendingMiningDevice;
    MiningCodeSC public miningCode;
    USDT public usdtToken;
    PublicKeyFromPrivateKeyMock public keyContract;
    // CallerContract public keyContract;
    // Code public codeContract;
    Code codeContract;
    // MockCode codeContract;

    // Accounts
    address public owner;
    // address public device1;
    address public user2;
    address public userA;
    address public device1;
    address public device2;
    address public validator;
    address public BE;
    // uint256 device1PrivateKey;
    // uint256 user2PrivateKey;
    // uint256 device1PrivateKey;
    uint256 device2PrivateKey;
    uint256 currentTime = 1746583269;// 7/5/2025
    address[] daoMemberArr;
    bytes32 hashedPrivateCode;
    bytes32 hashedPublicKey;
    bytes32 privateCode = 0x61cffafd93c74678852bbc7bf67ef35074ce175069d34a3fc142c96506e0a8c6;//FE tu gen random privateCode //trong vd la lay tu private key cua vi df182ed5cf7d29f072c429edd8bfcf9c4151394b
    bytes secret = "123";
    address userDAO = generateAddress(1);
    uint256 expireTime = 1750235327 +365 days;

    // Setup before each test
    constructor(){
        owner = address(0x111);
        vm.startPrank(owner);
        // Setup accounts with private keys
        
        // device1PrivateKey = 0x1;
        // user2PrivateKey = 0x2;
        // device1PrivateKey = 0x3;
        device2PrivateKey = 0x4;
        
        device1 = 0xdf182ed5CF7D29F072C429edd8BFCf9C4151394B;
        user2 = 0x55798165960a62cED34a0d86e36B1758D1303907;
        userA = 0xB50b908fFd42d2eDb12b325e75330c1AaAf35dc0;
        // device1 = vm.addr(device1PrivateKey);
        device2 = vm.addr(device2PrivateKey);
        validator = address(0x5);
        BE = address(0x11);
        
        // Deploy USDT token mock
        // usdtToken = new MockERC20("MockUSDT", "USDT");
        usdtToken = new USDT();

        usdtToken.mintToAddress(device1, 1_000_000 * 10**18);
        
        // Transfer USDT to test accounts
        // usdtToken.transfer(device1, 10_000 * 10**6);
        // usdtToken.transfer(user2, 10_000 * 10**6);
        
        // // Deploy PublicKeyFromPrivateKey mock
        keyContract = new PublicKeyFromPrivateKeyMock();
        // keyContract = new CallerContract();

        // Deploy contracts
        getJob = new GetJob();
        miningDevice = new MiningDevice();
        miningUser = new MiningUser(
            BE, // BE address
            address(usdtToken),
            address(miningDevice),
            userA //user2 la rootUser
        );
        
        pendingMiningDevice = new PendingMiningDevice(
            address(miningDevice),
            address(miningUser)
        );
        for (uint i=1;i<=12;i++){
            address daoMember = generateAddress(i);
            daoMemberArr.push(daoMember);
        }

        codeContract = new Code(daoMemberArr);     
        // codeContract.setMintLimit(device1, 100); 
        // codeContract = new MockCode();
        miningCode = new MiningCodeSC(address(keyContract), address(codeContract));
        
        // Setup contract connections
        miningCode.setMiningDevice(address(miningDevice));
        miningCode.setMiningUser(address(miningUser));
        miningDevice.setMiningUser(address(miningUser));
        miningDevice.setMiningCode(address(miningCode));
        pendingMiningDevice.setValidator(validator);
        miningDevice.setAdmin(address(pendingMiningDevice),true);
        miningDevice.setAdmin(address(miningCode),true);
        vm.stopPrank();

    }
    function testActivateCodeFlow() public {
    //     // Tạo publicKey giả lập
    //     //public key cua vi 0xdf182ed5CF7D29F072C429edd8BFCf9C4151394B
    //     bytes memory publicKeyUserA = hex'43ecc93c2949c17cbc9d525e910f91ffc13835786d6da1ddd49347bad123f6fe2fb89c7dcbba6ba85fb976956229fc4daa6ef3676a5df3a89cb5bbb3fe68b327';
    //     // Thông số cho code
    //     uint256 boostRate = 100_000;
    //     uint256 maxDuration = currentTime + 30 days;
    //     bool transferable = true;
        
    //     // User1 yêu cầu tạo code mới
    //     vm.startPrank(userDAO);
    //     bytes memory newCode = codeContract.requestCode(
    //         publicKeyUserA,
    //         boostRate,
    //         maxDuration,
    //         userA, // assignedTo
    //         address(0x123), // can có người giới thiệu moi activate dc code
    //         0, // không có phần thưởng giới thiệu
    //         transferable,
    //         expireTime
    //     );
    //     vm.stopPrank();
    //     // Kiểm tra code đã được tạo với trạng thái pending
    //     (
    //         bytes memory storedPublicKey,
    //         uint256 storedBoostRate,
    //         uint256 storedMaxDuration,
    //         CodeStatus status,
    //         address assignedTo,
    //         address referrer,
    //         uint256 referralReward,
    //         bool isTransferable,
    //         uint256 lockUntil,
    //         LockType lockType,
    //         uint256 expireTime
    //     ) = codeContract.miningCodes(newCode);

    //     assertEq(keccak256(storedPublicKey), keccak256(publicKeyUserA), "Public key should match");
    //     assertEq(storedBoostRate, boostRate, "Boost rate should match");
    //     assertEq(storedMaxDuration, maxDuration, "Max duration should match");
    //     assertEq(uint(status), uint(CodeStatus.Pending), "Status should be Pending");
    //     assertEq(assignedTo, userA, "Assigned to should be userA");

    //     // DAO members vote để phê duyệt code
    //     for (uint i = 0; i < 9; i++) {
    //         // Cần 9 phiếu phê duyệt
    //         address voter = daoMemberArr[i];          
    //       // DAO member vote
    //         vm.prank(voter);
    //         codeContract.voteCode(newCode, true);
    //     }

    //     // Kiểm tra code đã được phê duyệt
    //     (,,,status,,,,,, ,) = codeContract.miningCodes(newCode);
    //     assertEq(uint(status), uint(CodeStatus.Approved), "Status should be Approved");
    //     bytes[] memory codesArr = codeContract.getCodesByOwner(userA);
    //     assertEq(1,codesArr.length,"code array should have 1 code");

    //     // // Kích hoạt code
    //     // vm.prank(userA);
    //     // (uint256 returnedBoostRate, uint256 returnedMaxDuration, uint256 expireTime1) = codeContract.activateCode(1,userA);
        
    //     // // Kiểm tra các giá trị trả về
    //     // assertEq(returnedBoostRate, boostRate, "Returned boost rate should match");
    //     // assertEq(returnedMaxDuration, maxDuration, "Returned max duration should match");
    //     // assertEq(expireTime1, 1781771327, "Expire time should be 365 days");

    //     // // Kiểm tra trạng thái code sau khi kích hoạt
    //     // (,,,status,,,,,, ,) = codeContract.miningCodes(newCode);
    //     // assertEq(uint(status), uint(CodeStatus.Actived), "Status should be Actived");
    //     activateCodeWithOTP();
    }


    // ========================= MiningUser Tests =========================
        function activateCodeWithOTP() public {
        //userA la nguoi gioi thieu -> tao code. user2 la nguoi duoc gioi thieu goi refUserViaQRCode
        vm.warp(currentTime);
        // Refer userA by user2( user2 gioi thieu userA -o day user2 la rootUser thi moi quet duoc dau tien)
        vm.prank(userA);
        string memory otp = miningUser.createOTP();
        vm.prank(user2);//nguoi duoc gioi thieu
        bytes32 hashDeviceID = keccak256(abi.encodePacked("1"));
        miningUser.refUserViaQRCode(otp, hashDeviceID);

        //level2
        vm.warp(currentTime + 3 minutes);
        vm.prank(user2);
        string memory otp1 = miningUser.createOTP();
        address user4 = address(0x333);
        vm.prank(user4);//nguoi duoc gioi thieu
        bytes32 hashDeviceID1 = keccak256(abi.encodePacked("2"));
        miningUser.refUserViaQRCode(otp1, hashDeviceID1);
        
        activationFlow(hashDeviceID);
        // GetByteCode();
    }
    // ========================= MiningCode Tests =========================
     function activationFlow(bytes32 hashDeviceID) public {
        //1.genCode
        // Calculate expected hashes
        hashedPrivateCode = keccak256(abi.encodePacked(privateCode));
        // bytes memory publicKey = keyContract.getPublicKeyFromPrivate(privateCode);
        bytes memory publicKey =hex"43ecc93c2949c17cbc9d525e910f91ffc13835786d6da1ddd49347bad123f6fe2fb89c7dcbba6ba85fb976956229fc4daa6ef3676a5df3a89cb5bbb3fe68b327";
        //thuc te publicKey lay tu  getPublicKeyFromPrivate cho ket qua tuong tu
        hashedPublicKey = keccak256(abi.encodePacked(publicKey));
        console.log("hashedPublicKey genCode:");
        console.logBytes32(hashedPublicKey);
        // Generate a code first
        // bytes32 emptyBytes32 = 0x0000000000000000000000000000000000000000000000000000000000000000;
        vm.prank(userA);
        miningCode.genCode(1, hashedPrivateCode, hashedPublicKey);
        //2.Cac buoc activateCode
        // Step 1: Create commit hash (privateCode + secret + user address)
        bytes32 commitHash = keccak256(abi.encodePacked(privateCode, secret, user2));
        console.log("commitHash:");
        console.logBytes32(commitHash);
        // User calls commitActivationCode with the hash
        vm.startPrank(user2);
        miningCode.commitActivationCode(commitHash);
        vm.stopPrank();
        
        // Step 2: Wait for 15 seconds (the minimum reveal delay)
        vm.warp(currentTime + 3 minutes + 15 seconds);
        
        // Step 3: User activates the code with the actual privateCode and secret
        vm.startPrank(user2);
        miningCode.activateCode(privateCode, secret);
        MiningCodeSC.DataCode[] memory dataCodes = miningCode.getActivePrivateCode(user2);
        assertEq(dataCodes.length,1);

        vm.stopPrank();
        // Step 4: Verify code activation and linking
        
        // Extract device address from hashedPublicKey - matches the logic in activateCode
        address expectedDeviceAddress = address(uint160(uint256(hashedPublicKey) & 0x0000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
        
        // Check that the code is activated for the user
        DataCode memory activatedCode = getMiningPrivateCode(hashedPrivateCode);
        
        // Assert code activation
        assertEq(activatedCode.owner, user2, "Code should be activated for the user");
        assertEq(activatedCode.device, expectedDeviceAddress, "Device should be properly set");
        assertTrue(activatedCode.activeTime > 0, "Active time should be set");
        
        // Verify that the user and device are linked
        assertTrue(isDeviceLinkedToUser(device1, user2), "User should be linked to device");
        //claim
        vm.warp(currentTime + 3 minutes + 15 seconds + 24 hours +16 seconds);// sau khi activateCode hon 24h moi goi claim duoc khong se loi not match time
        vm.prank(owner);
        // uint256 halvingReward = 1000;
        miningCode.claim();

        // // Check balances for code1
        uint256 expectedCode1Reward = 6250000000000000000; // 100,000 = maxWithdrawable
        (,address deviceA,,,,,,,,,,) = miningCode.miningPrivateCodes(hashedPrivateCode);
        assertEq(miningDevice.balanceOf(deviceA), expectedCode1Reward);
        // assertEq(mockMiningDevice.getBalance(ref1), expectedCode1Reward * 20 / 100); // 20,000
        // assertEq(mockMiningDevice.getBalance(ref2), expectedCode1Reward * 10 / 100); // 10,000
        // assertEq(mockMiningDevice.getBalance(ref3), expectedCode1Reward * 5 / 100);  // 5,000
        // assertEq(mockMiningDevice.getBalance(ref4), expectedCode1Reward * 5 / 100);  // 5,000
        // assertEq(mockMiningDevice.getBalance(showroom1), expectedCode1Reward * 20 / 100); // 20,000

        // // Check balances for code2
        // uint256 expectedCode2Reward = 150 * halvingReward; // 150,000
        // assertEq(mockMiningDevice.getBalance(device2), expectedCode2Reward);
        
        // // Verify that activeCodes still contains both codes (not expired)
        // assertEq(miningCode.getActiveCodesLength(), 2);
        (BalanceDevice[] memory arr,uint256 totalAmount) = miningDevice.getAllDeviceBalances(device1);
        console.log("totalAmount:",totalAmount);
        console.log("arr:",arr.length);
        address user3 = address(0x1111);
        vm.prank(user3);
        miningUser.switchWalletWithDevice(hashDeviceID);
        (BalanceDevice[] memory arr1,uint256 totalAmount1) = miningDevice.getAllDeviceBalances(user3);
        console.log("totalAmountUser3:",totalAmount1);
        console.log("arr3:",arr1.length);
        vm.prank(device1);
        miningUser.switchWalletWithDevice(hashDeviceID);
        (BalanceDevice[] memory arr3,uint256 totalAmount3) = miningDevice.getAllDeviceBalances(device1);
        console.log("totalAmountdevice1:",totalAmount3);
        console.log("arr1:",arr3.length);
        BalanceWallet[] memory balanceArr = miningUser.getDownlineBalances(device1);
        console.log("balanceArr:",balanceArr.length);
        //depositToWithdraw
        //1.owner transfer usdt to device1 
        // vm.prank(owner);
        // usdtToken.mintToAddress(device1, 10_000);
        // vm.deal(address(miningUser),1 ether);
        // //2.device1 approve and deposit to withdraw mtd
        // vm.startPrank(device1);
        // usdtToken.approve(address(miningUser),10_000);
        // // uint256 usdtAmount = 10_000;
        // uint256 resourceAmount = 1;
        // miningUser.depositToWithdraw(deviceA,resourceAmount);
        // vm.stopPrank();
    }
    
    // Helper function to access and return the miningPrivateCodes mapping value
    function getMiningPrivateCode(bytes32 _hashedPrivateCode) internal view returns (DataCode memory) {
        // Use the exposed mapping to get the data code
        (
            address owner,
            address device,
            uint256 boostRate,
            uint256 maxDuration,
            address showroom,
            address ref_1,
            address ref_2,
            address ref_3,
            address ref_4,
            uint256 activeTime,
            uint256 expireTime,
            bytes32 privateCode
        ) = miningCode.miningPrivateCodes(_hashedPrivateCode);
        
        DataCode memory code;
        code.owner = owner;
        code.device = device;
        code.boostRate = boostRate;
        code.maxDuration = maxDuration;
        code.showroom = showroom;
        code.ref_1 = ref_1;
        code.ref_2 = ref_2;
        code.ref_3 = ref_3;
        code.ref_4 = ref_4;
        code.activeTime = activeTime;
        code.expireTime = expireTime;
        code.privateCode = privateCode;
        return code;
    }
    
    // Helper function to check if a device is linked to a user
    function isDeviceLinkedToUser(address _user, address _device) internal view returns (bool) {
        return miningDevice.isLinkUserDevice(_device,_user);
    }
    
    // Define DataCode struct to match the one in MiningCode
    struct DataCode {
        address owner;
        address device;
        uint256 boostRate;
        uint256 maxDuration;
        address showroom;
        address ref_1;
        address ref_2;
        address ref_3;
        address ref_4;
        uint256 activeTime;
        uint256 expireTime;
        bytes32 privateCode;
    }
    // function testActivateCodeTooSoon() public {
    //     bytes32 privateCode = 0x61cffafd93c74678852bbc7bf67ef35074ce175069d34a3fc142c96506e0a8c6;
    //     // bytes memory secret = "abcd";

    //     // Create and commit code
    //     bytes32 commitHash = keccak256(abi.encodePacked(hex'61cffafd93c74678852bbc7bf67ef35074ce175069d34a3fc142c96506e0a8c6', hex'abcd', hex'68B45379FEa4d354685e1C473962475a8119a2ba'));
    //     console.logBytes32(commitHash);
    //     // bytes32 abc = keccak256(abi.encodePacked(hex"abcd"));
    //     // console.log("abc:");
    //     // console.logBytes32(abc);
    //     vm.prank(device1);
    //     miningCode.commitActivationCode(commitHash);
        
    //     // Try to activate too soon
    //     vm.prank(device1);
    //     vm.expectRevert("Wait for reveal time");
    //     miningCode.activateCode(privateCode, hex'abcd');
    //             GetByteCode();

    // }
    
    // function testActivateCodeWrongDetails() public {
    //     // Create and commit code
    //     bytes32 commitHash = keccak256(abi.encodePacked(privateCode, secret, device1));
        
    //     vm.prank(device1);
    //     miningCode.commitActivationCode(commitHash);
        
    //     // Wait for reveal delay
    //     vm.warp(block.timestamp + 16); // 16 seconds
        
    //     // Try to activate with wrong code
    //     vm.prank(device1);
    //     vm.expectRevert("Invalid code");
    //     miningCode.activateCode("wrongcode", secret);
        
    //     // Try to activate with wrong secret
    //     vm.prank(device1);
    //     vm.expectRevert("Invalid code");
    //     miningCode.activateCode(privateCode, "wrongsecret");
    // }
    //     function testCommitActivationCode() public {
    //     // Create commit hash
    //     bytes32 commitHash = keccak256(abi.encodePacked(privateCode, secret, device1));
        
    //     // Commit the code
    //     vm.prank(device1);
    //     miningCode.commitActivationCode(commitHash);
        
    //     // Check commit was saved
    //     (bytes32 savedHash, uint256 commitTime) = miningCode.commits(device1);
    //     assertEq(savedHash, commitHash, "Commit hash should be saved");
    //     assertEq(commitTime, block.timestamp, "Commit time should be set");
    // }

    function generateAddress(uint256 num) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(num)))));
    }

    // // ========================= GetJob Tests =========================

    // function testGetJobFirstTime() public {
    //     vm.warp(currentTime);
    //     // Get job for the first time
    //     vm.prank(device1);
    //     (bytes32 jobHash, string memory jobType, string memory dataLink) = getJob.getJob(bytes32(0), "");
        
    //     // Check job was created
    //     assertNotEq(jobHash, bytes32(0), "Job hash should not be zero");
    //     assertTrue(bytes(jobType).length > 0, "Job type should not be empty");
    //     assertTrue(bytes(dataLink).length > 0, "Data link should not be empty");
        
    //     // Check user is active
    //     assertTrue(getJob.isInActiveList(device1), "User should be in active list");
    // }
    
    // function testGetJobComplete() public {
    //     vm.warp(currentTime);
    //     // First get a job
    //     vm.prank(device1);
    //     (bytes32 jobHash, , ) = getJob.getJob(bytes32(0), "");
        
    //     // Wait 1 minute
    //     vm.warp(block.timestamp + 61);
        
    //     // Complete job and get a new one
    //     vm.prank(device1);
    //     (bytes32 newJobHash, , ) = getJob.getJob(jobHash, "Job completed successfully");
        
    //     // Check new job is different
    //     assertNotEq(newJobHash, jobHash, "New job hash should be different");
    // }
    
    // function testGetJobTooSoon() public {
    //     vm.warp(currentTime);
    //     // Get first job
    //     vm.prank(device1);
    //     getJob.getJob(bytes32(0), "");
        
    //     // Try to get another job too soon (should fail)
    //     vm.prank(device1);
    //     vm.expectRevert("Must wait 1 minute before calling again");
    //     getJob.getJob(bytes32(0), "");
    // }
    
    // function testGetJobWrongHash() public {
    //     vm.warp(currentTime);
    //     // Get first job
    //     vm.prank(device1);
    //     getJob.getJob(bytes32(0), "");
        
    //     // Wait 1 minute
    //     vm.warp(block.timestamp + 61);
        
    //     // Try to complete with wrong hash
    //     bytes32 wrongHash = keccak256(abi.encodePacked("wrong hash"));
    //     vm.prank(device1);
    //     vm.expectRevert("Invalid job hash");
    //     getJob.getJob(wrongHash, "Job completed successfully");
    // }
    
    // function testGetRecentActiveUsers() public {
    //     vm.warp(currentTime);
    //     // device1 gets job
    //     vm.prank(device1);
    //     getJob.getJob(bytes32(0), "");
        
    //     // Advance time and user2 gets job
    //     vm.warp(block.timestamp + 61);
    //     vm.prank(user2);
    //     getJob.getJob(bytes32(0), "");
        
    //     // Get recent users (last 30 seconds)
    //     address[] memory recentUsers = getJob.getRecentActiveUsers(block.timestamp - 30);
        
    //     // Check user2 is in recent users
    //     bool found = false;
    //     for (uint i = 0; i < recentUsers.length; i++) {
    //         if (recentUsers[i] == user2) {
    //             found = true;
    //             break;
    //         }
    //     }
    //     assertTrue(found, "User2 should be in recent users");
    // }
    
    // // ========================= MiningDevice Tests =========================
    
    // function testLinkDeviceToUser() public {
    //     vm.warp(currentTime);
    //     uint256 timestamp = currentTime;
    //     address user3 = 0x043E61E490EC76Aa636758D72A15201923593C72;      
    //     bytes memory signature = hex"6055f2424f681caea5004ba44d860ef3de8a395e498e7249658ad323c288a6d01c9f293058a69a14a1a7137929640d8a561ce18b1cae6b2959c52f5b8783a34901";
    //     // Link device to user
    //     vm.prank(device1);
    //     miningDevice.deviceLinkToUser(user3, signature, timestamp);
        
    //     // Check link was successful
    //     assertTrue(miningDevice.isLinkUserDevice(user3, device1), "Device should be linked to user");
    // }
    
    function testUserLinkToDevice() public {
        //
        // uint256 timestamp = 1748601645;
        // //user ki = 0xdf182ed5cf7d29f072c429edd8bfcf9c4151394b
        // address deviceA = 0x043E61E490EC76Aa636758D72A15201923593C72;
        // bytes memory signatureA = hex"84d7bbfcaa16b7368c719087bfc1dc3177ac614f98cea5af1daada3204f6c5681a9626c4f2febf2d8d08c20a31d069d09b31799153a9a88524b6009bd402495600";
        //
        vm.warp(1752033524);
        uint256 timestamp = 1752033524;
        address deviceA = 0x3d9Cf842Bd57D60c760622Fb394BE918623f5a7a;
        //signature cua device ky voi message = device+time
        bytes memory signature = hex"d9d576b3c22f9ea72c0ffb831218aa51f26525a3a67e0573a7f7a86aa5f29f5869a33fa08177314bebaec9bae2e529f06aef1452537b411f9bea432b2fdd1a8a00";
        // Link user to device 
        // vm.prank(device1);
        address deviceB = 0xf5f4717635445460f0462fc80AC4fdDd3dfd3c47;
        vm.prank(deviceB);
        miningDevice.userLinkToDevice(deviceA, signature, timestamp);
        GetByteCode();
        // Check link was successful
        // assertTrue(miningDevice.isLinkUserDevice(device1, deviceA), "User should be linked to device");
    }
    
    // function testAddBalance() public {
    //     // Link device to user first
    //     vm.warp(currentTime);
    //     uint256 timestamp = currentTime;
    //     address user3 = 0x043E61E490EC76Aa636758D72A15201923593C72;
    //     //signature cua device ky voi message = device+time
    //     bytes memory signature = hex"6055f2424f681caea5004ba44d860ef3de8a395e498e7249658ad323c288a6d01c9f293058a69a14a1a7137929640d8a561ce18b1cae6b2959c52f5b8783a34901";
        
    //     vm.prank(device1);
    //     miningDevice.deviceLinkToUser(user3, signature, timestamp);
        
    //     // Advance time by 24 hours
    //     vm.warp(block.timestamp + 24 * 60 * 60 + 1);
    //     vm.prank(address(pendingMiningDevice));
    //     // Add balance
    //     uint256 amount = 1 ether;
    //     miningDevice.addBalance(device1, amount);
        
    //     // Check balance
    //     assertEq(miningDevice.balanceOf(device1), amount, "Device balance should be updated");
    // }
    
    // function testAddBalanceTooSoon() public {
    //     // Link device to user first
    //     vm.warp(currentTime);
    //     uint256 timestamp = currentTime;
    //     address user3 = 0x043E61E490EC76Aa636758D72A15201923593C72;
    //     // bytes32 message = keccak256(abi.encodePacked(device1, timestamp));
    //     // (uint8 v, bytes32 r, bytes32 s) = vm.sign(device1PrivateKey, message);
    //     // bytes memory signature = abi.encodePacked(r, s, v);
    //     bytes memory signature = hex"6055f2424f681caea5004ba44d860ef3de8a395e498e7249658ad323c288a6d01c9f293058a69a14a1a7137929640d8a561ce18b1cae6b2959c52f5b8783a34901";

    //     vm.prank(device1);
    //     miningDevice.deviceLinkToUser(user3, signature, timestamp);
    //     vm.prank(address(pendingMiningDevice));
    //     // Try to add balance immediately (should fail)
    //     uint256 amount = 1 ether;
    //     vm.expectRevert("not match time");
    //     miningDevice.addBalance(device1, amount);
    // }
    
    // // ========================= PendingMiningDevice Tests =========================
    
    // function testAddPendingReward() public {
       
    //     vm.prank(validator);
    //     // Add pending reward
    //     uint256 amount = 1 ether;
    //     pendingMiningDevice.addPendingReward(device1, amount);
        
    //     // Check pending balance
    //     assertEq(pendingMiningDevice.pendingBalance(device1), amount, "Pending balance should be updated");
        
    //     // Check reward details
    //     (uint256 rewardAmount, uint256 pendingSince, bool isClaimed) = pendingMiningDevice.minerRewards(device1, 0);
    //     assertEq(rewardAmount, amount, "Reward amount should match");
    //     assertEq(pendingSince, block.timestamp, "Pending since should be set to current time");
    //     assertFalse(isClaimed, "Reward should not be claimed yet");
    // }
    
    // function testClaimRewardTooSoon() public {
    //      vm.prank(validator);
    //     // Add pending reward
    //     uint256 amount = 1 ether;
    //     pendingMiningDevice.addPendingReward(device1, amount);
        
    //     // Try to claim too soon (should fail)
    //     vm.prank(device1);
    //     vm.expectRevert("No reward available for claim");
    //     pendingMiningDevice.claimReward();
    // }
    
    // function testClaimRewardAfterDelay() public {
    //     // Setup: Link device to user and add balance to device
    //     vm.warp(currentTime);
    //     uint256 timestamp = currentTime;
    //     address user3 = 0x043E61E490EC76Aa636758D72A15201923593C72;
    //     // bytes32 message = keccak256(abi.encodePacked(device1, timestamp));
    //     // (uint8 v, bytes32 r, bytes32 s) = vm.sign(device1PrivateKey, message);
    //     // bytes memory signature = abi.encodePacked(r, s, v);
    //     bytes memory signature = hex"6055f2424f681caea5004ba44d860ef3de8a395e498e7249658ad323c288a6d01c9f293058a69a14a1a7137929640d8a561ce18b1cae6b2959c52f5b8783a34901";

    //     vm.prank(device1);
    //     miningDevice.deviceLinkToUser(user3, signature, timestamp);
    //      vm.prank(validator);
    //     // Add pending reward
    //     uint256 amount = 1 ether;
    //     pendingMiningDevice.addPendingReward(device1, amount);
        
    //     // Advance time by 48 hours
    //     vm.warp(block.timestamp + 48 * 60 * 60 + 1);
        
    //     // This would need proper integration with MiningDevice.addBalance
    //     // For a proper test, we'd need to mock or use proper integration
    // }
    
    function GetByteCode()public{
        //commitActivationCode
        address user = 0xA620249dc17f23887226506b3eB260f4802a7efc;
        bytes32 commitHash = keccak256(abi.encodePacked(privateCode, secret, user));
        bytes memory bytesCodeCall = abi.encodeCall(
            miningCode.commitActivationCode,
            (commitHash)
        );
        console.log("miningCode commitActivationCode: ");
        console.logBytes(bytesCodeCall);
        console.log(
            "-----------------------------------------------------------------------------"
        );
        //miningCode activateCode
        bytes32 privateCodeA = 0x61cffafd93c74678852bbc7bf67ef35074ce175069d34a3fc142c96506e0a8c6;
        // bytes memory secret1 = "123";
        bytesCodeCall = abi.encodeCall(
            miningCode.activateCode,
            (privateCodeA,secret)
        );
        console.log("miningCode activateCode: ");
        console.logBytes(bytesCodeCall);
        console.log(
            "-----------------------------------------------------------------------------"
        );
    //     // refUserViaQRCode
    //     // address userA = 0xdf182ed5CF7D29F072C429edd8BFCf9C4151394B;
    //     // string memory token = "fhgwzThJRciYxtivwue_p4:APA91bGbyanMsZ_99BvQ7mYoGH8hNEL6gsCEfVBeFtzmS8ioVQ2B2QajmuXcq1z-m4f-HyBQ5x0IaDZJ6iOm-hWgF_lDJ4wbaoaCRLC0Gx2k43BQdmiVXgY";
    //     // bytes memory signature = hex"b229e507b6b2a9d2fad28b73e68f3ec8c7ceb401886a3421e1cff3cb1435d7560fead7fc34bc9358fee9df58dd88aaacd547feaa8bd95a088835d0f8cc65168a01";
    //     // address userA = 0xdf182ed5CF7D29F072C429edd8BFCf9C4151394B;
    //     // string memory token = "fhgwzThJRciYxtivwue_p4:APA91bGbyanMsZ_99BvQ7mYoGH8hNEL6gsCEfVBeFtzmS8ioVQ2B2QajmuXcq1z-m4f-HyBQ5x0IaDZJ6iOm-hWgF_lDJ4wbaoaCRLC0Gx2k43BQdmiVXgY";
    //     // bytes memory signature = hex"b229e507b6b2a9d2fad28b73e68f3ec8c7ceb401886a3421e1cff3cb1435d7560fead7fc34bc9358fee9df58dd88aaacd547feaa8bd95a088835d0f8cc65168a01";
    //     // address userA = 0x68B45379FEa4d354685e1C473962475a8119a2ba;
    //     // string memory token = "fhgwzThJRciYxtivwue_p4:APA91bGbyanMsZ_99BvQ7mYoGH8hNEL6gsCEfVBeFtzmS8ioVQ2B2QajmuXcq1z-m4f-HyBQ5x0IaDZJ6iOm-hWgF_lDJ4wbaoaCRLC0Gx2k43BQdmiVXgY";
    //     // bytes memory signature = hex"6ea3ce4092a57f8bfac7df2ad5f9371118324b0900309b70223c465cfc99073d1d9a23f0fe3cde6ea140aeaaa750f1a1c01933c4e3a684ed2adea3cabdd28fae00";
    //     // address userA = 0xC8643eF8f4232bf7E8bAc6Ac73a2fe9A28Cb575A;
    //     // string memory token = "etnTZCegRi6HHG9_vZRAlt:APA91bHBOVjplwQyVKUMxJAwBfwPbtIxJwtdSPHWKA6DQcU6DFTbk_71zAj3S3QWCKvAweK--0rqOnZuSFDALDyzRRuO22VFEFl_6v5_GvbqbvL1CtyoRz8";
    //     // bytes memory signature = hex"10603f653b11564e792a926b4c591daec5ce501ed3b2e7890309a1eda5582afb279317b3cb63b3f4fd773378ee05986e94adc08d0ea34b456bcdbdf33c46e27500";
    //     // address userA = 0xD5e5De64b7CDea2eca2ca27A2cC8cDf8821D5D99;
    //     // string memory token = "edxD12lnQsiibrus79bwit:APA91bFyao0Nuo9dT4rBV4W4c9F2drtqV6hS7FbKRSGDHE1SZ1X7kwzL__LFOMvotEMKt1h6KPQvgwAU27PXY8VENqU6-qoSPOiaPVzNmJ7EyAQgyVEf044";
    //     // bytes memory signature = hex"4981792e21b1ecb49ced46ca5eeb4535f2d716c983c604993393488a63c130d8246277cca5e352ccf102b22b1bca7d9b2f740ba572b0595d04a52b69bf4011e701";
    //     // address userA = 0xDF7876Dc76C913b265676F8D5504167CFd8c1Ca1;
    //     // string memory token = "dzgX0U3NQ9qJuUtjnf9ePH:APA91bFv1R7cGfU9aRzWjSfXahHuUR0eP_m4idB78vsKE1vRlSsAAoieOfIHbrcuyhVOrcJY-2CuSMwhJ59W_98qr-7lXrJuTfac40ZoYUpTawI3f_VnRVg";
    //     // bytes memory signature = hex"5e619647345a963d7e9546e95a5eab6082e797e2326a2fe12d33f89ad1b607732261e0a18c6f38d309dc4f8aea9f312bfcebc48b2168b58531e26c34c74eea5d01";
    //     // address userA = 0xf341E1B65bdFCa2bA2379560337A7927F3EB6F11;
    //     // string memory token = "etnTZCegRi6HHG9_vZRAlt:APA91bHBOVjplwQyVKUMxJAwBfwPbtIxJwtdSPHWKA6DQcU6DFTbk_71zAj3S3QWCKvAweK--0rqOnZuSFDALDyzRRuO22VFEFl_6v5_GvbqbvL1CtyoRz8";
    //     // bytes memory signature = hex"cdcb5c24778aa90908296b71e1c87e5d166d6d5bea31bf5b262d9b6c84802a102ea4342f7e76395b45917e53de007fbfbbc56aff078046e8db1d8ed1012afd2400";
    //     // address userA = 0x3d0285A43b52f0fEFA568428DD83DfE79Ec0A6E8;
    //     // string memory token = "frt_CeU-TI6AC9Y3ArJOj-:APA91bFYx2N6IsKZaK8duUMFq3WwGslzqzd39gCmjgnNlVqpF6TjD0pIcI8x-OyC3FyU66hxwPNxgn8uHMXxAPnfe6Fw2Zrp8p0IfKOVer9XLwA0uecfhUQ";
    //     // bytes memory signature = hex"8c99b1e9c61da3f31c365d3a6a45ac3174d02b035699676a23686a0ebb8da22d22a5b28abf9619bf4417293e5c648810b64dae9affbae13fe5f0dfb56bace03d01";
    //     address userA = 0x9a6e3fbA88B089dEB99815e0Ce4bA0Daf8Ac86EF;
    //     string memory token = "eKhbXzjfRIanbetCBT209F:APA91bG8vfrc2lUnTaD-VkXCL21IbD6iDUku0jf9CFu19jJgA6iIzc5ekm186vWvWDcrxpb4EbbIr8mPIGJtnW0_INJ9qUYR_NOOSKsF8Ml0FuprjSgWRhI";
    //     bytes memory signature = hex"98e89390f72fe4290e0ea11c0b43d3e86861c712122e61b301f1bf1103d49c162c3551db8537e38e7efa72bc000aa9684a219601714dc13e11ad79d94407f2c201";
    //     // address userA = 0xC8643eF8f4232bf7E8bAc6Ac73a2fe9A28Cb575A;
    //     // string memory token = "eKhbXzjfRIanbetCBT209F:APA91bG8vfrc2lUnTaD-VkXCL21IbD6iDUku0jf9CFu19jJgA6iIzc5ekm186vWvWDcrxpb4EbbIr8mPIGJtnW0_INJ9qUYR_NOOSKsF8Ml0FuprjSgWRhI";
    //     // bytes memory signature = hex"fdc60581c55541617e1f49f2511f1f4c32b0a3fbd60f1b725da7dd71cc8e331c4282d8571653f2193c8702b3e7816ed5c53aa12ef428c32f167b6443671e99d701";


    //     // Refer user2 by device1
    //     // vm.prank(user2);
    //     // bytesCodeCall = abi.encodeCall(
    //     //     miningUser.refUserViaQRCode,
    //     //     (userA, signature, token)
    //     // );
    //     // console.log("miningUser refUserViaQRCode: ");
    //     // console.logBytes(bytesCodeCall);
    //     // console.log(
    //     //     "-----------------------------------------------------------------------------"
    //     // );
    //     //processUserWithOTP
    //     // address parent1 = 0xA620249dc17f23887226506b3eB260f4802a7efc;
    //     // bytes32 otp1 = 0xd44b316023d9f87f06e62f767ec2e735d3e4f0af55a9034b952f72022aba053c;

    //     // bytesCodeCall = abi.encodeCall(
    //     //     miningUser.processUserWithOTP,
    //     //     (parent1,otp1)
    //     // );
    //     // console.log("miningUser processUserWithOTP: ");
    //     // console.logBytes(bytesCodeCall);
    //     // console.log(
    //     //     "-----------------------------------------------------------------------------"
    //     // );
    //     //activeUserByBe
    //     // address parent = 0x430E02Cc084C8EDd1B931AdB3545eb73074bA317;
    //     // bytes32 otp = 0x3132333435350000000000000000000000000000000000000000000000000000;
    //     // bytesCodeCall = abi.encodeCall(
    //     //     miningUser.activeUserByBe,
    //     //     (parent,otp)
    //     // );
    //     // console.log("miningUser activeUserByBe: ");
    //     // console.logBytes(bytesCodeCall);
    //     // console.log(
    //     //     "-----------------------------------------------------------------------------"
    //     // );
        //genCode
        bytes32 privateCode1 = 0x61cffafd93c74678852bbc7bf67ef35074ce175069d34a3fc142c96506e0a8c6; //day la private key cua vi df182ed5cf7d29f072c429edd8bfcf9c4151394b
        bytes32 hashedPrivateCode1 = keccak256(abi.encodePacked(privateCode1));
        console.log("hashedPrivateCode1:");
        console.logBytes32(hashedPrivateCode1);
        bytes memory publicKey1 = hex'0443ecc93c2949c17cbc9d525e910f91ffc13835786d6da1ddd49347bad123f6fe2fb89c7dcbba6ba85fb976956229fc4daa6ef3676a5df3a89cb5bbb3fe68b327';
        bytes32 hashedPublicKey1 = keccak256(abi.encodePacked(publicKey1));
        
        bytesCodeCall = abi.encodeCall(
            miningCode.genCode,
            (1, hashedPrivateCode1, hashedPublicKey1)
        );
        console.log("miningCode genCode: ");
        console.logBytes(bytesCodeCall);
        console.log(
            "-----------------------------------------------------------------------------"
        );
        //userLinkToDevice: user la nguoi goi ham, device ki signatureA
        uint256 timestamp = 1752033524;
        address deviceA = 0x3d9Cf842Bd57D60c760622Fb394BE918623f5a7a;
        //signature cua device ky voi message = device+time
        bytes memory signatureA = hex"d9d576b3c22f9ea72c0ffb831218aa51f26525a3a67e0573a7f7a86aa5f29f5869a33fa08177314bebaec9bae2e529f06aef1452537b411f9bea432b2fdd1a8a00";
        // Link user to device 
        // vm.prank(device1);
        address deviceB = 0xf5f4717635445460f0462fc80AC4fdDd3dfd3c47;
        // uint256 timestamp = 1750136030;
        // //user = 0xdf182ed5cf7d29f072c429edd8bfcf9c4151394b
        // address deviceA = 0x888Fc4277540e94A70d753bfb964d29AedbD9a89;
        // bytes memory signatureA = hex"7049f18074483dc7f33a1c083ebc5245cd98cea574659f2f135ae6d89b7baf87736e303ab6e614bcddea04c3174d07312823f878b66f436ac444741fb9e9eaf500";
        bytesCodeCall = abi.encodeCall(
            miningDevice.userLinkToDevice,
            (deviceA, signatureA, timestamp)
        );
        console.log("miningDevice userLinkToDevice: ");
        console.logBytes(bytesCodeCall);
        console.log(
            "-----------------------------------------------------------------------------"
        );
    //     //deviceLinkToUser: device la nguoi goi ham, user ki signatureB
    //     //device ki = 0x043E61E490EC76Aa636758D72A15201923593C72
    //     address user3 = 0xdf182ed5CF7D29F072C429edd8BFCf9C4151394B;
    //     bytes memory signatureB = hex"0d5cadc52cb525a2d560d6e3b6d81965e4fca74414e896818ff9e6593aecf8b51ab3d8e0ee45b84d219dbb4dcb770bd7802d481d63176629425faf91a1470a2d00";
    //     bytesCodeCall = abi.encodeCall(
    //         miningDevice.deviceLinkToUser,
    //         (user3, signatureB, timestamp)
    //     );
    //     console.log("miningDevice deviceLinkToUser: ");
    //     console.logBytes(bytesCodeCall);
    //     console.log(
    //         "-----------------------------------------------------------------------------"
    //     );
    //     //balanceOfAllDeviceAUser
    //     bytesCodeCall = abi.encodeCall(
    //         miningDevice.balanceOfAllDeviceAUser,
    //         (0xd132126049A2B52512d752B3559c2A13Fa59E312)
    //     );
    //     console.log("miningDevice balanceOfAllDeviceAUser: ");
    //     console.logBytes(bytesCodeCall);
    //     console.log(
    //         "-----------------------------------------------------------------------------"
    //     );


    }

    
    
    
    
    
    // function testDepositToWithdraw() public {
    //     // Link device to user first
    //     uint256 timestamp = block.timestamp;
    //     bytes32 message = keccak256(abi.encodePacked(device1, timestamp));
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(device1PrivateKey, message);
    //     bytes memory signature = abi.encodePacked(r, s, v);
        
    //     vm.prank(device1);
    //     miningDevice.deviceLinkToUser(device1, signature, timestamp);
        
    //     // Add balance to device
    //     vm.warp(block.timestamp + 24 * 60 * 60 + 1);
    //     uint256 deviceAmount = 10 ether;
    //     miningDevice.addBalance(device1, deviceAmount);
        
    //     // Approve USDT
    //     uint256 usdtAmount = 200 * 10**6; // 200 USDT
    //     vm.prank(device1);
    //     usdtToken.approve(address(miningUser), usdtAmount);
        
    //     // Deposit to withdraw
    //     uint256 resourceAmount = 1 ether; // 1 ETH / MTD
        
    //     // This would need more setup to test properly
    //     // Would need to ensure the contract can send ETH back to user
    // }
}