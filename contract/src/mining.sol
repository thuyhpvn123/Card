// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";
/*
* Luồng migrate số dư và code đào: có 2 smart contract là migrareWallet và migrateCode.

- bước 1, khi user import private key
-- nonce đang là 0
--> user gọi để liên kết private key của BLS và address ECDH

- bước 2, tiến hành gọi với address BLS đến migrareWallet để check có balance
--> nếu có thì client gọi hàm migrate với: address ECDH device nhận, public key bls, signature của public key và hash của address ECDH device nhận
--> cộng vào miningDevice và đánh dấu đã liên kết

- bước 3, lấy public code gọi tới migrateCode, nếu có thì tạo ở miningCode thông tin thời gian còn lại của code

*/

/*

thuật toán:

1. done
=> cách nào để biết validator minh bạch trong trả cho miner !?

- device gọi hàm getJob ở SM quy định 0x00000000000000000000000000000010, validator trả về link cần query. device query kết quả và trả về validator. validator trả thưởng theo phút. trong 1 phút mà device có thực hiện được việc yêu cầu thì sẽ được nhận thưởng. device sau đó lại tiếp tục thực hiện.
-- getJob trả về công việc là thực hiện verify lại các giao dịch trong block nếu phần cứng đáp ứng đủ; nếu phần cứng ko đủ thì mở link youtube giới thiệu, hoặc link quảng cáo lên trong 10 giây.

- validator tiến hành cộng cho miner và lưu vào leveldb offfchain.

=> mỗi ngày validator tổng kết các miner đào và cộng vào pending balance ở SM PendingMiningDevice. Sau 48h thì user có thể yêu cầu cộng pending balance vào balance. cần lưu pending balance theo thời gian.


-- khi đó, validator sẽ chọn ngẫu nhiên của validator khác để gửi xác thực về phone qua noti, yêu cầu thực hiện bấm vào. nếu trong vòng 36h mà phone ko bấm vào thì user sẽ bị khoá.
-- device + secret sẽ được mã hoá hash để lưu lên SM AuthChallenge, sau 48h, offchain sẽ gọi lên để kiểm tra.
-- khi client nhận được noti, client bấm vào, thì client sẽ gửi đến SM AuthChallenge.

* trả thưởng:
- nếu tài khoản đừng đào trong 30 ngày, thì sẽ bị khoá vĩnh viễn số dư.

- khi miner chuyển pendingBalance về Balance, thì validator chuyển ETH về cho SM MiningUser giữ

- mỗi ngày khi trả cho user, thì trả lên cho 3 tầng giới thiệu lên trên, và showroom của user


2. done

Active code

- user đưa băm của private code và salt lên qua SM MiningCode hàm commitActivationCode

- user đưa lên cho chain qua hàm encryptedCode để BE giải mã, và đảm bảo kích hoạt thành công cho user

- gửi code, salt với hàm keccak256(abi.encodePacked(code, secret, userAddress))
- SM lưu lại time

- tiếp theo activeCode qua keccak256(abi.encodePacked(code, secret, userAddress)).
- yêu cầu time đã tồn tại từ 1 phút trước

-> check code thì hashed 2 

=> phần code đào, mỗi ngày validator tổng kết các mã đào và biểu quyết cộng balance

3. -> chưa làm
- để đảm bảo đúng sách metanode, cần có circle. mỗi người chỉ được xác thực circle cho 5 người, và điều kiện là cần phải ở gần nhau.

4. không làm:
  + lock key
  + lock time
  + unlock key

*/

library Signature {

    function recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;
        bytes memory sign = add27ToLastByte(signature);
        require(sign.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(sign, 32))
            s := mload(add(sign, 64))
            v := byte(0, mload(add(sign, 96)))
        }

        return ecrecover(hash, v, r, s);
    }
    function add27ToLastByte(bytes memory input) public pure returns (bytes memory) {
        require(input.length > 0, "Empty input");

        // Copy input to new bytes
        bytes memory output = input;

        // Modify last byte
        output[output.length - 1] = bytes1(uint8(output[output.length - 1]) + 27);

        return output;

    }

}

interface PublicKeyFromPrivateKey {
    function getPublicKeyFromPrivate(bytes32 _privateCode) external returns (bytes memory);
}
interface IMiningDevice {
    function addBalance(address miner, uint256 amount) external;
    function linkCodeWithUser(address _user, address _device) external;
}
interface ICode {
    function activateCode(uint256 indexCode,address user) external returns (uint256, uint256, uint256);
}
interface IMiningUser {
    function lockUser(address _user) external;
    function checkJoined(address _user) external view returns (bool);
    function getParentUser(address _user, uint8 _level) external view returns (address[] memory);
}


