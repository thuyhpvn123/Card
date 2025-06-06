// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "./ICodePool.sol";
import "./interfaces/ICode.sol";

// Interface for Code contract
// Interface for Code contract
interface ICode {
    function createCodeDirect(
        bytes memory publicKey,
        uint256 boostRate,
        uint256 maxDuration,
        address assignedTo,
        address referrer,
        uint256 referralReward,
        bool transferable
    ) external returns(bytes memory);
    
    function requestCode(
        bytes memory publicKey,
        uint256 boostRate,
        uint256 maxDuration,
        address assignedTo,
        address referrer,
        uint256 referralReward,
        bool transferable
    ) external returns(bytes memory);
    
    function voteCode(bytes memory code, bool approve) external;
    function isDAOMember(address member) external view returns (bool);
    function getCodeStatus(bytes memory code) external view returns(uint256 approveVotes, uint256 denyVotes);
    function activateCode(uint256 indexCode, address user) external returns (uint256, uint256, uint256);
    function getCodesByOwner(address owner) external view returns (bytes[] memory);
}


struct UserProposal {
    uint256 proposalId;
    bytes32 types;
    uint256 createdAt;
    uint256 voteCount;
    uint256 votingRate; // For Role Owner
    uint256 votingWeight; // For Role Member
    bool isApproved;
    address nominee;
}

struct CodeProposal {
    uint256 proposalId;
    bool isApproved;
    uint256 voteCount;
    uint256 createdAt;
    uint256 price;
    bytes codeHash; // Changed from bytes32 to bytes to match Code contract
    // Store code creation parameters
    bytes publicKey;
    uint256 boostRate;
    uint256 maxDuration;
    address assignedTo;
    address referrer;
    uint256 referralReward;
    bool transferable;
}

