// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/utxo.sol";
import "../src/usdt.sol";
import "../src/masterpool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract UltraUTXOTest is Test {
    UltraUTXO private ultraUTXO;
    USDT private USDT_ERC;
    PoolUTXO private POOlUTXO;
    MasterPool public MASTERPOOL;
    address private owner = address(0x123);
    address private user1 = address(0x456);
    address private user2 = address(0x789);
    address recipient1 = address(0x3);
    address recipient2 = address(0x4);


    constructor() {
        // Deploy UltraUTXO contract
        vm.startPrank(owner);
        ultraUTXO = new UltraUTXO();
        // Deploy USDT token
        USDT_ERC = new USDT();
        MASTERPOOL = new MasterPool(address(USDT_ERC),address(ultraUTXO));
        ultraUTXO.setMasterPool(address(MASTERPOOL));


        // Mint tokens to the owner and users
        USDT_ERC.mintToAddress(owner, 1_000_000 ether);
        // USDT_ERC.mintToAddress(user1, 1_000_000 ether);
        USDT_ERC.mintToAddress(user2, 1_000_000 ether);
        vm.stopPrank();
    }

    function testMintUTXO() public {
        vm.startPrank(owner);
        uint256 parentValue = 1000 ;

        bytes32 parentHash = keccak256(abi.encodePacked(user1, parentValue, block.timestamp, block.number));

        // // Approve UltraUTXO to transfer tokens on behalf of the owner
        // USDT_ERC.approve(address(ultraUTXO), parentValue);

        // Mint a UTXO
        address poolAddress = ultraUTXO.mint(parentHash, parentValue, user1, address(USDT_ERC));

        // Check that the UTXO has been created correctly
        (uint256 utxoValue, bool spent, address pool, address utxoOwner, address token) = ultraUTXO.childUTXOs(parentHash);
        assertEq(utxoValue, parentValue);
        assertFalse(spent);
        assertEq(pool, poolAddress);
        assertEq(utxoOwner, user1);
        assertEq(token, address(USDT_ERC));

        vm.stopPrank();
        //
         vm.startPrank(user1);
         POOlUTXO = PoolUTXO(pool);
        bytes32 previousParentHashRoot = POOlUTXO.previousParentHashRoot();
        console.log("previousParentHashRoot:");
        console.logBytes32(previousParentHashRoot);
        // bytes32 previousParentHash0 = parentHash;
        uint256[] memory childValues = new uint256[](2);
        childValues[0] = 300;
        childValues[1] = 700;

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
         // Create a previous parent UTXO to satisfy the requirement
        bytes32 newParentHash = keccak256(abi.encodePacked(user1, parentValue, block.timestamp, block.number));
        
        bytes32 newhash =  POOlUTXO.createParentUTXO(previousParentHashRoot, parentValue, childValues, recipients,address(USDT_ERC));
        // (,,bytes32 previousParentHash,,,) = POOlUTXO.parentUTXOs(newParentHash);       
        assertEq(newhash, newParentHash, "hash should be same");
        // Assert
        (uint256 value, address ownerPool, bytes32 prevHash) = POOlUTXO.getParentUTXO(newParentHash);
        assertEq(value, 0, "Parent UTXO value mismatch");
        assertEq(ownerPool, user1, "Parent UTXO owner mismatch");
        assertEq(prevHash, previousParentHashRoot, "Previous parent hash mismatch");
        (uint256 storedValue1, PoolUTXO.ChildStatus spent1) = POOlUTXO.getChildUTXO(newParentHash, recipient1);
        (uint256 storedValue2, PoolUTXO.ChildStatus spent2) = POOlUTXO.getChildUTXO(newParentHash, recipient2);
        assertEq(storedValue1, 300, "Child 1 value should be set correctly");
        assertEq(storedValue2, 700, "Child 2 value should be set correctly");
        assertEq(uint8(spent1), uint8(PoolUTXO.ChildStatus.Unspent), "Child 1 should be unspent");
        assertEq(uint8(spent2), uint8(PoolUTXO.ChildStatus.Unspent), "Child 2 should be unspent");
        vm.stopPrank();
        transferChildUTXO(newhash);
        // redeemChildUTXO(parentHash);
    }
    function transferChildUTXO(bytes32 newParentHash )public{
        vm.startPrank(recipient1);
         uint256[] memory values = new uint256[](2);
        values[0] = 200;
        values[1] = 100;

        address[] memory transferRecipients = new address[](2);
        transferRecipients[0] = address(0x8);
        transferRecipients[1] = address(0x9);
        bytes32 newParentHashChild =  POOlUTXO.transferChildUTXO(newParentHash, values, transferRecipients,address(USDT_ERC));
        //Verify parent UTXO details
        (uint256 storedValue, address storedOwner, bytes32 previousParentHash) =  POOlUTXO.getParentUTXO(newParentHashChild);
        assertEq(storedValue, 0, "should be equal");// All value is distributed to children
        assertEq(storedOwner, recipient1, "should be equal");
        assertEq(previousParentHash, newParentHash);
        // 4. Verify recipient1's UTXO is spent
        (uint256 user2NewValue, PoolUTXO.ChildStatus user2NewStatus) = POOlUTXO.getChildUTXO(newParentHash, recipient1);
        assertEq(user2NewValue, 300); // Value shouldn't change
        assertEq(uint(user2NewStatus), uint(PoolUTXO.ChildStatus.Spent)); // Status should be spent
        // 5. Verify new UTXOs were created for the recipients
        (uint256 recipient1Value, PoolUTXO.ChildStatus recipient1Status) = POOlUTXO.getChildUTXO(newParentHashChild, address(0x8));
        assertEq(recipient1Value, 200);
        assertEq(uint(recipient1Status), uint(PoolUTXO.ChildStatus.Unspent));
        
        (uint256 recipient2Value, PoolUTXO.ChildStatus recipient2Status) = POOlUTXO.getChildUTXO(newParentHashChild, address(0x9));
        assertEq(recipient2Value, 100);
        assertEq(uint(recipient2Status), uint(PoolUTXO.ChildStatus.Unspent));

        // Verify the new UTXO for user2
        (uint256 user2Value, , ) = POOlUTXO.children(newParentHash,recipient1);
        assertEq(user2Value, 300 );

        // Verify the remaining UTXO for user1
        (uint256 user1Value, , ) = POOlUTXO.children(newParentHashChild,address(0x8));
        assertEq(user1Value, 200 );
        vm.stopPrank();
        
    }
    function testRedeemChildUTXO()public{
        bytes32 tokenCard = keccak256("token_card");
        vm.startPrank(owner);
        uint256 parentValue = 1 ;

        bytes32 parentHash = keccak256(abi.encodePacked(user1, parentValue, block.timestamp, block.number));
        console.log("parentHash test:");
        console.logBytes32(parentHash);
        // // Approve UltraUTXO to transfer tokens on behalf of the owner
        // USDT_ERC.approve(address(ultraUTXO), parentValue);

        // Mint a UTXO
        address pool = ultraUTXO.mint(parentHash, parentValue, user1, address(USDT_ERC));
        bytes32 previousParentHashRoot = PoolUTXO(pool).previousParentHashRoot();
        console.log("previousParentHashRoot:");
        console.logBytes32(previousParentHashRoot);
        uint256[] memory childValues = new uint256[](1);
        childValues[0] = 1;
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        bytes32 newhash =  PoolUTXO(pool).createParentUTXO(previousParentHashRoot, parentValue, childValues, recipients,address(USDT_ERC));


        vm.stopPrank();  
        
        //redeem
        vm.prank(owner);
        USDT_ERC.mintToAddress(address(MASTERPOOL), 1_000_000);

        vm.warp(block.timestamp + 60 days);
        vm.startPrank(user1);
        PoolUTXO(pool).withdrawChildUTXO(newhash, tokenCard, address(USDT_ERC));
        uint256 bal = USDT_ERC.balanceOf(user1);
        console.log("bal la:",bal);
        // PoolUTXO(pool).redeemChildUTXO(newhash, tokenCard, address(USDT_ERC));
 
    }
    // function testRedeemChildUTXO() public {
    //     vm.startPrank(owner);

    //     bytes32 utxoHash = keccak256("utxo_1");
    //     uint256 value = 100 ether;

    //     // Mint a UTXO
    //     USDT_ERC.approve(address(ultraUTXO), value);
    //     ultraUTXO.mint(user1, utxoHash, value, owner, address(USDT_ERC));

    //     // Fast forward time to make UTXO active
    //     vm.warp(block.timestamp + 61 days);

    //     // Redeem the UTXO
    //     vm.startPrank(user1);
    //     // PoolUTXO pool = PoolUTXO(ultraUTXO.childUTXOs(utxoHash).pool);
    //     (,,address poolAd,,) = ultraUTXO.childUTXOs(utxoHash);
    //     PoolUTXO pool = PoolUTXO(poolAd);
    //     bytes32 tokenCard = keccak256("token_card");

    //     pool.redeemChildUTXO(utxoHash, tokenCard, address(USDT_ERC));

    //     // Check token balance of user1
    //     assertEq(USDT_ERC.balanceOf(user1), 100 ether);

    //     // Verify that the UTXO is marked as redeemed
    //     (, PoolUTXO.ChildStatus spent, ) = pool.children(user1);
    //     assertEq(uint8(spent), uint8(PoolUTXO.ChildStatus.Redeemed),"should be equal");

    //     vm.stopPrank();
    // }
}
