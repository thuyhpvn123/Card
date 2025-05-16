// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "../src/utxo.sol"; // Adjust path if necessary
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// // Mock ERC20 token for testing
// contract MockToken is ERC20 {
//     constructor(uint256 initialSupply) ERC20("MockToken", "MTK") {
//         _mint(msg.sender, initialSupply);
//     }
// }

// contract UltraUTXOTest is Test {
//     UltraUTXO ultraUTXO;
//     MockToken mockToken;
//     address owner = address(0x1);
//     address admin = address(0x2);
//     address user1 = address(0x3);
//     address user2 = address(0x4);
//     address user3 = address(0x5);
//     address[] recipients;
//     uint256[] values;
    
//     function setUp() public {
//         // Deploy contracts
//         vm.startPrank(owner);
//         ultraUTXO = new UltraUTXO();
//         mockToken = new MockToken(1000000 * 10**18);
        
//         // Set admin permissions
//         ultraUTXO.setAdmin(admin, true);
        
//         // Transfer tokens to the admin for later use
//         mockToken.transfer(admin, 500000 * 10**18);
//         vm.stopPrank();
//     }
    
//     function testTransferChildUTXO() public {
//         // 1. Mint a new UTXO
//         vm.startPrank(admin);
//         bytes32 hash = keccak256(abi.encodePacked("test", block.timestamp));
//         uint256 initialValue = 1000;
//         address pool = ultraUTXO.mint(
//             hash,
//             initialValue,
//             user1, // owner of the pool
//             address(mockToken)
//         );
//         vm.stopPrank();
        
//         // 2. Transfer mock tokens to the pool for distribution
//         vm.startPrank(admin);
//         mockToken.transfer(pool, initialValue);
//         vm.stopPrank();
        
//         // Create a parent UTXO and child UTXOs
//         vm.startPrank(user1);
//         PoolUTXO poolUTXO = PoolUTXO(pool);
        
//         // Create parent UTXO
//         recipients = new address[](2);
//         values = new uint256[](2);
        
//         recipients[0] = user2;
//         recipients[1] = user3;
//         values[0] = 400;
//         values[1] = 600;
        
//         bytes32 parentHash = poolUTXO.createParentUTXO(
//             hash, // previousParentHash
//             initialValue,
//             values,
//             recipients,
//             address(mockToken)
//         );
//         vm.stopPrank();
        
//         // Verify child UTXOs were created
//         (uint256 user2Value, PoolUTXO.ChildStatus user2Status) = poolUTXO.getChildUTXO(parentHash, user2);
//         assertEq(user2Value, 400);
//         assertEq(uint(user2Status), uint(PoolUTXO.ChildStatus.Unspent));
        
//         (uint256 user3Value, PoolUTXO.ChildStatus user3Status) = poolUTXO.getChildUTXO(parentHash, user3);
//         assertEq(user3Value, 600);
//         assertEq(uint(user3Status), uint(PoolUTXO.ChildStatus.Unspent));
        
//         // 3. User2 transfers their UTXO to other recipients
//         vm.startPrank(user2);
        
//         // Prepare recipients for transfer
//         address[] memory newRecipients = new address[](2);
//         uint256[] memory newValues = new uint256[](2);
        
//         newRecipients[0] = address(0x6);
//         newRecipients[1] = address(0x7);
//         newValues[0] = 150;
//         newValues[1] = 250;
        
//         // Transfer child UTXO
//         bytes32 newParentHash = poolUTXO.transferChildUTXO(
//             parentHash,
//             newValues,
//             newRecipients,
//             address(mockToken)
//         );
//         vm.stopPrank();
        
//         // 4. Verify user2's UTXO is spent
//         (uint256 user2NewValue, PoolUTXO.ChildStatus user2NewStatus) = poolUTXO.getChildUTXO(parentHash, user2);
//         assertEq(user2NewValue, 400); // Value shouldn't change
//         assertEq(uint(user2NewStatus), uint(PoolUTXO.ChildStatus.Spent)); // Status should be spent
        
//         // 5. Verify new UTXOs were created for the recipients
//         (uint256 recipient1Value, PoolUTXO.ChildStatus recipient1Status) = poolUTXO.getChildUTXO(newParentHash, address(0x6));
//         assertEq(recipient1Value, 150);
//         assertEq(uint(recipient1Status), uint(PoolUTXO.ChildStatus.Unspent));
        
//         (uint256 recipient2Value, PoolUTXO.ChildStatus recipient2Status) = poolUTXO.getChildUTXO(newParentHash, address(0x7));
//         assertEq(recipient2Value, 250);
//         assertEq(uint(recipient2Status), uint(PoolUTXO.ChildStatus.Unspent));
        
//         // 6. Verify parent UTXO details
//         (uint256 parentValue, address parentOwner, bytes32 previousParentHash) = poolUTXO.getParentUTXO(newParentHash);
//         assertEq(parentValue, 0); // All value is distributed to children
//         assertEq(parentOwner, user2);
//         assertEq(previousParentHash, parentHash);
//     }
    
