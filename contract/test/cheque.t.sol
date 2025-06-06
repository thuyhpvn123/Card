// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/secureCheque.sol";

contract SecureChequeTest is Test {
    SecureCheque public secureCheque;
    
    // Test addresses
    address public deployer;
    address public trustedSigner;
    address public userA;
    address public userB;
    address public userC;
    
    // Private keys for signing
    uint256 private deployerPrivKey;
    uint256 private trustedSignerPrivKey;
    uint256 private userAPrivKey;
    uint256 private userBPrivKey;
    uint256 private userCPrivKey;
    
    // Setup before running tests
    function setUp() public {
        // Initialize keys and addresses
        deployerPrivKey = 0x1;
        trustedSignerPrivKey = 0x2;
        // userAPrivKey = 0x3;
        // userBPrivKey = 0x4;
        // userCPrivKey = 0x5;
        
        deployer = vm.addr(deployerPrivKey);
        trustedSigner = vm.addr(trustedSignerPrivKey);
        userA = 0xA620249dc17f23887226506b3eB260f4802a7efc;
        userB = 0x043E61E490EC76Aa636758D72A15201923593C72;
        userC = 0xdf182ed5CF7D29F072C429edd8BFCf9C4151394B;
        
        // Provide ETH for test addresses
        vm.deal(deployer, 100 ether);
        vm.deal(userA, 100 ether);
        vm.deal(userB, 10 ether);
        vm.deal(userC, 10 ether);
        
        // Deploy contract as deployer
        vm.startPrank(deployer);
        secureCheque = new SecureCheque();
        secureCheque.setTrustedSigner(trustedSigner);
        vm.stopPrank();
    }
    
    // Test registering new cheques
    function testRegisterCheques() public {
        // Create mock pubKeyHashes
        bytes32[] memory pubKeyHashes = new bytes32[](2);
        pubKeyHashes[0] = keccak256(abi.encodePacked("pubKey1"));
        pubKeyHashes[1] = keccak256(abi.encodePacked("pubKey2"));
        
        uint256 amount = 10 ;
        uint256 totalAmount = amount * pubKeyHashes.length;
        
        vm.startPrank(userA);
        
        // Register a list of cheques with 1 ETH value each
        secureCheque.registerCheques{value: totalAmount}(pubKeyHashes, amount);
        
        // Check if the cheque was created correctly
        (address creator,,uint256 maxAmount,,SecureCheque.ChequeStatus status,) = secureCheque.cheques(pubKeyHashes[0]);
        assertEq(creator, userA, "Creator does not match");
        assertEq(maxAmount, amount, "Cheque amount does not match");
        assertEq(uint(status), uint(SecureCheque.ChequeStatus.Unused), "Cheque status does not match");
        
        vm.stopPrank();
    }
    
    // Test uploading offchain signatures
    function testUploadOffchainSignatures() public {
        // Register a cheque first
        bytes32[] memory pubKeyHashes = new bytes32[](1);
        pubKeyHashes[0] = keccak256(abi.encodePacked("pubKey1"));
        
        vm.startPrank(userA);
        secureCheque.registerCheques{value: 50}(pubKeyHashes,50);
        vm.stopPrank();
        
        // Create mock signatures
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked("signature1");
        
        // Test uploading signatures as trusted signer
        vm.startPrank(trustedSigner);
        secureCheque.uploadOffchainSignatures(pubKeyHashes, signatures);
        vm.stopPrank();
        
        // Check if signature was stored correctly
        (,,,,,bytes memory offchainSig) = secureCheque.cheques(pubKeyHashes[0]);
        assertEq(offchainSig, signatures[0], "Offchain signature does not match");
    }
    
    // Test requesting and executing cheque reclaim
    function testRequestAndExecuteReclaim() public {
        // 1. Create mock pubKeyHash and register a cheque
        bytes32[] memory pubKeyHashes = new bytes32[](1);
        pubKeyHashes[0] = keccak256(abi.encodePacked(userB));
        
        vm.startPrank(userB);
        secureCheque.registerCheques{value: 60}(pubKeyHashes, 60);
        
        // 2. Request reclaim
        secureCheque.requestReclaim(pubKeyHashes);
        
        // Check if reclaim time was set
        (,,,uint256 reclaimTime,,) = secureCheque.cheques(pubKeyHashes[0]);
        assertTrue(reclaimTime > 0, "Reclaim time was not set");
        
        // 3. Create signature for reclaim
        // bytes32 reclaimHash = keccak256(abi.encodePacked(pubKeyHashes[0], "reclaim"));
        bytes memory signature = hex"2a7c7972ef14f1078dcb83fd94391f31f0b89634b8cd089f03f88591a6107f096f6e7995c10e25ad542900c258f0d21919e7f631d453675a41d29baa263db20e01";
       
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;
        
        // 4. Wait for reclaim delay (72 hours)
        vm.warp(block.timestamp + 72 hours + 1);
        
        // 5. Execute reclaim
        uint256 balanceBefore = secureCheque.balances(userB);
        
        secureCheque.executeReclaim(pubKeyHashes, signatures);
        
        // Check if cheque was marked as reclaimed
        (,,,,SecureCheque.ChequeStatus status,)  = secureCheque.cheques(pubKeyHashes[0]);
        assertEq(uint(status), uint(SecureCheque.ChequeStatus.Reclaimed), "Cheque was not marked as reclaimed");
        
        // Check if funds were added to balance
        uint256 balanceAfter = secureCheque.balances(userB);
        assertEq(balanceAfter - balanceBefore, 60, "Refund amount is incorrect");
        
        vm.stopPrank();
    }
    
    // Test posting intent and claiming a cheque with no transfer steps
    function testPostIntentAndClaimCheque() public {
        // 1. Create and register a cheque
        vm.startPrank(userA);
        bytes32[] memory pubKeyHashes = new bytes32[](1);
        pubKeyHashes[0] = keccak256(abi.encodePacked(userB));
        secureCheque.registerCheques{value: 70}(pubKeyHashes, 70);
        
        vm.stopPrank();
        
        // 2. UserB posts intent to claim funds
        vm.startPrank(userB);
        
        uint256 claimAmount = 30;
        bytes memory sigInitial = hex"cb60c81cfd8f1c6b4834fb55a45fd2a4ed087993f267e379ce9ea02b19f1d7220d9627350db76f82733c2213ec15600b455bbb4e8e6ba1d74f6cd2f76ad2235201";
      
        // Register intent
        bytes32 initialSigHash = keccak256(sigInitial);
        secureCheque.postClaimIntent(initialSigHash);
        
        // 3. Wait for front-run window
        vm.warp(block.timestamp + 5);
        
        // 4. Claim the cheque
        SecureCheque.TransferStep[] memory emptySteps = new SecureCheque.TransferStep[](0);
        secureCheque.claimCheque(emptySteps, claimAmount, sigInitial);
        
        // Check if balance was updated
        uint256 balance = secureCheque.balances(userB);
        assertEq(balance, claimAmount, "Balance was not updated correctly");
        
        // Check if remaining amount was refunded to cheque creator
        uint256 creatorBalance = secureCheque.balances(userA);
        assertEq(creatorBalance, 40, "Remaining amount was not refunded to creator");
        
        vm.stopPrank();
    }
    
    // Test claiming a cheque with transfer steps
    function testClaimChequeWithTransferSteps() public {
        // 1. Create and register a cheque with userA
        vm.startPrank(userA);
        
        bytes32[] memory pubKeyHashes = new bytes32[](1);
        pubKeyHashes[0] = keccak256(abi.encodePacked(userB));
        secureCheque.registerCheques{value: 65}(pubKeyHashes, 65);
        
        vm.stopPrank();
        
        // 2. Create transfer chain:
        // userA (65)-> userB (35) -> userC (25)
        
        // Step 1: userA transfers to userB: keccak256(abi.encodePacked(address(0), userB, uint256(10000000))); -userB ky
        bytes memory sigStep1 = hex"4b5f291c1224f33eb0b7ee37533cccd2da8d6239d60f092ca24400698770f9bb7f11798b77f0297704a0d72959d7249957b7c95205f4de0b5e35235f38fbbeb001";
        // Step 2: userB transfers to userC 25: keccak256(abi.encodePacked(userB, userC, uint256(25)))-userB ky lun
         bytes memory sigStep2 = hex"6215d20d323853346ce346385909a3dbdb03e5ad3de13b5fb17933124c8da2064b9b4a9180380740b2a7d317743f7a431ee25dfc9589980d0059a0d8b993cb5601";
       
        // 3. Create array of transfer steps
        vm.startPrank(userC);
        
        SecureCheque.TransferStep[] memory transferSteps = new SecureCheque.TransferStep[](2);
        
        // Step 1: userA -> userB
        transferSteps[0] = SecureCheque.TransferStep({
            to: userB,
            nextAmount: 35,
            signature: sigStep1
        });
        
        // Step 2: userB -> userC
        transferSteps[1] = SecureCheque.TransferStep({
            to: userC,
            nextAmount: 25,
            signature: sigStep2
        });
        
        // 4. Claim funds from transfer chain
        secureCheque.claimCheque(transferSteps, 35, sigStep1);
        
        // 5. Check balances
        // UserA should receive 30 ETH (65-35)
        // UserB should receive 10 ETH (35-25)
        // UserC should receive 25 ETH
        
        uint256 balanceA = secureCheque.balances(userA);
        uint256 balanceB = secureCheque.balances(userB);
        uint256 balanceC = secureCheque.balances(userC);
        
        assertEq(balanceA, 30, "UserA did not receive correct remaining amount");
        assertEq(balanceB, 10, "UserB did not receive correct remaining amount");
        assertEq(balanceC, 25, "UserC did not receive correct final amount");
        
        vm.stopPrank();
    }
    
    // Test redeeming funds from balance
    function testRedeem() public {
        // 1. First set up a balance for userA
        vm.startPrank(userB);
        
        // Create and register a cheque
        bytes32[] memory pubKeyHashes = new bytes32[](1);
        pubKeyHashes[0] = keccak256(abi.encodePacked(userB));
        secureCheque.registerCheques{value: 1 ether}(pubKeyHashes, 1 ether);
        
        // Request reclaim
        secureCheque.requestReclaim(pubKeyHashes);
        
        // Create signature for reclaim
        // bytes32 reclaimHash = keccak256(abi.encodePacked(pubKeyHashes[0], "reclaim"));
        // bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", reclaimHash));
        
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivKey, ethSignedMessageHash);
        // bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory signature = hex"2a7c7972ef14f1078dcb83fd94391f31f0b89634b8cd089f03f88591a6107f096f6e7995c10e25ad542900c258f0d21919e7f631d453675a41d29baa263db20e01";
       
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;
        
        // Wait for reclaim delay
        vm.warp(block.timestamp + 72 hours + 1);
        
        // Execute reclaim
        secureCheque.executeReclaim(pubKeyHashes, signatures);
        
        // 2. Check balance before redemption
        uint256 balanceBefore = secureCheque.balances(userB);
        assertEq(balanceBefore, 1 ether, "Initial balance is incorrect");
        
        uint256 ethBalanceBefore = address(userB).balance;
        
        // 3. Redeem funds
        secureCheque.redeem(0.5 ether);
        
        // 4. Check balance after redemption
        uint256 balanceAfter = secureCheque.balances(userB);
        uint256 ethBalanceAfter = address(userB).balance;
        assertEq(balanceAfter, 0.5 ether, "Final balance is incorrect");
        assertEq(ethBalanceAfter - ethBalanceBefore, 0.5 ether, "ETH was not transferred correctly");
        
        vm.stopPrank();
    }
    
    // Test failure cases for registerCheques
    function test_Revert_When_RegisterChequesWithIncorrectAmount() public {
        bytes32[] memory pubKeyHashes = new bytes32[](2);
        pubKeyHashes[0] = keccak256(abi.encodePacked("pubKey1"));
        pubKeyHashes[1] = keccak256(abi.encodePacked("pubKey2"));
        
        uint256 amount = 1 ether;
        
        vm.startPrank(userA);
        // Send incorrect amount (less than required)
         vm.expectRevert("Incorrect total amount");
        secureCheque.registerCheques{value: amount}(pubKeyHashes, amount);
        vm.stopPrank();
    }
    
    // Test failure case for claiming cheque with invalid signature
    function test_Revert_When_ClaimChequeWithInvalidSignature() public {
        // 1. Register a cheque
        bytes32[] memory pubKeyHashes = new bytes32[](1);
        pubKeyHashes[0] = keccak256(abi.encodePacked(userA));
        
        vm.startPrank(userA);
        secureCheque.registerCheques{value: 1 ether}(pubKeyHashes, 1 ether);
        vm.stopPrank();
        
        // 2. Try to claim with invalid signature
        vm.startPrank(userB);
        
        uint256 claimAmount = 0.5 ether;
        // Create an invalid signature (signed by wrong key)
        bytes memory invalidSig = hex"824b259a8e4880cc031f4a1a364f2d80506a20983a1ce01355abb8daef0cc3871694cdf830e2b0b7214654d3fb28890a44b7aeaf2718a5639c6f4143253f7e2500";
        
        // Register intent
        bytes32 initialSigHash = keccak256(invalidSig);
        secureCheque.postClaimIntent(initialSigHash);
        
        // Wait for front-run window
        vm.warp(block.timestamp + 5);
        
        // Try to claim with invalid signature (should fail)
        SecureCheque.TransferStep[] memory emptySteps = new SecureCheque.TransferStep[](0);
        vm.expectRevert("Amount exceeds cheque max");
        secureCheque.claimCheque(emptySteps, claimAmount, invalidSig);
        
        vm.stopPrank();
    }
}