contract GetJob {
    struct Job {
        bytes32 jobHash;
        string jobType; // "verify" | "ad"
        string dataLink;
        uint256 timestamp;
    }

    mapping(address => Job) public lastJob;
    mapping(address => uint256) public lastActiveTime;

    address[] public activeUsers;
    mapping(address => bool) public isInActiveList;

    event JobAssigned(address indexed user, bytes32 jobHash, string jobType, string dataLink);
    event JobCompleted(address indexed user, bytes32 jobHash, string result, uint256 time);

    /// @dev User gọi hàm này mỗi lần lấy job mới. Truyền kết quả job trước nếu có.
    function getJob(bytes32 prevJobHash, string calldata result) external returns (
        bytes32 newJobHash,
        string memory jobType,
        string memory dataLink
    ) {

        // Kiểm tra thời gian giữa các lần gọi
        require(block.timestamp >= lastActiveTime[msg.sender] + 1 minutes, "Must wait 1 minute before calling again");

        // Nếu đã từng nhận job trước đó, validate kết quả
        if (lastJob[msg.sender].jobHash != 0x0) {
            require(prevJobHash == lastJob[msg.sender].jobHash, "Invalid job hash");
            emit JobCompleted(msg.sender, prevJobHash, result, block.timestamp);
        }

        // Ghi nhận hoạt động
        lastActiveTime[msg.sender] = block.timestamp;
        if (!isInActiveList[msg.sender]) {
            activeUsers.push(msg.sender);
            isInActiveList[msg.sender] = true;
        }

        // Tạo job mới
        string memory _jobType;
        string memory _dataLink;

        // giả định là random: nếu block.timestamp % 2 == 0 thì verify, else quảng cáo
        if (block.timestamp % 2 == 0) {
            _jobType = "verify";
            _dataLink = "https://example.com/block_verify_data.json";
        } else {
            _jobType = "ad";
            _dataLink = "https://youtube.com/watch?v=dQw4w9WgXcQ"; // 😏
        }

        newJobHash = keccak256(abi.encodePacked(msg.sender, block.timestamp, _dataLink));

        // Lưu job mới
        lastJob[msg.sender] = Job({
            jobHash: newJobHash,
            jobType: _jobType,
            dataLink: _dataLink,
            timestamp: block.timestamp
        });

        emit JobAssigned(msg.sender, newJobHash, _jobType, _dataLink);
        return (newJobHash, _jobType, _dataLink);
    }

    function getRecentActiveUsers(uint256 sinceTime) external view returns (address[] memory users) {
        uint256 count = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (lastActiveTime[activeUsers[i]] >= sinceTime) {
                count++;
            }
        }

        users = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (lastActiveTime[activeUsers[i]] >= sinceTime) {
                users[idx++] = activeUsers[i];
            }
        }
    }

    function getLastJob(address user) external view returns (Job memory) {
        return lastJob[user];
    }

    function getActiveUsersCount() external view returns (uint256) {
        return activeUsers.length;
    }

    function clearCurrentJob() external {
        require(lastJob[msg.sender].jobHash != 0x0, "No job to clear");
        delete lastJob[msg.sender];
    }

}


contract PendingMiningDevice {
    struct MiningReward {
        uint256 amount; // Số tiền đang chờ được chuyển
        uint256 pendingSince; // Thời gian pending bắt đầu
        bool isClaimed; // Trạng thái yêu cầu rút
    }

    mapping(address => MiningReward[]) public minerRewards; // Mapping để lưu trữ pending reward cho từng miner
    mapping(address => uint256) public pendingBalance; // Tổng pending balance của từng miner
    
    event RewardPending(address indexed miner, uint256 amount);
    event RewardClaimed(address indexed miner, uint256 amount);
    event RewardTransferred(address indexed miner, uint256 amount);

    address public validator; // Địa chỉ của validator, chỉ validator mới có thể cộng thưởng
    address public miningDevice; // Địa chỉ của MiningDevice contract
    address public miningUser; // Địa chỉ của MiningUser contract, nơi lưu trữ ETH cho miners

    modifier onlyValidator() {
        require(msg.sender == validator, "Only validator can call this");
        _;
    }

    modifier onlyMiningDevice() {
        require(msg.sender == miningDevice, "Only mining device can call this");
        _;
    }

    constructor(address _miningDevice, address _miningUser) {
        validator = msg.sender; // Validator là người deploy contract
        miningDevice = _miningDevice; // Gán địa chỉ của MiningDevice contract
        miningUser = _miningUser; // Gán địa chỉ của MiningUser contract
    }

    // Cộng phần thưởng vào pending balance của miner
    function addPendingReward(address miner, uint256 amount) external onlyValidator {
        require(amount > 0, "Amount must be greater than 0 addPendingReward");

        // Lưu reward vào array cho miner
        minerRewards[miner].push(MiningReward({
            amount: amount,
            pendingSince: block.timestamp,
            isClaimed: false
        }));

        // Cộng vào tổng pending balance của miner
        pendingBalance[miner] += amount;

        emit RewardPending(miner, amount);
    }

    // Miner yêu cầu rút reward sau 48h
    function claimReward() external {
        address miner = msg.sender; // Lấy miner từ msg.sender (người gọi hàm)
        require(pendingBalance[miner] > 0, "No reward available for claim");
        uint256 claimableAmount = 0;
        
        // Duyệt qua các pending rewards và kiểm tra thời gian pending >= 48h
        for (uint256 i = 0; i < minerRewards[miner].length; i++) {
            if (!minerRewards[miner][i].isClaimed && 
                block.timestamp - minerRewards[miner][i].pendingSince >= 48 hours) {
                
                // Cộng reward đủ điều kiện vào claimableAmount
                claimableAmount += minerRewards[miner][i].amount;
                
                // Đánh dấu reward là đã yêu cầu
                minerRewards[miner][i].isClaimed = true;
            }
        }

        require(claimableAmount > 0, "No reward available for claim");
        require(pendingBalance[miner] >= claimableAmount, "No reward available for claim");
        
        // Cộng reward vào balance chính của miner
        pendingBalance[miner] -= claimableAmount;
        
        // Gọi hàm addBalance trong MiningDevice để cộng balance cho miner
        IMiningDevice(miningDevice).addBalance(miner, claimableAmount);

        emit RewardClaimed(miner, claimableAmount);
    }

    // Validator có thể thay đổi địa chỉ validator nếu cần
    function setValidator(address newValidator) external onlyValidator {
        validator = newValidator;
    }

    // MiningDevice có thể thay đổi địa chỉ của contract MiningDevice nếu cần
    function setMiningDevice(address newMiningDevice) external onlyValidator {
        miningDevice = newMiningDevice;
    }

    // MiningUser có thể thay đổi địa chỉ của contract MiningUser nếu cần
    function setMiningUser(address newMiningUser) external onlyValidator {
        miningUser = newMiningUser;
    }
}




/**
 * @title Secure Activation
 * @dev Cơ chế kích hoạt an toàn với commit-reveal
 * - Người dùng trước tiên gửi commit chứa băm của (privateCode, secret, userAddress)
 * - Sau ít nhất 15 giây, họ mới có thể gửi privateCode thật để active
 * - Cơ chế này giúp chống spam và chiếm quyền kích hoạt từ node pool
 */