//     function testFailTransferChildUTXOWithInsufficientValue() public {
//         // 1. Mint a new UTXO and set up as in previous test
//         vm.startPrank(admin);
//         bytes32 hash = keccak256(abi.encodePacked("test", block.timestamp));
//         uint256 initialValue = 1000;
//         address pool = ultraUTXO.mint(
//             hash,
//             initialValue,
//             user1,
//             address(mockToken)
//         );
//         mockToken.transfer(pool, initialValue);
//         vm.stopPrank();
        
//         // Create parent UTXO with children
//         vm.startPrank(user1);
//         PoolUTXO poolUTXO = PoolUTXO(pool);
        
//         recipients = new address[](2);
//         values = new uint256[](2);
        
//         recipients[0] = user2;
//         recipients[1] = user3;
//         values[0] = 400;
//         values[1] = 600;
        
//         bytes32 parentHash = poolUTXO.createParentUTXO(
//             hash,
//             initialValue,
//             values,
//             recipients,
//             address(mockToken)
//         );
//         vm.stopPrank();
        
//         // Try to transfer more than user2 has
//         vm.startPrank(user2);
        
//         address[] memory newRecipients = new address[](1);
//         uint256[] memory newValues = new uint256[](1);
        
//         newRecipients[0] = address(0x6);
//         newValues[0] = 500; // User2 only has 400
        
//         // This should fail
//         poolUTXO.transferChildUTXO(
//             parentHash,
//             newValues,
//             newRecipients,
//             address(mockToken)
//         );
//         vm.stopPrank();
//     }
    
//     function testFailTransferAlreadySpentChildUTXO() public {
//         // 1. Set up as before
//         vm.startPrank(admin);
//         bytes32 hash = keccak256(abi.encodePacked("test", block.timestamp));
//         uint256 initialValue = 1000;
//         address pool = ultraUTXO.mint(
//             hash,
//             initialValue,
//             user1,
//             address(mockToken)
//         );
//         mockToken.transfer(pool, initialValue);
//         vm.stopPrank();
        
//         // Create parent UTXO with children
//         vm.startPrank(user1);
//         PoolUTXO poolUTXO = PoolUTXO(pool);
        
//         recipients = new address[](2);
//         values = new uint256[](2);
        
//         recipients[0] = user2;
//         recipients[1] = user3;
//         values[0] = 400;
//         values[1] = 600;
        
//         bytes32 parentHash = poolUTXO.createParentUTXO(
//             hash,
//             initialValue,
//             values,
//             recipients,
//             address(mockToken)
//         );
//         vm.stopPrank();
        
//         // First transfer
//         vm.startPrank(user2);
//         address[] memory newRecipients = new address[](1);
//         uint256[] memory newValues = new uint256[](1);
        
//         newRecipients[0] = address(0x6);
//         newValues[0] = 400;
        
//         poolUTXO.transferChildUTXO(
//             parentHash,
//             newValues,
//             newRecipients,
//             address(mockToken)
//         );
        
//         // Try to transfer again with the same UTXO (should fail)
//         poolUTXO.transferChildUTXO(
//             parentHash,
//             newValues,
//             newRecipients,
//             address(mockToken)
//         );
//         vm.stopPrank();
//     }
    
//     function testFailTransferWithMismatchedArrays() public {
//         // 1. Set up as before
//         vm.startPrank(admin);
//         bytes32 hash = keccak256(abi.encodePacked("test", block.timestamp));
//         uint256 initialValue = 1000;
//         address pool = ultraUTXO.mint(
//             hash,
//             initialValue,
//             user1,
//             address(mockToken)
//         );
//         mockToken.transfer(pool, initialValue);
//         vm.stopPrank();
        
//         // Create parent UTXO with children
//         vm.startPrank(user1);
//         PoolUTXO poolUTXO = PoolUTXO(pool);
        
//         recipients = new address[](2);
//         values = new uint256[](2);
        
//         recipients[0] = user2;
//         recipients[1] = user3;
//         values[0] = 400;
//         values[1] = 600;
        
//         bytes32 parentHash = poolUTXO.createParentUTXO(
//             hash,
//             initialValue,
//             values,
//             recipients,
//             address(mockToken)
//         );
//         vm.stopPrank();
        
//         // Try to transfer with mismatched arrays
//         vm.startPrank(user2);
//         address[] memory newRecipients = new address[](2);
//         uint256[] memory newValues = new uint256[](1); // One less than recipients
        
//         newRecipients[0] = address(0x6);
//         newRecipients[1] = address(0x7);
//         newValues[0] = 400;
        
//         // This should fail
//         poolUTXO.transferChildUTXO(
//             parentHash,
//             newValues,
//             newRecipients,
//             address(mockToken)
//         );
//         vm.stopPrank();
//     }
// }