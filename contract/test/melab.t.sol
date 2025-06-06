// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/code.sol";
import "../src/melab1.sol";
import {console} from "forge-std/console.sol";

contract MelabTest is Test {
    Code codeContract;
    MeLab public meLab;
    address deployer = address(0x111);
    address[] daoMemberArr;
    uint256 private constant PRIVATE_KEY = 1;
    address private  user1 = vm.addr(PRIVATE_KEY);
    address user2 = address(0x666);
    address userA = 0xdf182ed5CF7D29F072C429edd8BFCf9C4151394B;
    address userDAO = generateAddress(1);
    bytes public testPublicKey = hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    uint256 public testBoostRate = 1000;
    uint256 public testMaxDuration = 365 days;
    uint256 public testReferralReward = 100;
    uint256 public testPlanPrice = 1000000; // 1 USDT (6 decimals)
    address public member1 = address(0x2);
    address public member2 = address(0x3);
    address public member3 = address(0x4);
    address public assignedUser = address(0x5);
    address public referrer = address(0x6);
    constructor() {
        for (uint i=1;i<=12;i++){
            address daoMember = generateAddress(i);
            daoMemberArr.push(daoMember);
        }

        vm.startPrank(deployer);
        codeContract = new Code(daoMemberArr);  
        meLab = new MeLab(deployer, address(codeContract));
        codeContract.setMeLab(address(meLab));
        vm.stopPrank();

    }
    function generateAddress(uint256 num) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(num)))));
    }
    function test_CreateOwnerProposal() public {
        vm.prank(deployer);
        uint256 proposalId = meLab.createOwnerProposal(user2, 50);

        UserProposal memory proposal = meLab.getUserProposalInfo(proposalId);

        assertEq(proposal.nominee, user2);
        assertEq(proposal.types, meLab.ADD_OWNER());
        assertEq(proposal.votingRate, 50);
        emit log("Owner proposal created successfully");
        vm.prank(deployer);
        bool success = meLab.voteUserProposal(proposalId, true);
        assertTrue(success, "Vote should succeed");

        emit log("Owner voted on the proposal successfully");
    }
    function CreateMemberProposal() public {
        vm.prank(deployer);
        uint256 proposalId = meLab.createMemberProposal(user2, 100);

        UserProposal memory proposal = meLab.getUserProposalInfo(proposalId);

        assertEq(proposal.nominee, user2);
        assertEq(proposal.types, meLab.ADD_MEMBER());
        assertEq(proposal.votingWeight, 100);
        emit log("Member proposal created successfully");
        vm.prank(deployer);
        bool success = meLab.voteUserProposal(proposalId, true);
        assertTrue(success, "Vote should succeed");

    }
    function testVoteCodeProposalSuccess()external{
        CreateMemberProposal();
 // First create a code proposal
        vm.prank(user2);
        uint256 proposalId = meLab.createCodeProposal(
            testPublicKey,
            testBoostRate,
            testMaxDuration,
            assignedUser,
            referrer,
            testReferralReward,
            true,
            testPlanPrice
        );
        
        vm.prank(user2);        
        meLab.voteCodeProposal(proposalId,true);
        // Kiểm tra code đã được phê duyệt
        bytes memory newCode = generateCode(testPublicKey);
        (,,,CodeStatus status,,,,,, ) = codeContract.miningCodes(newCode);
        assertEq(uint(status), uint(CodeStatus.Approved), "Status should be Approved");
        bytes[] memory codesArr = codeContract.getCodesByOwner(assignedUser);
        assertEq(1,codesArr.length,"code array should have 1 code");

    }
    function generateCode(bytes memory publicKey) public pure returns (bytes memory) {
        // require(publicKey.length == 32, "Invalid public key length"); //thường privatekey mới 32bytes thôi?
        bytes32 hash = keccak256(publicKey); // Hash the public key
        uint8 checksum = _calculateChecksum(hash); // Generate checksum
        return bytes(abi.encodePacked(hash, checksum)); // Combine hash and checksum
    }
    // Calculate checksum from the hash
    function _calculateChecksum(bytes32 hash) internal pure returns (uint8) {
        uint256 sum = 0;
        for (uint256 i = 0; i < 32; i++) {
            sum += uint8(hash[i]);
        }
        return uint8(sum % 256); // Modulo 256 to fit in 1 byte
    }

}