contract MiningCode {
    struct ActivationCommit {
        bytes32 commitHash;
        uint256 commitTime;
    }

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
    // uint256 private constant TIME_MINING = 24 hours;
    uint256 private constant TIME_MINING = 1 minutes; //for test only

    ICode public codeContract;

    mapping(address => ActivationCommit) public commits;

    // Mỗi code là 1 cặp private key và public key, khi check sẽ dùng hashed của public key
    // Khi active sẽ dùng hashed private key để commit, sau đó mới active thì gửi privateCode
    mapping(bytes32 => bool) public miningPublicCodes;
    mapping(bytes32 => DataCode) public miningPrivateCodes;

    // Địa chỉ của contract PublicKeyFromPrivateKey
    PublicKeyFromPrivateKey public keyContract;

    event CodeCommitted(address indexed user, bytes32 commitHash);
    event CodeActivated(address indexed user);
    event CodeGenned(address indexed creator, uint256 boostRate, uint256 maxDuration, uint256 expireTime);
    event CodeReplaced(address indexed replacer, uint256 newBoostRate, uint256 newMaxDuration, uint256 newExpireTime);

    uint256 public constant REVEAL_DELAY = 15 seconds; // Thời gian chờ tối thiểu trước khi active

    uint256 private constant BONUS_REF_1 = 20; // 20%
    uint256 private constant BONUS_REF_2 = 10; // 10%
    uint256 private constant BONUS_REF_3 = 5; // 5%
    uint256 private constant BONUS_REF_4 = 5; // 5%

    uint256 private constant BONUS_SHOWROOM = 20; // 20%


    bytes32[] activeCodes;
    uint256 lastTimeMiningDevices;

    address owner;
    IMiningDevice private miningDevice;
    IMiningUser public miningUser;
    mapping(address => bytes32[]) public mActivePrivateCodes; //user => mang priva
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _keyContractAddress, address _codeContract) {
        keyContract = PublicKeyFromPrivateKey(_keyContractAddress); // Khởi tạo địa chỉ của contract lấy public key

        codeContract = ICode(_codeContract);

        owner = msg.sender;
    }
    function setCodeContract(address _codeContract ) external onlyOwner {
        codeContract = ICode(_codeContract);
    }
    function setMiningDevice(address _miningDeviceAddress) external onlyOwner {
        miningDevice = IMiningDevice(_miningDeviceAddress);
    }

    function setMiningUser(address _miningUserAddress) external onlyOwner {
        miningUser = IMiningUser(_miningUserAddress);
    }

    // gọi qua smart contract Code để kích hoạt code theo index trong list code tại SM Code do user được cấp
    function genCode(uint256 indexCode, bytes32 _hashedPrivateCode, bytes32 _hashedPublicCode) external {
        require(indexCode > 0, "Invalid index code");
        require(_hashedPrivateCode != bytes32(0), "Invalid hashed private code");
        require(_hashedPublicCode != bytes32(0), "Invalid hashed public code");

        // kiểm tra xem có _hashedPrivateCode nào đã active chưa
        require(miningPrivateCodes[_hashedPrivateCode].boostRate == 0, "Private Code already genned");
        require(!miningPublicCodes[_hashedPublicCode], "Public Code already genned");

        /*
         gọi qua SM Code để tiến hành active cho code và nhận lại thông tin của code:
        */

        (uint256 boostRate, uint256 maxDuration, uint256 expireTime) = codeContract.activateCode(indexCode,msg.sender);
        require(boostRate > 0, "wrong boostRate");
        require(maxDuration > 0, "wrong maxDuration");
        require(expireTime > 0, "wrong expireTime");


        miningPrivateCodes[_hashedPrivateCode].boostRate = boostRate;
        miningPrivateCodes[_hashedPrivateCode].maxDuration = maxDuration;
        miningPrivateCodes[_hashedPrivateCode].expireTime = expireTime;



        miningPublicCodes[_hashedPublicCode] = true;

        emit CodeGenned(msg.sender, boostRate, maxDuration, expireTime);
    }
    function cancelCommit(address user) external onlyOwner {
        require(commits[user].commitHash != 0, "commit does not exist");
        delete commits[user];

    }
    /**
     * @dev Người dùng gửi commit trước với hash(privateCode, secret, userAddress)
     * @param _commitHash Giá trị băm của privateCode + secret + userAddress
     */
    function commitActivationCode(bytes32 _commitHash) external {
        require(commits[msg.sender].commitHash == 0, "Already committed"); 

        commits[msg.sender] = ActivationCommit({
            commitHash: _commitHash,
            commitTime: block.timestamp
        });

        emit CodeCommitted(msg.sender, _commitHash);
    }

    // replaceCode dùng để đổi code cũ qua code mới
    function replaceCode(bytes32  _privateCode, bytes memory _secret, bytes32 _hashedPrivateCode, bytes32 _hashedPublicCode) external {
        require(_hashedPrivateCode == bytes32(0), "Invalid hashed private code");
        require(_hashedPublicCode == bytes32(0), "Invalid hashed private code");

        ActivationCommit memory commit = commits[msg.sender];

        require(commit.commitHash != 0, "No commit found");
        require(block.timestamp >= commit.commitTime + REVEAL_DELAY, "Wait for reveal time");

        bytes32 expectedHash = keccak256(abi.encodePacked(_privateCode, _secret, msg.sender));
        require(expectedHash == commit.commitHash, "Invalid code");

        // Kiểm tra code có đúng không?
        bytes32 hashedPrivateCode = keccak256(abi.encodePacked(_privateCode));
        require(miningPrivateCodes[hashedPrivateCode].owner == address(0), "Code not exists");
        require(miningPrivateCodes[hashedPrivateCode].activeTime == 0, "Code already activated");

        // Lấy public key từ private code để kiểm tra
        bytes memory publicKey = keyContract.getPublicKeyFromPrivate(_privateCode); // Sử dụng hàm lấy public key từ contract khác

        bytes32 hashedPublicKey = keccak256(abi.encodePacked(publicKey));
        require(miningPublicCodes[hashedPublicKey] == true, "Public code not found");

        delete miningPublicCodes[hashedPublicKey];
        
        uint256 boostRate = miningPrivateCodes[hashedPrivateCode].boostRate;
        uint256 maxDuration = miningPrivateCodes[hashedPrivateCode].maxDuration;
        uint256 expireTime = miningPrivateCodes[hashedPrivateCode].expireTime;

        delete miningPrivateCodes[hashedPrivateCode];


        miningPrivateCodes[_hashedPrivateCode].boostRate = boostRate;
        miningPrivateCodes[_hashedPrivateCode].maxDuration = maxDuration;
        miningPrivateCodes[_hashedPrivateCode].expireTime = expireTime;

        
        miningPublicCodes[_hashedPublicCode] = true;

        delete commits[msg.sender]; // Xóa commit để tránh reuse
        emit CodeReplaced(msg.sender, boostRate, maxDuration, expireTime);
    }

    /**
     * @dev Sau ít nhất 15 giây, user có thể gửi privateCode thật để kích hoạt
     * @param _privateCode Mã kích hoạt thật
     * @param _secret Giá trị bí mật đã dùng khi tạo commit
     */
    function activateCode(bytes32  _privateCode, bytes memory _secret) external {
        ActivationCommit memory commit = commits[msg.sender];

        require(commit.commitHash != 0, "No commit found");
        require(block.timestamp >= commit.commitTime + REVEAL_DELAY, "Wait for reveal time");

        bytes32 expectedHash = keccak256(abi.encodePacked(_privateCode, _secret, msg.sender));
        // console.logBytes32(expectedHash);
        require(expectedHash == commit.commitHash, "Invalid code");

        // Kiểm tra code có đúng không?
        bytes32 hashedPrivateCode = keccak256(abi.encodePacked(_privateCode));
        require(miningPrivateCodes[hashedPrivateCode].owner == address(0), "Code not exists");
        require(miningPrivateCodes[hashedPrivateCode].activeTime == 0, "Code already activated");

        // Lấy public key từ private code để xóa
        bytes memory publicKey = keyContract.getPublicKeyFromPrivate(_privateCode); // Sử dụng hàm lấy public key từ contract khác
        bytes32 hashedPublicKey = keccak256(abi.encodePacked(publicKey));
        require(miningPublicCodes[hashedPublicKey] == true, "Public code not found");

        delete miningPublicCodes[hashedPublicKey];


        miningPrivateCodes[hashedPrivateCode].activeTime = block.timestamp;
        // gán mỗi quan hệ giữa user và code
        miningPrivateCodes[hashedPrivateCode].owner = msg.sender;

        // gọi qua cho link ví user và owner

        // _device để lấy 19 byte cuối (152 bits) và giữ byte đầu là 0
        address _deviceRemoveFirstBytes = address(uint160(uint256(hashedPublicKey) & 0x0000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
        miningDevice.linkCodeWithUser(msg.sender, _deviceRemoveFirstBytes);
        

        miningPrivateCodes[hashedPrivateCode].device = _deviceRemoveFirstBytes;
        miningPrivateCodes[hashedPrivateCode].privateCode = _privateCode;
        
        // lưu danh sách active code
        activeCodes.push(hashedPrivateCode);
        mActivePrivateCodes[msg.sender].push(_privateCode);

        // tiến hành lấy danh sách liên kết giới thiệu để lưu vào code
        address[] memory devices = miningUser.getParentUser(msg.sender, 4);
        if (devices.length >= 1){
            miningPrivateCodes[hashedPrivateCode].ref_1 = devices[0];
        }
        if (devices.length >= 2){
            miningPrivateCodes[hashedPrivateCode].ref_2 = devices[1];
        }
        if (devices.length >= 3){
            miningPrivateCodes[hashedPrivateCode].ref_3 = devices[2];
        }
        if (devices.length == 4){
            miningPrivateCodes[hashedPrivateCode].ref_4 = devices[3];
        }

        // tiến hành lấy showroom gần nhất
        // #to-do đưa thêm smart contract showroom vào để quét và lưu lại


        // mining code sẽ được ofchain gọi, và tiếp theo sẽ gọi qua MiningDevice đẻ lưu code lại
        delete commits[msg.sender]; // Xóa commit để tránh reuse


        emit CodeActivated(msg.sender);
    }
    function getActivePrivateCode(address user) external view returns(DataCode[] memory){
        require(msg.sender == owner || msg.sender == user,"only owner or owner code can call");
        bytes32[] memory activeCodeArr = mActivePrivateCodes[user];
        DataCode[] memory dataCodes = new DataCode[](activeCodeArr.length);
        for (uint256 i = 0; i < activeCodeArr.length; i++) {
            bytes32 hashedPrivateCode = keccak256(abi.encodePacked(activeCodeArr[i]));
            DataCode memory miningPrivateCode = miningPrivateCodes[hashedPrivateCode];
            dataCodes[i] = miningPrivateCode;
        }
        return dataCodes;
    }
    /**
     * @dev Kiểm tra xem public code có hợp lệ hay không
     * @param _hashedPublicCode Giá trị băm của publicCode
     * @return bool Trả về true nếu mã tồn tại, ngược lại false
     */
    function isCodeValid(bytes32 _hashedPublicCode) external view returns (bool) {
        return miningPublicCodes[_hashedPublicCode];
    }

    // offchain goi yêu cầu
    function claim(uint256 halvingReward) external onlyOwner {
        require(block.timestamp - lastTimeMiningDevices > TIME_MINING, "not match time");

        lastTimeMiningDevices = block.timestamp;

        uint256[] memory removedIndexCodes = new uint256[](activeCodes.length);
        uint256 totalRemovedIndexCode = 0;
        // console.log("activeCodes.length:",activeCodes.length);
        for (uint256 i = 0; i < activeCodes.length; i++) {
            DataCode memory miningPrivateCode = miningPrivateCodes[activeCodes[i]];

            if (block.timestamp >= miningPrivateCode.expireTime ) {
                removedIndexCodes[totalRemovedIndexCode] = i;
                totalRemovedIndexCode += 1;
                continue;
            }
            // claimableAmount: tính trên tốc độ đào và thời gian
            uint256 claimableAmount = miningPrivateCode.boostRate * halvingReward;
            // tinh cho ref

            if(miningPrivateCode.ref_1 != address(0)){
                miningDevice.addBalance(miningPrivateCode.ref_1, (claimableAmount *  BONUS_REF_1 / 100 ));
            }
            if(miningPrivateCode.ref_2 != address(0)){
                miningDevice.addBalance(miningPrivateCode.ref_2, (claimableAmount *  BONUS_REF_2 / 100 ));
            }
            if(miningPrivateCode.ref_3 != address(0)){
                miningDevice.addBalance(miningPrivateCode.ref_3, (claimableAmount *  BONUS_REF_3 / 100 ));
            }
            if(miningPrivateCode.ref_4 != address(0)){
                miningDevice.addBalance(miningPrivateCode.ref_4, (claimableAmount *  BONUS_REF_4 / 100 ));
            }
            if(miningPrivateCode.showroom != address(0)){
                miningDevice.addBalance(miningPrivateCode.showroom, (claimableAmount *  BONUS_SHOWROOM / 100 ));
            }

            // xử lý cho việc cộng balances
            if(miningPrivateCode.device != address(0)){
                miningDevice.addBalance(miningPrivateCode.device, claimableAmount);
            }
        }

        // Xóa từ cuối về đầu
        for (uint256 i = totalRemovedIndexCode; i > 0; i--) {
            uint256 indexCode = removedIndexCodes[i - 1];

            if ( indexCode != activeCodes.length - 1 ) {
                activeCodes[indexCode] = activeCodes[activeCodes.length - 1];
            }

            activeCodes.pop();
        }
        
    }

}

contract MiningDevice {
    using Signature for *;

    uint256 private constant TIME_MINING = 24 hours;

    // lưu số lần halving, mỗi lần halving thì tốc độ chia 2
    uint8 private halvingReward;
    uint8 public halvingCount;
    
    mapping(address => address[]) public userDevices;
    mapping(address => address[]) public deviceUsers; // Lưu trữ user liên kết với từng device

    mapping(address => bool) public lockedDevices;     // Kiểm tra trạng thái khóa của thiết bị

    mapping(address => mapping(address => uint256)) public linkTimeUserDevices;

    mapping(address => uint256) public lastTimeMiningDevices;
    mapping(address => uint256) public balances;
    mapping(address => bool) public isAdmin;

    event DeviceActivated(address indexed user, address indexed device);
    
    event BalanceUpdated(address indexed device, uint256 amount);
    
    
    // Event khi thiết bị bị khóa
    event DeviceLocked(address indexed device, address indexed user);

    IMiningUser public miningUserContract;

    address private owner;
    address private miningCodeAddress;

    modifier onlyMiningUser() {
        require(msg.sender == address(miningUserContract), "Only mining user can call this");
        _;
    }

    modifier onlyMiningCode() {
        require(msg.sender == miningCodeAddress, "Only mining user can call this");
        _;
    }


    modifier onlyRegisteredUser() {
        require(miningUserContract.checkJoined(msg.sender), "Not a registered user");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    modifier onlyAdmin() {
        require(isAdmin[msg.sender] == true, "Not admin");
        _;
    }

    constructor() {
        owner = msg.sender;

        halvingReward = 3;
        halvingCount = 1;
    }
    function setMiningUser(address _miningUserContract) external onlyOwner {
        miningUserContract = IMiningUser(_miningUserContract);
    }
    function setMiningCode(address _miningCodeAddress) external onlyOwner {
        miningCodeAddress = _miningCodeAddress;
    }
    function setAdmin(address _admin, bool _approved) external onlyOwner {
        isAdmin[_admin] = _approved;
    }
    // Hàm chung xử lý link device chỉ gọi được từ miningCode
    function linkCodeWithUser(address _user, address _device) external onlyMiningCode {
        // Kiểm tra điều kiện cơ bản
        require(_user != address(0), "Invalid user address");
        require(_device != address(0), "Invalid device address");


        // require(userDevices[_user].length < 50, "Max linked device to user"); // mỗi user có tối da 50 thiết bị
        // require(deviceUsers[_device].length < 10, "Max linked device"); // mỗi thiết bị được link tối đa đến 10 tài khoản khác nhau

        // Kiểm tra xem thiết bị đã được liên kết với user chưa
        require(linkTimeUserDevices[_device][_user] == 0, "Device already linked to this user");

        // Liên kết thiết bị với user
        userDevices[_user].push(_device);  // Thêm thiết bị vào danh sách của user
        // Lưu lại thông tin user liên kết với device
        deviceUsers[_device].push(_user);

        linkTimeUserDevices[_device][_user] = block.timestamp;  // Lưu thời gian liên kết
        lastTimeMiningDevices[_device] = block.timestamp;  // Cập nhật thời gian khai thác
        emit DeviceActivated(_user, _device);  // Phát sự kiện liên kết thành công
    }

    // Hàm chung xử lý link device (chỉ có thể gọi từ các hàm internal)
    function _linkDevice(address _user, bytes memory _signature, uint256 createdTime, address _device, bool isUserSignature) internal {
        // Kiểm tra điều kiện cơ bản
        require(_user != address(0), "Invalid user address");
        require(_device != address(0), "Invalid device address");
        require(_signature.length > 0, "Signature required");
        require(userDevices[_user].length < 50, "Max linked device to user"); // mỗi user có tối da 50 thiết bị
        require(deviceUsers[_device].length < 10, "Max linked device"); // mỗi thiết bị được link tối đa đến 10 tài khoản khác nhau

        bytes32 expectedHash;

        // Nếu là người dùng gọi (isUserSignature = true), hash sẽ là keccak của _device, còn không thì là _user
        if (isUserSignature) {
            expectedHash = keccak256(abi.encodePacked(_device, createdTime));  // Keccak của _device khi user gọi
        } else {
            expectedHash = keccak256(abi.encodePacked(_user, createdTime));  // Keccak của _user khi device gọi
        }

        // Kiểm tra chữ ký của người dùng hoặc thiết bị dựa trên isUserSignature
        address recoveredAddress = Signature.recoverSigner(expectedHash, _signature);
     
        // Kiểm tra chữ ký của user hoặc device
        if (isUserSignature) {
            require(recoveredAddress == _device, "Invalid device signature");
        } else {
            require(recoveredAddress == _user, "Invalid user signature");
        }

        // Kiểm tra xem thiết bị đã được liên kết với user chưa
        require(linkTimeUserDevices[_device][_user] == 0, "Device already linked to this user");

        // Kiểm tra thời gian chữ ký có hợp lệ (trong vòng 10 phút)
        require(block.timestamp - createdTime <= 600, "Signature expired");

        // Liên kết thiết bị với user
        userDevices[_user].push(_device);  // Thêm thiết bị vào danh sách của user
        // Lưu lại thông tin user liên kết với device
        deviceUsers[_device].push(_user);

        linkTimeUserDevices[_device][_user] = block.timestamp;  // Lưu thời gian liên kết
        lastTimeMiningDevices[_device] = block.timestamp;  // Cập nhật thời gian khai thác

        emit DeviceActivated(_user, _device);  // Phát sự kiện liên kết thành công
    }
    // function add27ToLastByte(bytes memory input) public pure returns (bytes memory) {
    //         require(input.length > 0, "Empty input");

    //         // Copy input to new bytes
    //         bytes memory output = input;

    //         // Modify last byte
    //         output[output.length - 1] = bytes1(uint8(output[output.length - 1]) + 27);

    //         return output;
    //     }
    // Hàm cho thiết bị gọi để liên kết
    function deviceLinkToUser(address _user, bytes memory _signature, uint256 createdTime) external {
        require(_user != address(0), "Invalid user address");

        // Lấy địa chỉ của thiết bị từ msg.sender
        address deviceAddress = msg.sender;

        // Gọi hàm nội bộ để xử lý liên kết, với isUserSignature = true vì chữ ký của user cần xác minh
        _linkDevice(_user, _signature, createdTime, deviceAddress, false);
    }

    // Hàm cho người dùng gọi để liên kết
    function userLinkToDevice(address _device, bytes memory _signature, uint256 createdTime) external {
        require(_device != address(0), "Invalid device address");

        // Lấy địa chỉ của người dùng từ msg.sender
        address userAddress = msg.sender;

        // Gọi hàm nội bộ để xử lý liên kết, với isUserSignature = false vì chữ ký của device cần xác minh
        _linkDevice(userAddress, _signature, createdTime, _device, true);
    }

    // Hàm để khóa tất cả thiết bị của một user
    function lockAllDevicesOfUser(address device) external onlyOwner {
        // Lấy tất cả các user đã liên kết với device này
        address[] memory users = deviceUsers[device];

        // Kiểm tra nếu không có user nào liên kết với device
        require(users.length > 0, "No users linked to this device");

        // Duyệt qua tất cả các user và khóa thiết bị của họ
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            miningUserContract.lockUser(user);

            // Lấy danh sách thiết bị của user
            address[] memory userDevicesList = userDevices[user];

            // Duyệt qua tất cả thiết bị của user và khóa từng thiết bị
            for (uint256 j = 0; j < userDevicesList.length; j++) {
                address userDevice = userDevicesList[j];

                // Kiểm tra nếu thiết bị chưa bị khóa
                if(lockedDevices[userDevice]) {
                    continue;
                }

                // Khóa thiết bị
                lockedDevices[userDevice] = true;

                // Emit sự kiện khóa thiết bị
                emit DeviceLocked(userDevice, user);
            }
        }
    }
    // Hàm chỉ có thể gọi bởi PendingMiningDevice (validator sẽ gọi hàm này)
    function addBalance(address _device, uint256 amount) external onlyAdmin {
        // console.log("amount:",amount);
        // Kiểm tra nếu amount phải lớn hơn 0
        require(amount > 0, "Amount must be greater than 0");
        require(lastTimeMiningDevices[_device] > 0, "device not active");
        
        // chỉ cho phép 2 lần đào cách nhau đúng thời gian quy định
        require(block.timestamp - lastTimeMiningDevices[_device] > TIME_MINING, "not match time");


        // Cộng phần thưởng vào balance của _device
        balances[_device] += amount;

        lastTimeMiningDevices[_device] = block.timestamp;

        // Emit sự kiện để ghi nhận thay đổi balance
        emit BalanceUpdated(_device, balances[_device]);
    }


    function isLinkUserDevice(address user, address device) public view returns (bool) {
        return linkTimeUserDevices[device][user] > 0;
    }

    function balanceOf(address device) public view returns (uint256) {
        return balances[device];
    }

    function withdraw(address device, uint256 amount) public onlyMiningUser {
        require(balances[device] >= amount, "Insufficient balance");
        balances[device] -= amount;
    }


    function rebackWithdraw(address device, uint256 amount) public onlyMiningUser {
        require(amount > 0, "Insufficient amount");
        balances[device] += amount;
    }
}

contract MiningUser {
    using Signature for *;
    struct User {
        address parent;
        address device; // lưu device mà user muốn trả phí đến, device này bắt buộc phải đã link đến user
        uint8 referralCount;
        uint256 createdTime;
        bool isLocked;
    }


    struct DraftUser {
        address referral;
        string encryptToken;
        bytes32 OTP;
    }


    struct UserAmount {
        address device;
        uint256 usdtAmount;
        uint256 resourceAmount;
        uint256 lastWithdrawTime; // Thời gian của lần rút gần nhất
    }
    
    mapping(address => User) private users;
    mapping(address => UserAmount[]) private userAmounts;
    mapping(address => address[]) private referrals;
    mapping(address => bytes32) private activationCodes;
    
    event UserRegistered(address indexed user, address indexed parent);
    event ReferralRewardPaid(address indexed referrer, address indexed user, uint256 amount);
    event UserProcessing(address indexed user,address parent, bytes32 OTP);
    event UserActivated(address indexed user, address indexed activator);
    event DeviceReplaced(address indexed user, address oldDevice, address newDevice);

    event ResourcePurchased(address indexed user, address indexed device, uint256 resourceAmount, uint256 usdtAmount);
    event DepositRefunded(address indexed user, uint256 index, uint256 usdtAmount, uint256 ethReceived);


    
    event UserRef(address indexed referal, address indexed referer, string _referralEncryptTokenNoti);

    uint8 private constant MAX_REFERRAL = 10;
    uint8 private constant MAX_LEVELS = 3;
    uint256 private constant TIME_REFERRAL = 1 weeks;
    


    IERC20 public usdtToken; // USDT Token

    // Địa chỉ của contract miningDeviceContract
    MiningDevice public miningDeviceContract;

    address BE;
    mapping(address => DraftUser) private draftUsers; // Đối tượng draft user

    // khi là số âm, nghĩa là lấy 1 / cho số dương, còn khi là dương thì nhân trực tiếp
    int256 private halvingDeposit;

    mapping(address => mapping(uint256 => bool)) public isDepositWithdrawn;
    // INoti public Notification;
    mapping(address => bool) public mUserToOtpStatus; //user => true if otp right
    address rootUser;

    modifier onlyBE() {
        require(BE == msg.sender, "only BE can call");
        _;
    }


    modifier onlyMiningDevice() {
        require(msg.sender == address(miningDeviceContract), "Only mining device can call this");
        _;
    }


    constructor(
        address _BE,
        address _usdtAddress,
        address _miningDeviceAddress,
        address _rootUser
    ) {

        usdtToken = IERC20(_usdtAddress); // Gán USDT contract

        BE = _BE;

        users[msg.sender] = User({
            parent: msg.sender,
            device: address(0),
            referralCount: 0,
            createdTime: block.timestamp,
            isLocked: false
        });

        miningDeviceContract = MiningDevice(_miningDeviceAddress);



        halvingDeposit = -1000;
        rootUser = _rootUser;
    }

    function lockUser(address _user) external onlyMiningDevice {
        users[_user].isLocked = true;

    }
    function registerUser(address _user, address _parent) internal {
        require(users[_user].parent == address(0), "User already exists");
        require(users[_parent].parent == address(0), "Parent not exists");
        require(_parent != _user, "Cannot refer yourself");
        require(!users[_parent].isLocked, "user is locked");
        require(users[_parent].referralCount < MAX_REFERRAL, "Max referrals reached");
        // parent can tham gia duoc 1 tuan thi moi gioi thieu
        require(block.timestamp - users[_parent].createdTime > TIME_REFERRAL, "Parent need joined before 1 week from this step");

        users[_user] = User({
            parent: _parent,
            device: address(0),
            referralCount: 0,
            createdTime: block.timestamp,
            isLocked: false
        });

        users[_parent].referralCount++;
        
        emit UserRegistered(_user, _parent);
    }

    // A show qr code info, B gọi lên SM
    // encryptToken là token của phone đẻ cho nhận noti thông báo
    // noti chứa code để active
    function refUserViaQRCode(address _referralAddress, bytes memory _referralSignature, string memory _referralEncryptTokenNoti) external {
         // ✳️ Kiểm tra người gọi đã được active
        require(users[msg.sender].parent != address(0) || msg.sender == rootUser, "Only active users can refer others");
        require(users[_referralAddress].parent == address(0), "User exists");
        require(draftUsers[_referralAddress].referral == address(0), "Pending user confirm");


        // kiểm tra chữ ký của _referralSignature, xem referral đã ký lên _referralEncryptTokenNoti với time nhỏ hơn 10 phút ko

        address recoverAddress = Signature.recoverSigner(
            keccak256(abi.encodePacked(_referralEncryptTokenNoti))
            , _referralSignature
        );

        require(recoverAddress == _referralAddress, "address not match");
        
        draftUsers[msg.sender] = DraftUser({
            referral: _referralAddress,
            encryptToken: _referralEncryptTokenNoti,
            OTP: bytes32(0)
        });

        // bắn event token cho BE, để BE có thể gửi noti với _OTP cho user bấm vào
        emit UserRef(_referralAddress, msg.sender, _referralEncryptTokenNoti);
        // NotiParams memory params = NotiParams(
        //         // NOTIFIER,
        //         // data,
        //         // dataStruct,
        //         title,
        //         body
        //     );
        // Notification.AddNoti(params, _to);
    }
    function deleteRefUser() external {
        require(users[msg.sender].parent == address(0), "User exists");
        require(draftUsers[msg.sender].referral == address(0), "User exists");

        delete draftUsers[msg.sender];
    }

    // user bấm vào noti, lấy OTP gửi lên SM tới đoạn cần khi user bấm vào noti và chọn active
    function processUserWithOTP(address parent, bytes32 _OTP) external {
        require(draftUsers[parent].referral != address(0), "User not exists");


        draftUsers[parent].OTP = _OTP;

        // gửi sự kiện cho BE
        emit UserProcessing(msg.sender,parent, _OTP);
    }
    function updateOtpStatus(address parent,bool status) external onlyBE {
        mUserToOtpStatus[parent] = status;
    }
    
    // BE bắt được OTP, BE sẽ gọi lên để active ví cho user
    function activeUserByBe(address _parent, bytes32 _OTP) external onlyBE {
        // require(draftUsers[_parent].referral == address(0), "User exists");
        require(draftUsers[_parent].OTP == _OTP, "OTP not matched");

        address _user = draftUsers[_parent].referral;
        registerUser(_user, _parent);

        delete draftUsers[_user];
        
        emit UserActivated(_user, _parent);
    }


    function checkJoined(address _user) external view returns (bool) {
        require(!users[_user].isLocked, "user is locked");
        return users[_user].parent != address(0);
    }
    
    function getInfo() external view returns (User memory) {
        require(!users[msg.sender].isLocked, "user is locked");
        return users[msg.sender];
    }

    // hàm này mục tiêu để lấy danh sách các tầng trên của user
    function getParentUser(address _user, uint8 _level) external view returns (address[] memory) {
        require(_level <= 4, "user is locked");

        address parent = users[_user].parent;
        address[] memory devices = new address[](_level);

        for (uint8 i = 0; i < _level; i++) {
            if (parent == address(0)) {
                break;
            }

            if (users[parent].isLocked) {
                devices[i] = address(0);
            } else {
                devices[i] = users[parent].device;
            }

            parent = users[parent].parent;
        }

        return devices;
    }

    function setDeviceDefault(address _device) external {
        require(!users[msg.sender].isLocked, "user is locked");
        require(users[msg.sender].device == address(0), "user had linked");

        require(miningDeviceContract.isLinkUserDevice(msg.sender, _device) == true, "user not link with device");

        users[msg.sender].device = _device;
    }


    /// @dev User cọc để rút MTD về ví
    function depositToWithdraw(address _device, uint256 usdtAmount, uint256 resourceAmount) external {
        require(usdtAmount > 100, "Must send USDT to deposit");
        require(!users[msg.sender].isLocked, "user is locked");

        uint256 expectedUSDT = 0;
        if (halvingDeposit < 0) {
            expectedUSDT = resourceAmount / uint256(-1 * halvingDeposit);
        } else {
            expectedUSDT = resourceAmount * uint256(halvingDeposit);
        }
        require(usdtAmount >= expectedUSDT, "Not enough usdt");


        // kiểm tra xem user có số MTD lớn hơn ko
        require(miningDeviceContract.isLinkUserDevice(msg.sender, _device) == true, "user not link with device");

        // Lấy số dư MTD trên thiết bị của user
        uint256 deviceBalance = miningDeviceContract.balanceOf(_device);
        // Kiểm tra tỷ lệ rút tối đa là 10% của số dư trên thiết bị
        uint256 maxWithdrawable = deviceBalance * 10 / 100;  // 10% của số dư

        // Kiểm tra xem resourceAmount có lớn hơn tỷ lệ rút tối đa không
        require(resourceAmount <= maxWithdrawable, "Withdraw limit exceeded: You can only withdraw up to 10% of device balance.");


        // Kiểm tra thời gian giữa lần cọc trước và lần cọc hiện tại (ở phần tử cuối cùng trong mảng userAmounts)
        if (userAmounts[msg.sender].length > 0) {
            uint256 lastWithdrawTime = userAmounts[msg.sender][userAmounts[msg.sender].length - 1].lastWithdrawTime;
            uint256 timeDifference = block.timestamp - lastWithdrawTime;
            require(timeDifference >= 1 weeks, "You can only deposit once every week");
        }


        // Chuyển USDT vào hợp đồng
        uint256 balanceBefore = usdtToken.balanceOf(address(this));
        require(usdtToken.transferFrom(msg.sender, address(this), usdtAmount), "USDT transfer failed");
        uint256 receivedUSDT = usdtToken.balanceOf(address(this)) - balanceBefore;
        // require(receivedUSDT >= usdtAmount - 1e18 && receivedUSDT <= usdtAmount + 1e18, "Incorrect USDT transfer amount");//comment lai de balance nho van rut duoc 

        // Ghi nhận dòng tiền từ user mua
        userAmounts[msg.sender].push(UserAmount({
            device: _device,
            usdtAmount: usdtAmount,
            resourceAmount: resourceAmount,
            lastWithdrawTime: block.timestamp // Thời gian lần gửi cọc đầu tiên
        }));

        miningDeviceContract.withdraw(_device, resourceAmount);

         // Đúc ETH: chuyển từ contract về ví user
        (bool sent, ) = msg.sender.call{value: resourceAmount}("");
        require(sent, "Failed to send resource");


        emit ResourcePurchased(msg.sender, _device, resourceAmount, usdtAmount);
    }

    function getListDeposit(address _user) external view returns (UserAmount[] memory) {
        return userAmounts[_user];
    }

    function refundDeposit(uint256 index) external payable {
        require(index < userAmounts[msg.sender].length, "Invalid index");
        require(!isDepositWithdrawn[msg.sender][index], "Already withdrawn");
        require(msg.value > 0, "empty value");

        UserAmount memory info = userAmounts[msg.sender][index];

        require(msg.value == info.resourceAmount, "Incorrect resource amount");

        uint256 contractBalance = usdtToken.balanceOf(address(this));
        require(contractBalance >= info.usdtAmount, "Contract lacks USDT");

        // Trả USDT lại cho user
        require(usdtToken.transfer(msg.sender, info.usdtAmount), "USDT refund failed");

        // Đánh dấu đã rút
        isDepositWithdrawn[msg.sender][index] = true;

        // trả lại mtd vào balance
        miningDeviceContract.rebackWithdraw(info.device, info.resourceAmount);

        emit DepositRefunded(msg.sender, index, info.usdtAmount, msg.value);
    }

    // Hàm nhận ETH từ validator
    receive() external payable {}

}
