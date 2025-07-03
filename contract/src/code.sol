// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "forge-std/console.sol";
import "./interfaces/ICode.sol";
contract Code {

    struct Vote {
        uint256 approveVotes;     // Count of approval votes
        uint256 denyVotes;        // Count of denial votes
    }

    mapping(bytes => MiningCode) public miningCodes; // Mapping of code (hashed public key) to details
    mapping(address => bytes[]) private ownerCodes;   // Mapping owner to their codes
    mapping(address => uint256) private userNonces;     // Nonce for each user (used for creating referrer codes)


    // mapping(address => uint256) public mintLimits;     // Mint limits for addresses
    mapping(bytes => Vote) public votes;             // Voting records for each code
    address[] public daoMembers;                       // DAO members

    uint256 public constant MIN_LOCK_DURATION = 1 days; // Minimum lock duration for active lock
    uint256 public constant MIN_MINING_LOCK_DURATION = 7 days; // Minimum lock duration for mining lock
    uint256 public constant REQUIRED_APPROVALS = 9;    // Number of approvals required to approve a code

    address public admin;
    address public meLab;  // MeLab contract address
    mapping(address => bool) public isAdmin;

    event CodeRequested(bytes code, address indexed assignedTo);
    event CodeApproved(bytes code, address indexed assignedTo);
    event CodeDenied(bytes code);
    event CodeActivated(bytes code);
    event CodeLocked(bytes code, LockType lockType, uint256 until);
    event CodeTransferred(bytes oldCode, bytes newCode, address from, address to);
    event CodeExpired(bytes code);
    event DAOUpdated(address indexed member, bool added);
    event MintLimitUpdated(address indexed user, uint256 limit);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    modifier onlyDAO() {
        require(isDAOMember(msg.sender), "Only DAO members can call this function");
        _;
    }
    modifier isAllowed() {
        require(isAdmin[msg.sender], "Only admin can call this function");
        _;
    }
    constructor(address[] memory _daoMembers) {
        isAdmin[msg.sender] = true;
        daoMembers = _daoMembers;
    }
    function setAdmin(address _admin) external onlyAdmin {
        isAdmin[_admin] = true;
    }
    // Set MeLab contract address
    function setMeLab(address _meLab) external onlyAdmin {
        meLab = _meLab;
        isAdmin[_meLab] = true;
    }
    // Check if an address is a DAO member
    function isDAOMember(address member) public view returns (bool) {
        for (uint256 i = 0; i < daoMembers.length; i++) {
            if (daoMembers[i] == member) {
                return true;
            }
        }
        return false;
    }

    // Add or remove a DAO member
    function updateDAOMember(address member, bool add) external onlyAdmin {
        if (add) {
            daoMembers.push(member);
        } else {
            for (uint256 i = 0; i < daoMembers.length; i++) {
                if (daoMembers[i] == member) {
                    daoMembers[i] = daoMembers[daoMembers.length - 1];
                    daoMembers.pop();
                    break;
                }
            }
        }
        emit DAOUpdated(member, add);
    }

    // Function to get the current nonce of a user
    function getNonce(address user) external view returns (uint256) {
        return userNonces[user];
    }

    // Retrieve codes by owner
    function getCodesByOwner(address owner) external view returns (bytes[] memory) {
        return ownerCodes[owner];
    }
    function getIndexOfCode(address owner,bytes memory code) external view returns(uint256){
        for (uint256 i=0;i < ownerCodes[owner].length; i++) {
            if (_compareCodes(code,ownerCodes[owner][i])){
                return i+1; //return index + 1 cho activate mining
            }  
        }
        return 0; //return 0 nếu ko tìm thấy code trong mảng
    }
    function _compareCodes(bytes memory a, bytes memory b) internal pure returns (bool) {
        return keccak256(a) == keccak256(b);
    }

    // Generate a Code (Hashed Public Key + Checksum)
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

    // Verify if a Code (33 bytes) is valid
    function isValidCode(bytes memory code) public pure returns (bool) {
        bytes32 hash = bytes32(code);
        uint8 checksum = uint8(code[32]);
        return _calculateChecksum(hash) == checksum;
    }

    // Request minting a new code
    function requestCode(
        bytes memory publicKey,
        uint256 boostRate, //boostRate >16 vì halvingReward = 0.0625-> ket qua mining lam tron =0
        uint256 maxDuration,
        address assignedTo,
        address referrer,
        uint256 referralReward,
        bool transferable,
        uint256 expireTime
    ) external onlyDAO() returns(bytes memory){

        bytes memory code = generateCode(publicKey); // Generate hashed code
        require(isValidCode(code), "Invalid code");
        require(!codeExists(code), "Code already exists"); // Check for duplicates
        require(block.timestamp < maxDuration && expireTime > block.timestamp, "maxDuration and expireTime must be over current time");
        miningCodes[code] = MiningCode({
            publicKey: publicKey,
            boostRate: boostRate,
            maxDuration: maxDuration,
            status: CodeStatus.Pending,
            assignedTo: assignedTo,
            referrer: referrer,
            referralReward: referralReward,
            transferable: transferable,
            lockUntil: 0,
            lockType: LockType.None,
            expireTime: expireTime
        });

        emit CodeRequested(code, assignedTo);
        return code;
    }
    //chua loc code phai dc request truoc, 1 nguoi vote nhieu lan van tinh
    // Vote for approving or denying a code
    function voteCode(bytes memory code, bool approve) external onlyDAO {
        MiningCode storage miningCode = miningCodes[code];
        require(miningCode.status == CodeStatus.Pending, "Code is not pending");

        Vote storage vote = votes[code];
        if (approve) {
            vote.approveVotes++;
        } else {
            vote.denyVotes++;
        }

        if (vote.approveVotes >= REQUIRED_APPROVALS) {
            approveCode(code);
        } else if (vote.denyVotes >= REQUIRED_APPROVALS) {
            denyCode(code);
        }
    }
    event CodeCreatedForReferrer(bytes referrerCode,address referrer);
    // Approve mint request
    function approveCode(bytes memory code) internal {
        MiningCode storage miningCode = miningCodes[code];
        require(miningCode.status == CodeStatus.Pending, "Code is not pending");
        miningCode.status = CodeStatus.Approved;
        ownerCodes[miningCode.assignedTo].push(code);
        
        emit CodeApproved(code, miningCode.assignedTo);

        // Handle referrer logic
        address referrer = miningCode.referrer;

        if (referrer != address(0)) {
            uint256 referrerNonce = userNonces[referrer];
            bytes memory referrerPublicKey = abi.encodePacked(referrer, referrerNonce);
            bytes memory referrerCode = generateCode(referrerPublicKey);

            // Increment referrer nonce
            userNonces[referrer]++;

            // Create a new code for the referrer
            miningCodes[referrerCode] = MiningCode({
                publicKey: referrerPublicKey,
                boostRate: miningCode.boostRate / 30, // Referrer gets 30% boost rate of the main code
                maxDuration: miningCode.maxDuration,
                status: CodeStatus.Approved,
                assignedTo: referrer,
                referrer: address(0),
                referralReward: 0,
                transferable: false,
                lockUntil: 0,
                lockType: LockType.None,
                expireTime: miningCode.expireTime
            });

            ownerCodes[referrer].push(referrerCode);
            
            emit CodeCreatedForReferrer(referrerCode, referrer);
        }
    }
     // Check if a code already exists in miningCodes
    function codeExists(bytes memory code) public view returns (bool) {
        return miningCodes[code].assignedTo != address(0);
    }

    function getCodeStatus(bytes memory code) external view returns(Vote memory){
        Vote storage vote = votes[code];
        return vote;
    }

    // Deny mint request
    function denyCode(bytes memory code) internal {
        require(miningCodes[code].status == CodeStatus.Pending, "Code is not pending");
        delete miningCodes[code];
        emit CodeDenied(code);
    }

    // // Activate a code with signature verification
    // function activateCode(
    //     bytes memory publicKey,
    //     bytes memory message,
    //     bytes memory signature
    // ) external {
    //     bytes memory code = generateCode(publicKey); // Derive the code from the public key
    //     MiningCode storage miningCode = miningCodes[code];

    //     require(miningCode.assignedTo != address(0), "Code not found");
    //     require(_verifySignature(publicKey, message, signature), "Invalid signature");

    //     // Decode the message and validate the command
    //     (string memory command, ) = _decodeMessage(message);
    //     require(keccak256(bytes(command)) == keccak256("activate"), "Invalid command");

    //     // Additional checks
    //     require(miningCode.status == CodeStatus.Approved, "Code not approved");
    //     require(block.timestamp <= miningCode.maxDuration, "Code expired");

    //     miningCode.status = CodeStatus.Actived;
    //     emit CodeActivated(code);
    // }
// Activate a code with signature verification
//bên miningCode gọi sang
    function activateCode(
        uint256 indexCode, //vi du mang indexCode = 1 thi code o vi tri 0 trong mang ownerCodes[user]
        address user
    ) external returns (uint256, uint256, uint256) {
        require(indexCode > 0, "Index code not found");
        require(ownerCodes[user].length >0,"no code of sender exists");
        bytes memory code = ownerCodes[user][indexCode -1];
        MiningCode storage miningCode = miningCodes[code];
        require(miningCode.expireTime > block.timestamp,"code expired");

        // Additional checks
        require(miningCode.status == CodeStatus.Approved, "Code not approved");
        require(block.timestamp <= miningCode.maxDuration, "Code expired");

        miningCode.status = CodeStatus.Actived;
        emit CodeActivated(code);

        // uint256 expireTime = 365 days;

        return (miningCode.boostRate, miningCode.maxDuration, miningCode.expireTime);
    }

    // Lock a code with signature verification
    function lockCode(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) external {
        bytes memory code = generateCode(publicKey); // Derive the code from the public key
        MiningCode storage miningCode = miningCodes[code];

        require(miningCode.assignedTo != address(0), "Code not found");
        // require(miningCode.assignedTo != address(0), "Code not found");
        require(_verifySignature(publicKey, message, signature), "Invalid signature");

        // Decode the message and validate the command
        (string memory command, uint256 duration) = _decodeMessage(message);
        require(keccak256(bytes(command)) == keccak256("lock"), "Invalid command");

        // Additional checks
        require(duration >= (miningCode.lockType == LockType.MiningLock ? MIN_MINING_LOCK_DURATION : MIN_LOCK_DURATION), "Lock duration too short");

        miningCode.lockUntil = block.timestamp + duration;
        miningCode.lockType = LockType.ActiveLock;

        emit CodeLocked(code, LockType.ActiveLock, miningCode.lockUntil);
    }

    // Transfer a code to a new owner with signature verification
    function transferCode(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) external {
        bytes memory oldCode = generateCode(publicKey); // Derive the current code
        MiningCode storage miningCode = miningCodes[oldCode];

        require(miningCode.assignedTo != address(0), "Code not found");
        require(_verifySignature(publicKey, message, signature), "Invalid signature");

        // Decode the message and validate the command
        (string memory command, uint256 newPublicKeyParam) = _decodeMessage(message);
        require(keccak256(bytes(command)) == keccak256("transfer"), "Invalid command");

        // Generate the new code from the new public key
        bytes memory newPublicKey = abi.encodePacked(newPublicKeyParam);
        bytes memory newCode = generateCode(newPublicKey);

        require(isValidCode(newCode), "Invalid new code");

        // Transfer the code
        address previousOwner = miningCode.assignedTo;

        miningCodes[newCode] = MiningCode({
            publicKey: newPublicKey,
            boostRate: miningCode.boostRate,
            maxDuration: miningCode.maxDuration,
            status: miningCode.status,
            // assignedTo: miningCode.assignedTo,
            assignedTo: getAddressFromUncompressed(newPublicKey),           //thuy sua
            referrer: miningCode.referrer,
            referralReward: miningCode.referralReward,
            transferable: miningCode.transferable,
            lockUntil: miningCode.lockUntil,
            lockType: miningCode.lockType,
            expireTime: miningCode.expireTime
        });
        bytes[] storage codes = ownerCodes[previousOwner];
        for (uint256 i; i< codes.length; i++){                     //thuy them
            if (keccak256(oldCode) == keccak256(codes[i])){
                codes[i] = codes[codes.length -1];
                codes.pop();
                break;
            }
        }
        ownerCodes[msg.sender].push(newCode); //thuy them
        delete miningCodes[oldCode];
        emit CodeTransferred(oldCode, newCode, previousOwner, msg.sender);
    }
    function getAddressFromUncompressed(bytes memory pubKeyXY) internal pure returns (address) {
        require(pubKeyXY.length == 64, "Invalid public key length, must be 64 bytes");
        
        // Extract X and Y coordinates (32 bytes each)
        uint256 x = bytesToUint256(slice(pubKeyXY, 0, 32));
        uint256 y = bytesToUint256(slice(pubKeyXY, 32, 32));
        
        return getAddressFromXY(x, y);
    }
    /**
     * @dev Convert X,Y coordinates to Ethereum address
     * @param x The X coordinate
     * @param y The Y coordinate
     * @return The Ethereum address
     */
    function getAddressFromXY(uint256 x, uint256 y) internal pure returns (address) {
        // Convert coordinates to bytes
        bytes memory pubKey = abi.encodePacked(x, y);
        
        // Hash with Keccak256
        bytes32 hash = keccak256(pubKey);
        
        // Take last 20 bytes as address
        return address(uint160(uint256(hash)));
    }
  /**
     * @dev Convert bytes32 to uint256
     */
    function bytesToUint256(bytes memory b) internal pure returns (uint256) {
        require(b.length == 32, "Bytes length must be 32");
        uint256 result;
        assembly {
            result := mload(add(b, 32))
        }
        return result;
    }
    
    /**
     * @dev Slice bytes array
     */
    function slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }
    // Verify the signature using the public key
    // function _verifySignature(
    //     bytes memory publicKey,
    //     bytes memory message,
    //     bytes memory signature
    // ) internal pure returns (bool) {
    //     bytes32 hash = keccak256(abi.encodePacked(message));
    //     address recoveredAddress = _recover(hash, signature);
    //     return keccak256(abi.encodePacked(publicKey)) == keccak256(abi.encodePacked(recoveredAddress));
    // }
    function _verifySignature(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal pure returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(message));
        address recoveredAddress = _recover(hash, signature);
        // Extract Ethereum address from the public key
        address expectedAddress = address(uint160(uint256(keccak256(publicKey))));
        // console.log("recoveredAddress:",recoveredAddress);
        // console.log("expectedAddress:",expectedAddress);
        return recoveredAddress == expectedAddress;
    }

    // Recover the address from a hash and signature
    function _recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        bytes memory sign = add27ToLastByte(signature);
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(sign);
        return ecrecover(hash, v, r, s);
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
    function add27ToLastByte(bytes memory input) public pure returns (bytes memory) {
        require(input.length > 0, "Empty input");

        // Copy input to new bytes
        bytes memory output = input;

        // Modify last byte
        output[output.length - 1] = bytes1(uint8(output[output.length - 1]) + 27);

        return output;

    }
    // Decode the message into command and parameter
    function _decodeMessage(bytes memory message) internal pure returns (string memory command, uint256 param) {
        (command, param) = abi.decode(message, (string, uint256));
    }
    function checkExpiration(bytes memory code) external {
        MiningCode storage miningCode = miningCodes[code];
        require(miningCode.status == CodeStatus.Actived, "Code is not active");
        require(block.timestamp > miningCode.maxDuration, "Code is still valid");
        
        miningCode.status = CodeStatus.Expired;
        emit CodeExpired(code);
    }

    // function migrateCode(MiningCode [] memory codeDirectArr) external onlyAdmin {
    //     for (uint256 i = 0; i < codeDirectArr.length; i++) {
    //         MiningCode memory codeDirect = codeDirectArr[i];
    //         // Nếu codeHash đã tồn tại thì migrate
    //         if (codeDirectArr.length > 0) {
    //             // Gọi createCodeDirect trong contract Code mới
    //             createCodeDirect(
    //                 codeDirect.publicKey,
    //                 codeDirect.boostRate,
    //                 codeDirect.maxDuration,
    //                 codeDirect.assignedTo,
    //                 address(0),
    //                 0,
    //                 false,
    //                 codeDirect.expireTime
    //             );
    //         }
    //     }
    // }

    // NEW FUNCTION: Create code directly (called by MeLab after approval)
    function createCodeDirect(
        bytes memory publicKey,
        uint256 boostRate,
        uint256 maxDuration,
        address assignedTo,
        address referrer,
        uint256 referralReward,
        bool transferable,
        uint256 expireTime
    ) public isAllowed returns(bytes memory) {
        bytes memory code = generateCode(publicKey); // Generate hashed code
        require(isValidCode(code), "Invalid code");
        require(!codeExists(code), "Code already exists"); // Check for duplicates
        // Create the mining code directly with Approved status
        miningCodes[code] = MiningCode({
            publicKey: publicKey,
            boostRate: boostRate,
            maxDuration: maxDuration,
            status: CodeStatus.Approved, // Directly approved
            assignedTo: assignedTo,
            referrer: referrer,
            referralReward: referralReward,
            transferable: transferable,
            lockUntil: 0,
            lockType: LockType.None,
            expireTime: expireTime
        });

        // Add to owner's codes
        ownerCodes[assignedTo].push(code);
        
        emit CodeApproved(code, assignedTo);

        // Handle referrer logic
        if (referrer != address(0)) {
            uint256 referrerNonce = userNonces[referrer];
            bytes memory referrerPublicKey = abi.encodePacked(referrer, referrerNonce);
            bytes memory referrerCode = generateCode(referrerPublicKey);

            // Increment referrer nonce
            userNonces[referrer]++;

            // Create a new code for the referrer
            miningCodes[referrerCode] = MiningCode({
                publicKey: referrerPublicKey,
                boostRate: boostRate / 30, // Referrer gets 1/30 boost rate of the main code
                maxDuration: maxDuration,
                status: CodeStatus.Approved,
                assignedTo: referrer,
                referrer: address(0),
                referralReward: 0,
                transferable: false,
                lockUntil: 0,
                lockType: LockType.None,
                expireTime: expireTime
            });

            ownerCodes[referrer].push(referrerCode);
            
            emit CodeCreatedForReferrer(referrerCode, referrer);
        }

        return code;
    }
}
