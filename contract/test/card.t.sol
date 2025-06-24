// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/card.sol";
import "../src/utxo.sol";
import "../src/usdt.sol";
import "../src/masterpool.sol";
contract CardTokenManagerTest is Test {
    CardTokenManager public cardTokenManager;
    address public admin;
    address public beProcessor;
    address public user1;
    address public user2;
    address public merchant1;
    address public merchant2;
    bytes32 public constant TEST_REQUEST_ID = keccak256("TEST_REQUEST_ID");
    bytes32 public constant TEST_TOKEN_ID = keccak256("TEST_TOKEN_ID");
    bytes32 public constant TEST_CARD_HASH = keccak256("TEST_CARD_HASH");
    bytes public constant ENCRYPTED_CARD_DATA = abi.encodePacked("ENCRYPTED_CARD_DATA");
    bytes public constant TEST_BACKEND_PUBKEY = abi.encodePacked("TEST_BACKEND_PUBKEY");
    
    event TokenRequest(address  user, bytes encryptedCardData, bytes32 requestId);
    event TokenIssued(address indexed user, bytes32 indexed tokenId, string region, bytes32 requestId, bytes32 cardHash);
    event TokenFailed(address indexed user, bytes32 requestId, string reason);
    event ChargeRequest(address  user, bytes32 tokenId, address merchant, uint256 amount);
    event ChargeRejected(address indexed user, bytes32 tokenId, string reason);
    UltraUTXO private ultraUTXO;
    USDT private USDT_ERC;
    MasterPool public MASTERPOOL;
    address recipient1 = address(0x3);
    address recipient2 = address(0x4);


    constructor() {
        admin = address(0x11);
        beProcessor = makeAddr("beProcessor");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        merchant1 = makeAddr("merchant1");
        merchant2 = makeAddr("merchant2");
        vm.startPrank(admin);
        // Deploy contract with backend processor
        cardTokenManager = new CardTokenManager(beProcessor);
        ultraUTXO = new UltraUTXO();
        USDT_ERC = new USDT();
        MASTERPOOL = new MasterPool(address(USDT_ERC),address(ultraUTXO));
        ultraUTXO.setMasterPool(address(MASTERPOOL));

        // Set up global rules
        cardTokenManager.setGlobalRule(
            5,  // maxPerMinute
            20, // maxPerHour
            50, // maxPerDay
            100, // maxPerWeek
            1000 // maxTotal
        );
        
        // Setup merchant rules
        string[] memory allowedRegions = new string[](2);
        allowedRegions[0] = "US";
        allowedRegions[1] = "VN";
              
        vm.deal(merchant1, 1 ether);
        cardTokenManager.setMerchantRule(
            allowedRegions,
            3, // maxPerMinute
            10, // maxPerHour
            30, // maxPerDay
            60,  // maxPerWeek
            merchant1
        );
       
        
        // Set backend public key
        
        cardTokenManager.setBackendPubKey(TEST_BACKEND_PUBKEY);
        cardTokenManager.setUtxoUltra(address(ultraUTXO));
        cardTokenManager.setToken(address(USDT_ERC));
        cardTokenManager.setAdmin(admin,true);
        ultraUTXO.setAdmin(address(cardTokenManager),true);

        vm.stopPrank();
    }
    
    // ===== ACCESS CONTROL TESTS =====
    
    // function testOnlyAdminCanSetLock() public {
    //     vm.prank(admin);
    //     cardTokenManager.setLock(true);
    //     assertTrue(cardTokenManager.isLocked());
        
    //     vm.prank(user1);
    //     vm.expectRevert("Only admin allowed");
    //     cardTokenManager.setLock(false);
    // }
    
    // function testOnlyAdminCanSetBackendPubKey() public {
    //     bytes memory newPubKey = abi.encodePacked("NEW_PUBKEY");
        
    //     vm.prank(admin);
    //     cardTokenManager.setBackendPubKey(newPubKey);
        
    //     vm.prank(user1);
    //     vm.expectRevert("Only admin allowed");
    //     cardTokenManager.setBackendPubKey(newPubKey);
    // }
    
    // function testOnlyAdminCanSetGlobalRule() public {
    //     vm.prank(admin);
    //     cardTokenManager.setGlobalRule(10, 100, 200, 500, 2000);
        
    //     vm.prank(user1);
    //     vm.expectRevert("Only admin allowed");
    //     cardTokenManager.setGlobalRule(10, 100, 200, 500, 2000);
    // }
    
    // function testOnlyBEProcessorCanSubmitToken() public {
    //     // First setup a pending request
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(user2);
    //     vm.expectRevert("Only backend processor allowed");
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
    // }
    
    // function testOnlyBEProcessorCanRejectToken() public {
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(user2);
    //     vm.expectRevert("Only backend processor allowed");
    //     cardTokenManager.rejectToken(user1, TEST_REQUEST_ID, "Test rejection");
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.rejectToken(user1, TEST_REQUEST_ID, "Test rejection");
    // }
    
    // function testOnlyBEProcessorCanSetTokenActive() public {
    //     // First create a token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     vm.prank(user2);
    //     vm.expectRevert("Only backend processor allowed");
    //     cardTokenManager.setTokenActive(TEST_TOKEN_ID, false);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.setTokenActive(TEST_TOKEN_ID, false);
    // }
    
    // function testOnlyBEProcessorCanSetCardLocked() public {
    //     vm.prank(user1);
    //     vm.expectRevert("Only backend processor allowed");
    //     cardTokenManager.setCardLocked(TEST_CARD_HASH, true);//true laf mo khoa, false la khoa
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.setCardLocked(TEST_CARD_HASH, true);
    //     assertTrue(cardTokenManager.lockedCards(TEST_CARD_HASH));
    // }
    
    // // ===== TOKEN REQUEST AND ISSUANCE TESTS =====
    
    // function testRequestToken() public {
    //     vm.prank(user1);
    //     vm.expectEmit(true, false, false, true);
    //     emit TokenRequest(user1, ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     assertTrue(cardTokenManager.userPending(user1));
    // }
    
    // function testCannotRequestTokenTwice() public {
    //     vm.startPrank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.expectRevert("User has a pending request");
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, bytes32(uint256(2)));
    //     vm.stopPrank();
    // }
    
    // function testSubmitToken() public {
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     vm.expectEmit(true, true, false, true);
    //     emit TokenIssued(user1, TEST_TOKEN_ID, "US", TEST_REQUEST_ID, TEST_CARD_HASH);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Verify token was created
    //     (address owner, string memory region, uint256 issuedAt, bool isActive, uint256 totalUsage, bytes32 cardHash) = 
    //         cardTokenManager.tokens(TEST_TOKEN_ID);
        
    //     assertEq(owner, user1);
    //     assertEq(region, "US");
    //     assertEq(isActive, true);
    //     assertEq(totalUsage, 0);
    //     assertEq(cardHash, TEST_CARD_HASH);
        
    //     // Verify user token was added
    //     bytes32[] memory userTokens = cardTokenManager.getUserTokens(user1);
    //     assertEq(userTokens.length, 1);
    //     assertEq(userTokens[0], TEST_TOKEN_ID);
        
    //     // Verify pending flag was cleared
    //     assertEq(cardTokenManager.userPending(user1), false);
    // }
    
    // function testRejectToken() public {
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     vm.expectEmit(true, false, false, true);
    //     emit TokenFailed(user1, TEST_REQUEST_ID, "Test rejection reason");
    //     cardTokenManager.rejectToken(user1, TEST_REQUEST_ID, "Test rejection reason");
        
    //     // Verify pending flag was cleared
    //     assertEq(cardTokenManager.userPending(user1), false);
    // }
    
    // function testCannotSubmitSameTokenIdTwice() public {
    //     // Create first token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Try to create another token with same ID
    //     vm.prank(user2);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, bytes32(uint256(2)));
        
    //     vm.prank(beProcessor);
    //     vm.expectRevert("Token already exists");
    //     cardTokenManager.submitToken(
    //         user2,
    //         TEST_TOKEN_ID,
    //         "VN",
    //         bytes32(uint256(2)),
    //         bytes32(uint256(3))
    //     );
    // }
    
    // // ===== CHARGE TESTS =====
    
    function testCharge() public {
        // 1.user1 gui requestToken
        vm.prank(user1);
        cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        //2.Backend goi submitToken
        vm.prank(beProcessor);
        cardTokenManager.submitToken(
            user1,
            TEST_TOKEN_ID,
            "US",
            TEST_REQUEST_ID,
            TEST_CARD_HASH
        );

        (address owner,,,,,) = cardTokenManager.tokens(TEST_TOKEN_ID);
        console.log("owner:",owner);
        console.log("user1:",user1);
        bytes32 token = cardTokenManager.userTokens(user1,0);
        console.logBytes32(token);
        vm.prank(user1);
        bytes32 tokenId = cardTokenManager.getTokenIdByRequestId(TEST_REQUEST_ID);
        console.logBytes32(tokenId);
        //3.user1 topup cho merchant goi charge
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        uint amountCharge = 100;
        // emit ChargeRequest(user1, TEST_TOKEN_ID, merchant1, amountCharge);
        // cardTokenManager.chargeMerchant(TEST_TOKEN_ID, merchant1, amountCharge);
        //case topup
        emit ChargeRequest(user1, TEST_TOKEN_ID, user1, amountCharge);
        cardTokenManager.charge(TEST_TOKEN_ID, user1, amountCharge);

        // Verify usage counts
        (,,,, uint256 totalUsage,) = cardTokenManager.tokens(TEST_TOKEN_ID);
        assertEq(totalUsage, 1);
        
        uint256 minute = block.timestamp / 60;
        uint256 hour = block.timestamp / 3600;
        uint256 day = block.timestamp / 86400;
        uint256 week = block.timestamp / 604800;
        
        assertEq(cardTokenManager.tokenUsagePerMinute(TEST_TOKEN_ID, minute), 1);
        assertEq(cardTokenManager.tokenUsagePerHour(TEST_TOKEN_ID, hour), 1);
        assertEq(cardTokenManager.tokenUsagePerDay(TEST_TOKEN_ID, day), 1);
        assertEq(cardTokenManager.tokenUsagePerWeek(TEST_TOKEN_ID, week), 1);
        
        assertEq(cardTokenManager.cardUsagePerMinute(TEST_CARD_HASH, minute), 1);
        assertEq(cardTokenManager.cardUsagePerHour(TEST_CARD_HASH, hour), 1);
        assertEq(cardTokenManager.cardUsagePerDay(TEST_CARD_HASH, day), 1);
        assertEq(cardTokenManager.cardUsagePerWeek(TEST_CARD_HASH, week), 1);

        //4.admin goi mint utxo
        vm.prank(admin);
        string memory transactionID = "transactionID";
        (address poolAddress,bytes32 parentHash) = cardTokenManager.MintUTXO(amountCharge,merchant1,transactionID);
        // Check that the UTXO has been created correctly
        uint256 parentValue = amountCharge;
        // bytes32 parentHash = keccak256(abi.encodePacked(merchant1, parentValue, block.timestamp, block.number));
        (uint256 utxoValue, bool spent, address pool, address utxoOwner, address tokenKq) = ultraUTXO.childUTXOs(parentHash);
        assertEq(utxoValue, parentValue,"parent value should be equal");
        assertFalse(spent);
        assertEq(pool, poolAddress);
        assertEq(utxoOwner, merchant1);
        assertEq(tokenKq, address(USDT_ERC));
        //5.merchant1 goi createParentUTXO de bat trang thai active moi co the redeeam sau 60 days
        vm.startPrank(merchant1);
        bytes32 previousParentHashRoot = PoolUTXO(pool).previousParentHashRoot();
        // bytes32 previousParentHash0 = parentHash;
        uint256[] memory childValues = new uint256[](2);
        childValues[0] = 30;
        childValues[1] = 70;

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
         // Create a previous parent UTXO to satisfy the requirement
        bytes32 newParentHash = keccak256(abi.encodePacked(merchant1, parentValue, block.timestamp, block.number));
        bytes32 newhash =  PoolUTXO(pool).createParentUTXO(previousParentHashRoot, parentValue, childValues, recipients,address(USDT_ERC));
        (,,bytes32 previousParentHash,,,) = PoolUTXO(pool).parentUTXOs(newParentHash);       
        assertEq(newhash, newParentHash, "hash should be same");
        // Assert
        (uint256 value, address merchant, bytes32 prevHash) = PoolUTXO(pool).getParentUTXO(newParentHash);
        assertEq(value, 0, "Parent UTXO value mismatch");
        assertEq(merchant, merchant1, "Parent UTXO owner mismatch");
        assertEq(prevHash, previousParentHashRoot, "Previous parent hash mismatch");
        (uint256 storedValue1, PoolUTXO.ChildStatus spent1) = PoolUTXO(pool).getChildUTXO(newParentHash, recipient1);
        (uint256 storedValue2, PoolUTXO.ChildStatus spent2) = PoolUTXO(pool).getChildUTXO(newParentHash, recipient2);
        assertEq(storedValue1, 30, "Child 1 value should be set correctly");
        assertEq(storedValue2, 70, "Child 2 value should be set correctly");
        assertEq(uint8(spent1), uint8(PoolUTXO.ChildStatus.Unspent), "Child 1 should be unspent");
        assertEq(uint8(spent2), uint8(PoolUTXO.ChildStatus.Unspent), "Child 2 should be unspent");
        vm.stopPrank();
        // getPoolInfo(transactionID);

    }
    function getPoolInfo(string memory transactionID)public {
        // CardTokenManager.PoolInfo memory poolInfo = cardTokenManager.getPoolInfo(transactionID);
        // console.log("poolInfo.pool:",poolInfo.pool);
        //  console.log("poolInfo.ownerPool:",poolInfo.ownerPool);
        //  console.log("poolInfo.parentValue:",poolInfo.parentValue);

    }
    
    // function testChargeFailsWithInactiveToken() public {
    //     // Setup token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Deactivate token
    //     vm.prank(beProcessor);
    //     cardTokenManager.setTokenActive(TEST_TOKEN_ID, false);
        
    //     // Try to charge
    //     vm.prank(user1);
    //     vm.expectRevert("Token inactive");
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 100);
    // }
    
    // function testChargeFailsWhenContractLocked() public {
    //     // Setup token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Lock contract
    //     vm.prank(admin);
    //     cardTokenManager.setLock(true);
        
    //     // Try to charge
    //     vm.prank(user1);
    //     vm.expectRevert("Contract is locked");
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 100);
    // }
    
    // function testChargeFailsWithLockedCard() public {
    //     // Setup token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Lock card
    //     vm.prank(beProcessor);
    //     cardTokenManager.setCardLocked(TEST_CARD_HASH, true);
        
    //     // Try to charge - should emit rejection event
    //     vm.prank(user1);
    //     vm.expectEmit(true, true, false, true);
    //     emit ChargeRejected(user1, TEST_TOKEN_ID, "Card is locked");
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 100);
    // }
    
    // function testChargeFailsWithNonAllowedRegion() public {
    //     // Setup token in non-allowed region
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "CA", // Canada - not in allowed regions
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Try to charge - should emit rejection event
    //     vm.prank(user1);
    //     vm.expectEmit(true, true, false, true);
    //     emit ChargeRejected(user1, TEST_TOKEN_ID, "Region not allowed");
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 100);
    // }
    
    // function testChargeFailsWithZeroAmount() public {
    //     // Setup token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Try to charge with zero amount
    //     vm.prank(user1);
    //     vm.expectRevert("Amount must be greater than 0");
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 0);
    // }
    
    // function testChargeFailsWithInvalidMerchant() public {
    //     // Setup token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Try to charge with invalid merchant
    //     vm.prank(user1);
    //     vm.expectRevert("token empty");
    //     cardTokenManager.charge(TEST_TOKEN_ID, address(0), 100);
    // }
    
    // function testChargeFailsWithGlobalRateLimits() public {
    //     // Setup token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Set a very restrictive global rule for testing
    //     vm.prank(admin);
    //     cardTokenManager.setGlobalRule(1, 20, 50, 100, 1000);
        
    //     // First charge should succeed
    //     vm.prank(user1);
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 100);
        
    //     // Second charge should fail due to minute limit
    //     vm.prank(user1);
    //     vm.expectRevert("SM: token minute limit");
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 100);
    // }
    
    // function testChargeFailsWithMerchantRateLimits() public {
    //     // Setup token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Set global rule to be permissive
    //     vm.prank(admin);
    //     cardTokenManager.setGlobalRule(10, 20, 50, 100, 1000);
        
    //     // Set merchant rule to be restrictive
    //     string[] memory allowedRegions = new string[](2);
    //     allowedRegions[0] = "US";
    //     allowedRegions[1] = "VN";
        
    //     vm.startPrank(admin);
    //     cardTokenManager.setMerchantRule(
    //         allowedRegions,
    //         1, // maxPerMinute
    //         10, // maxPerHour
    //         30, // maxPerDay
    //         60,  // maxPerWeek
    //         merchant1
    //     );
    //     vm.stopPrank();
        
    //     // First charge should succeed
    //     vm.prank(user1);
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 100);
        
    //     // Second charge should emit rejection event
    //     vm.prank(user1);
    //     vm.expectEmit(true, true, false, true);
    //     emit ChargeRejected(user1, TEST_TOKEN_ID, "Max per minute exceeded");
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 100);
    // }
    
    // ===== CLEANUP TESTS =====
    
    function testCleanUsage() public {
        uint currentTime = 1744281626;
        vm.warp(currentTime);
        // Setup token and make some charges
        vm.prank(user1);
        cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
        vm.prank(beProcessor);
        cardTokenManager.submitToken(
            user1,
            TEST_TOKEN_ID,
            "US",
            TEST_REQUEST_ID,
            TEST_CARD_HASH
        );
        
        // Make a few charges
        vm.startPrank(user1);
        cardTokenManager.charge(TEST_TOKEN_ID, user1, 100);
        vm.warp(currentTime + 61); // Move forward 1 minute
        cardTokenManager.charge(TEST_TOKEN_ID, user1, 100);
        vm.warp(currentTime + 61 + 61); // Move forward 1 minute
        cardTokenManager.charge(TEST_TOKEN_ID, user1, 100);
        vm.stopPrank();
        console.log("currentMinute:",block.timestamp);
        // Get current minute
        uint256 currentMinute = block.timestamp / 60;
        console.log("currentMinute:",currentMinute);
        uint256 pastMinute1 = (block.timestamp - 61) / 60;
        console.log("pastMinute1:",pastMinute1);
        uint256 pastMinute2 = (block.timestamp - 122) / 60;
        console.log("pastMinute2:",pastMinute2);
        // Verify counts before cleanup
        assertEq(cardTokenManager.tokenUsagePerMinute(TEST_TOKEN_ID, currentMinute), 1);
        assertEq(cardTokenManager.tokenUsagePerMinute(TEST_TOKEN_ID, pastMinute1), 1);
        assertEq(cardTokenManager.tokenUsagePerMinute(TEST_TOKEN_ID, pastMinute2), 1);
        
        // Lock contract for cleanup
        vm.prank(admin);
        cardTokenManager.setLock(true);
        
        // Perform cleanup
        vm.prank(admin);
         console.log("pastMinute2:",pastMinute2);
        cardTokenManager.cleanUsage(block.timestamp - 90); // Clean before the last 90 seconds
        
        // Verify counts after cleanup - oldest charge should be cleaned
        assertEq(cardTokenManager.tokenUsagePerMinute(TEST_TOKEN_ID, currentMinute), 1);
        assertEq(cardTokenManager.tokenUsagePerMinute(TEST_TOKEN_ID, pastMinute1), 1);
        assertEq(cardTokenManager.tokenUsagePerMinute(TEST_TOKEN_ID, pastMinute2), 0); // Should be cleaned
    }
    
    // function testFailCleanUsageWithoutLock() public {
    //     // Setup token
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     // Make a charge
    //     vm.prank(user1);
    //     cardTokenManager.charge(TEST_TOKEN_ID, merchant1, 100);
        
    //     // Try to clean without locking
    //     vm.prank(admin);
    //     cardTokenManager.cleanUsage(block.timestamp - 90); // Should revert
    // }
    
    // // ===== OTHER UTILITY FUNCTION TESTS =====
    
    // function testGetBackendPubKey() public {
    //     bytes memory pubKey = cardTokenManager.getBackendPubKey();
    //     assertEq(pubKey, TEST_BACKEND_PUBKEY);
    // }
    
    // function testGetUserTokens() public {
    //     // Setup two tokens for the same user
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, TEST_REQUEST_ID);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         TEST_TOKEN_ID,
    //         "US",
    //         TEST_REQUEST_ID,
    //         TEST_CARD_HASH
    //     );
        
    //     bytes32 requestId2 = bytes32(uint256(2));
    //     bytes32 tokenId2 = bytes32(uint256(3)); 
    //     bytes32 cardHash2 = bytes32(uint256(4));
        
    //     vm.prank(user1);
    //     cardTokenManager.requestToken(ENCRYPTED_CARD_DATA, requestId2);
        
    //     vm.prank(beProcessor);
    //     cardTokenManager.submitToken(
    //         user1,
    //         tokenId2,
    //         "VN",
    //         requestId2,
    //         cardHash2
    //     );
        
    //     // Get user tokens
    //     bytes32[] memory userTokens = cardTokenManager.getUserTokens(user1);
    //     assertEq(userTokens.length, 2);
    //     assertEq(userTokens[0], TEST_TOKEN_ID);
    //     assertEq(userTokens[1], tokenId2);
    // }
    // function GetByteCode()public{
    //     //
    //     bytes memory backendPubKey = abi.encodePacked("04274132e9021a5d6103260ad397cd82c5f5bc16c8d627f8789a3a7258a7fe735ac19bac9055dd91b76076bcd0fc3593dfd51d9697ea8cfdc756e84039c19bfe5f");
    //     bytes memory bytesCodeCall = abi.encodeCall(
    //         cardTokenManager.setBackendPubKey,
    //         (backendPubKey)
    //     );
    //     console.log("ECOM_PROcardTokenManagerDUCT setBackendPubKey: ");
    //     console.logBytes(bytesCodeCall);
    //     console.log(
    //         "-----------------------------------------------------------------------------"
    //     );

    // }
}