contract MeLab is Ownable {
    // ==== Start Variable Zone ====
    // Proposal types
    bytes32 public constant ADD_OWNER = keccak256("ADD_OWNER");
    bytes32 public constant REVOKE_OWNER = keccak256("REVOKE_OWNER");
    bytes32 public constant ADD_MEMBER = keccak256("ADD_MEMBER");
    bytes32 public constant REVOKE_MEMBER = keccak256("REVOKE_MEMBER");
    bytes32 public constant CREATE_CODE = keccak256("CREATE_CODE");

    address[] public ownerList;
    mapping(address => uint256) public indexOfOwner;
    mapping(address => uint256) public votingRate;
    uint256 public votingRateDecimal = 2;
    uint256 public constant VOTING_RATE_APPROVED_TARGET = 6667;

    address[] public memberList;
    mapping(address => uint256) public indexOfMember;
    mapping(address => uint256) public voteWeight;
    uint256 public totalVoteWeight;
    uint256 public deployedDate;
    mapping(bytes32 => bool) public validProposalType;

    uint8 public returnRIP = 10;

    UserProposal[] public userProposalList;
    CodeProposal[] public codeProposalList;

    mapping(address => mapping(uint256 => bool)) public hasVoted;

    // Interface to Code contract
    ICode public codeContract;
    // ICodePool public codePool;
    // IMining public MINING;

    uint256 public totalCreatedCode;
    uint256 public usdtDecimal = 10 ** 6;
    uint256 public boostSpeedDecimal = 10 ** 2;
    uint256 public rateBoost = (1 * usdtDecimal) / 10;

    address public boostStorage;
    address public miningMeLab;
    // ==== End Variable Zone ====

    event ECreateUserProposal(uint256 proposalId);
    event ECreateCodeProposal(uint256 proposalId);
    event EUserProposalVote(address voter, uint256 proposalId, uint256 atTime);
    event ECodeProposalVote(address voter, uint256 proposalId, uint256 atTime);
    event EApproveProposal(uint256 proposalId, uint256 atTime);
    event CodeRequested(bytes codeHash, address indexed assignedTo);
    event CodeApproved(bytes codeHash, address indexed assignedTo);

    constructor(address _owner, address _codeContract) Ownable(msg.sender) {
        ownerList.push(_owner);
        indexOfOwner[_owner] = ownerList.length;
        votingRate[_owner] = 100 * 10 ** votingRateDecimal;
        // codePool = ICodePool(_codePool);
        // MINING = IMining(_mining);
        codeContract = ICode(_codeContract);
        deployedDate = block.timestamp;
        
        validProposalType[ADD_OWNER] = true;
        validProposalType[REVOKE_OWNER] = true;
        validProposalType[ADD_MEMBER] = true;
        validProposalType[REVOKE_MEMBER] = true;
        validProposalType[CREATE_CODE] = true;
    }

    modifier onlyRoleOwner() {
        require(indexOfOwner[msg.sender] > 0, "MetaLab: Only Owner Role");
        _;
    }

    modifier onlyRoleMember() {
        require(indexOfMember[msg.sender] > 0, "MetaLab: Only Member Role");
        _;
    }

    modifier onlyBoostStorage() {
        require(msg.sender == boostStorage, "MetaLab: Only Boosting Storage");
        _;
    }

    modifier onlyMiningMeLab() {
        require(msg.sender == miningMeLab, "MetaLab: Only Mining MeLab");
        _;
    }

    function setBoostStorage(address _boostStorage) external onlyOwner {
        boostStorage = _boostStorage;
    }

    function setMiningLab(address _miningMeLab) external onlyOwner {
        miningMeLab = _miningMeLab;
    }

    function setCodeContract(address _codeContract) external onlyOwner {
        codeContract = ICode(_codeContract);
    }

    // Updated createCodeProposal function to work with Code contract
    function createCodeProposal(
        bytes memory _publicKey,
        uint256 _boostRate,
        uint256 _maxDuration,
        address _assignedTo,
        address _referrer,
        uint256 _referralReward,
        bool _transferable,
        uint256 _planPrice
    ) external onlyRoleMember returns (uint256) {
        require(_planPrice / usdtDecimal > 0, "MetaLab: Invalid Code Value");
        require(_maxDuration > 0, "MetaLab: Invalid Max Duration");
        require(_assignedTo != address(0), "MetaLab: Invalid Assigned Address");

        CodeProposal memory newProposal = CodeProposal({
            proposalId: codeProposalList.length + 1,
            createdAt: block.timestamp,
            voteCount: 0,
            isApproved: false,
            price: _planPrice,
            codeHash: "", // Will be set after Code contract generates it
            publicKey: _publicKey,
            boostRate: _boostRate,
            maxDuration: _maxDuration,
            assignedTo: _assignedTo,
            referrer: _referrer,
            referralReward: _referralReward,
            transferable: _transferable
        });
        
        codeProposalList.push(newProposal);
        
        emit ECreateCodeProposal(newProposal.proposalId);
        emit CodeRequested("", _assignedTo); // Empty codeHash for now
        
        return newProposal.proposalId;
    }

    // // Updated executeCreateCode function to interact with Code contract
    // function executeCreateCode(uint256 _proposalId) internal {
    //     CodeProposal storage proposal = codeProposalList[_proposalId - 1];
        
    //     // Request code creation from Code contract
    //     bytes memory codeHash = codeContract.requestCode(
    //         proposal.publicKey,
    //         proposal.boostRate,
    //         proposal.maxDuration,
    //         proposal.assignedTo,
    //         proposal.referrer,
    //         proposal.referralReward,
    //         proposal.transferable
    //     );
        
    //     // Update proposal with generated code hash
    //     proposal.codeHash = codeHash;
    //     totalCreatedCode++;
        
    //     emit CodeApproved(codeHash, proposal.assignedTo);
    // }
    // Updated executeCreateCode function to create code directly
    function executeCreateCode(uint256 _proposalId) internal {
        CodeProposal storage proposal = codeProposalList[_proposalId - 1];
        
        // Create code directly in Code contract (bypassing voting)
        bytes memory codeHash = codeContract.createCodeDirect(
            proposal.publicKey,
            proposal.boostRate,
            proposal.maxDuration,
            proposal.assignedTo,
            proposal.referrer,
            proposal.referralReward,
            proposal.transferable
        );
        
        // Update proposal with generated code hash
        proposal.codeHash = codeHash;
        totalCreatedCode++;
        
        emit CodeApproved(codeHash, proposal.assignedTo);
    }
    // Function to vote on code in the Code contract (for DAO members)
    function voteCodeInCodeContract(bytes memory codeHash, bool approve) external onlyRoleMember {
        // Verify that this member is also a DAO member in Code contract
        require(codeContract.isDAOMember(msg.sender), "MetaLab: Not a DAO member in Code contract");
        
        codeContract.voteCode(codeHash, approve);
    }

    // Get code status from Code contract
    function getCodeStatusFromCodeContract(bytes memory codeHash) external view returns (uint256 approveVotes, uint256 denyVotes) {
        return codeContract.getCodeStatus(codeHash);
    }

    // Get codes owned by an address from Code contract
    function getCodesFromCodeContract(address owner) external view returns (bytes[] memory) {
        return codeContract.getCodesByOwner(owner);
    }

    // Activate code through Code contract
    function activateCodeFromCodeContract(uint256 indexCode, address user) external onlyMiningMeLab returns (uint256, uint256, uint256) {
        return codeContract.activateCode(indexCode, user);
    }

    // Get code information from a successful proposal
    function getCodeProposalInfo(
        uint256 _proposalId
    ) external view returns (CodeProposal memory) {
        require(_proposalId <= codeProposalList.length, "MetaLab: Invalid proposal ID");
        return codeProposalList[_proposalId - 1];
    }

    function getCodeHashFromSuccessVoteProposal(uint256 _proposalId) external view returns(bytes memory codeHash) {
        require(_proposalId <= codeProposalList.length, "MetaLab: Invalid proposal ID");
        if (codeProposalList[_proposalId - 1].isApproved) {
            return codeProposalList[_proposalId - 1].codeHash;
        }
        return "";
    }

    // Original proposal functions remain the same
    function createOwnerProposal(
        address _nominee,
        uint256 _votingRate
    ) external onlyRoleOwner returns (uint256 proposalId) {
        checkValidNominee(ADD_OWNER, _nominee);
        UserProposal memory newProposal = UserProposal({
            proposalId: userProposalList.length + 1,
            types: ADD_OWNER,
            createdAt: block.timestamp,
            voteCount: 0,
            votingRate: _votingRate,
            votingWeight: 0,
            isApproved: false,
            nominee: _nominee
        });

        userProposalList.push(newProposal);
        emit ECreateUserProposal(newProposal.proposalId);
        return newProposal.proposalId;
    }

    function revokeOwnerProposal(
        address _nominee
    ) external onlyRoleOwner returns (uint256 proposalId) {
        checkValidNominee(REVOKE_OWNER, _nominee);
        UserProposal memory newProposal = UserProposal({
            proposalId: userProposalList.length + 1,
            types: REVOKE_OWNER,
            createdAt: block.timestamp,
            voteCount: 0,
            votingRate: 0,
            votingWeight: 0,
            isApproved: false,
            nominee: _nominee
        });
        userProposalList.push(newProposal);
        emit ECreateUserProposal(newProposal.proposalId);
        return newProposal.proposalId;
    }

    function revokeMemberProposal(
        address _nominee
    ) external onlyRoleOwner returns (uint256 proposalId) {
        checkValidNominee(REVOKE_MEMBER, _nominee);
        UserProposal memory newProposal = UserProposal({
            proposalId: userProposalList.length + 1,
            types: REVOKE_MEMBER,
            createdAt: block.timestamp,
            voteCount: 0,
            votingRate: 0,
            votingWeight: 0,
            isApproved: false,
            nominee: _nominee
        });
        userProposalList.push(newProposal);
        emit ECreateUserProposal(newProposal.proposalId);
        return newProposal.proposalId;
    }

    function createMemberProposal(
        address _nominee,
        uint256 _votingWeight
    ) external onlyRoleOwner returns (uint256 proposalId) {
        checkValidNominee(ADD_MEMBER, _nominee);
        UserProposal memory newProposal = UserProposal({
            proposalId: userProposalList.length + 1,
            types: ADD_MEMBER,
            createdAt: block.timestamp,
            voteCount: 0,
            votingRate: 0,
            votingWeight: _votingWeight,
            isApproved: false,
            nominee: _nominee
        });

        userProposalList.push(newProposal);
        emit ECreateUserProposal(newProposal.proposalId);
        return newProposal.proposalId;
    }

    function checkValidNominee(bytes32 _types, address _nominee) internal view {
        if (_types == ADD_OWNER) {
            require(
                indexOfOwner[_nominee] == 0,
                "MetaLab: Nominee Is Already Owner"
            );
        } else if (_types == REVOKE_OWNER) {
            require(
                indexOfOwner[_nominee] > 0,
                "MetaLab: Nominee Is Not Owner"
            );
        } else if (_types == ADD_MEMBER) {
            require(
                indexOfMember[_nominee] == 0,
                "MetaLab: Nominee Is Already Member"
            );
        } else if (_types == REVOKE_MEMBER) {
            require(
                indexOfMember[_nominee] > 0,
                "MetaLab: Nominee Is Not Member"
            );
        } else {
            revert("MetaLab: Invalid Proposal Types");
        }
    }

    function getUserProposalInfo(
        uint256 _proposalId
    ) external view returns (UserProposal memory) {
        isValidUserProposalId(_proposalId);
        return _getUserProposalInfo(_proposalId);
    }

    function isValidUserProposalId(uint256 _proposalId) internal view {
        require(
            userProposalList[_proposalId - 1].proposalId == _proposalId &&
                userProposalList[_proposalId - 1].nominee != address(0),
            "MetaLab: Invalid User Proposal Id"
        );
    }

    function _getUserProposalInfo(
        uint256 _proposalId
    ) internal view returns (UserProposal memory) {
        return userProposalList[_proposalId - 1];
    }

    function voteUserProposal(
        uint256 _proposalId,
        bool _option
    ) external onlyRoleOwner returns (bool) {
        isValidUserProposalId(_proposalId);
        require(
            !userProposalList[_proposalId - 1].isApproved,
            "MetaLab: Already Approved Vote"
        );
        require(!hasVoted[msg.sender][_proposalId], "MetaLab: Already Vote");
        if (_option) {
            userProposalList[_proposalId - 1].voteCount += votingRate[
                msg.sender
            ];
        }
        hasVoted[msg.sender][_proposalId] = true;
        emit EUserProposalVote(msg.sender, _proposalId, block.timestamp);

        if (
            userProposalList[_proposalId - 1].voteCount >=
            VOTING_RATE_APPROVED_TARGET &&
            !userProposalList[_proposalId - 1].isApproved
        ) {
            UserProposal memory proposal = userProposalList[_proposalId - 1];
            if (proposal.types == ADD_OWNER) {
                executeAddOwner(proposal);
            } else if (proposal.types == REVOKE_OWNER) {
                executeRevokeOwner(proposal);
            } else if (proposal.types == ADD_MEMBER) {
                executeAddMember(proposal);
            } else if (proposal.types == REVOKE_MEMBER) {
                executeRevokeMember(proposal);
            } else {
                revert("MetaLab: Invalid Proposal Types");
            }
            userProposalList[_proposalId - 1].isApproved = true;
            emit EApproveProposal(proposal.proposalId, block.timestamp);
        }
        return true;
    }

    function voteCodeProposal(
        uint256 _proposalId,
        bool _option
    ) external onlyRoleMember returns (bool) {
        require(
            !codeProposalList[_proposalId - 1].isApproved,
            "MetaLab: Already Approved Vote"
        );
        if (_option) {
            codeProposalList[_proposalId - 1].voteCount += voteWeight[
                msg.sender
            ];
        }
        hasVoted[msg.sender][_proposalId] = true;
        if (
            codeProposalList[_proposalId - 1].voteCount >=
            getRequiredVote(totalVoteWeight) &&
            !codeProposalList[_proposalId - 1].isApproved
        ) {
            executeCreateCode(_proposalId);
            codeProposalList[_proposalId - 1].isApproved = true;
            emit EApproveProposal(_proposalId, block.timestamp);
        }

        emit ECodeProposalVote(msg.sender, _proposalId, block.timestamp);
        return true;
    }

    function getRequiredVote(
        uint256 totalVoteNumber
    ) internal pure returns (uint256) {
        return ((totalVoteNumber + 1) * 2) / 3;
    }

    // Execute methods for user proposals
    function executeAddOwner(UserProposal memory proposal) internal {
        ownerList.push(proposal.nominee);
        indexOfOwner[proposal.nominee] = ownerList.length;
        votingRate[proposal.nominee] = proposal.votingRate;
    }

    function executeRevokeOwner(UserProposal memory proposal) internal {
        uint256 index = indexOfOwner[proposal.nominee];
        if (index > 0) {
            ownerList[index - 1] = ownerList[ownerList.length - 1];
            indexOfOwner[ownerList[index - 1]] = index;
            ownerList.pop();
            delete indexOfOwner[proposal.nominee];
            delete votingRate[proposal.nominee];
        }
    }

    function executeAddMember(UserProposal memory proposal) internal {
        memberList.push(proposal.nominee);
        indexOfMember[proposal.nominee] = memberList.length;
        voteWeight[proposal.nominee] = proposal.votingWeight;
        totalVoteWeight += proposal.votingWeight;
    }

    function executeRevokeMember(UserProposal memory proposal) internal {
        uint256 index = indexOfMember[proposal.nominee];
        if (index > 0) {
            totalVoteWeight -= voteWeight[proposal.nominee];
            memberList[index - 1] = memberList[memberList.length - 1];
            indexOfMember[memberList[index - 1]] = index;
            memberList.pop();
            delete indexOfMember[proposal.nominee];
            delete voteWeight[proposal.nominee];
        }
    }
}