// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./utxo.sol";
import "./interfaces/ICard.sol";
import "forge-std/console.sol";
/**
 * @title CardTokenManager
 * @dev Smart contract quản lý token liên kết thẻ mã hóa, kiểm tra region và giới hạn sử dụng
 */
contract CardTokenManager is Ownable {
    // ===== STRUCTS =====

    // ===== EVENTS =====
    event TokenRequest(address  indexed user, bytes encryptedCardData, bytes32 requestId);
    event TokenIssued(address indexed user, bytes32 indexed tokenId, string region, bytes32 requestId, bytes32 cardHash);
    event TokenFailed(address indexed user, bytes32 requestId, string reason);
    event ChargeRequest(address  indexed user, bytes32 tokenId, address merchant, uint256 amount);
    event ChargeRejected(address  indexed user, bytes32 tokenId, string reason);
    event RequestUpdateTxStatus(string transactionID,bytes32 tokenId);
    // ===== STATE =====
    mapping(bytes32 => CardToken) public tokens; // tokenId => CardToken
    mapping(address => bytes32[]) public userTokens; // user => token list

    mapping(bytes32 => mapping(uint256 => uint256)) public tokenUsagePerMinute;
    mapping(bytes32 => mapping(uint256 => uint256)) public tokenUsagePerHour;
    mapping(bytes32 => mapping(uint256 => uint256)) public tokenUsagePerDay;
    mapping(bytes32 => mapping(uint256 => uint256)) public tokenUsagePerWeek;

    mapping(bytes32 => mapping(uint256 => uint256)) public cardUsagePerMinute;
    mapping(bytes32 => mapping(uint256 => uint256)) public cardUsagePerHour;
    mapping(bytes32 => mapping(uint256 => uint256)) public cardUsagePerDay;
    mapping(bytes32 => mapping(uint256 => uint256)) public cardUsagePerWeek;

    mapping(address => MerchantRule) public merchantRules;
    mapping(address => bool) public userPending; // Đánh dấu user đang có request chưa xử lý

    mapping(bytes32 => bool) public lockedCards; // cardHash => isLocked

    address public beProcessor;

    // address public admin;

    // Dùng cho cleanup và tính rule
    mapping(bytes32 => uint256) public recentToken;  // tokenId => lastUsedTimestamp
    bytes32[] public recentTokenList;

    mapping(bytes32 => uint256) public recentCard;   // cardHash => lastUsedTimestamp
    bytes32[] public recentCardList;

    GlobalRule public smRule;

    // mapping lưu danh sách các phút đã phát sinh giao dịch theo token hoặc cardHash
    mapping(bytes32 => uint256[]) public tokenUsageTimestamps;
    mapping(bytes32 => uint256[]) public cardUsageTimestamps;

    bool public isLocked;

    bytes public backendPubKey; // 65 bytes: 0x04 + X(32) + Y(32)

    mapping(bytes32 => bytes32) private mRequestIdTokenId;//sửa private thành private để debug
    mapping(address => bool) public isAdmin;
    mapping(address => bytes32) public mUserToLastRequestId;

    mapping(string => TransactionStatus) public mTxIdToStatus;
    mapping(bytes32 => string) public mTokenIdToLastTxID;
    UltraUTXO public ULTRA_UTXO;
    address public token;
    mapping(string => PoolInfo) public mTransactionIdToPoolInfo; //transactionID => PoolInfo

    modifier onlyUnlocked() {
        require(!isLocked, "Contract is locked");
        _;
    }

    modifier onlyAdmin() {
        require(isAdmin[msg.sender] == true, "Only admin allowed");
        _;
    }

    modifier onlyBEProcessor() {
        require(msg.sender == beProcessor, "Only backend processor allowed");
        _;
    }

    // ===== MODIFIERS =====
    modifier onlyTokenOwner(bytes32 tokenId) {
        require(tokens[tokenId].owner == msg.sender, "Not token owner");
        require(tokens[tokenId].isActive, "Token inactive");
        _;
    }

    constructor(address _processor) Ownable(msg.sender){
        isAdmin[msg.sender] =  true ;
        // Bạn có thể thêm điều kiện chỉOwner nếu muốn bảo mật hơn
        beProcessor = _processor;
    }
    
    // ===== API =====
    function setUtxoUltra(address _utxo) external onlyAdmin {
        ULTRA_UTXO = UltraUTXO(_utxo); 
    }
    function setLock(bool _locked) external onlyAdmin {
        // Nếu muốn hạn chế ai được quyền gọi, có thể dùng `onlyOwner` hoặc 1 địa chỉ cụ thể
        isLocked = _locked;
    }
    function setProcessor(address _processor) external onlyAdmin {
        beProcessor = _processor;
    }
    function setBackendPubKey(bytes calldata pubKey) external onlyAdmin {
        backendPubKey = pubKey;
    }

    function getBackendPubKey() external view returns (bytes memory) {
        return backendPubKey;
    }
    function setAdmin(address _admin, bool _setOK)external onlyOwner {
        isAdmin[_admin] = _setOK;
    }
    function setToken(address _token)external onlyOwner {
       token = _token;
    }
    /**
     * @notice Gửi yêu cầu cấp token với dữ liệu AES đã mã hóa
     * @param encryptedCardData Dữ liệu thẻ đã mã hóa
     * @param requestId ID duy nhất để theo dõi yêu cầu
     */
    function requestToken(bytes calldata encryptedCardData, bytes32 requestId) external onlyUnlocked {
        require(!userPending[msg.sender], "User has a pending request");

        userPending[msg.sender] = true;
        mUserToLastRequestId[msg.sender] = requestId;

        emit TokenRequest(msg.sender, encryptedCardData, requestId);
    }
    function getTokenIdByRequestId(bytes32 _requestId) external view returns(bytes32){
        bytes32 tokenId = mRequestIdTokenId[_requestId];
        require(tokens[tokenId].owner == msg.sender,"only card owner can call");
        return tokenId;
    }

    /**
     * @notice Off-chain submit token sau khi kiểm tra thành công
     * @param user Người sở hữu token
     * @param tokenId ID token
     * @param region Khu vực phát hành thẻ
     * @param requestId ID yêu cầu tương ứng
     * @param cardHash Hash duy nhất của số thẻ + thời gian hết hạn
     */
    function submitToken(
        address user,
        bytes32 tokenId,
        string calldata region,
        bytes32 requestId,
        bytes32 cardHash
    ) external onlyBEProcessor {
        require(userPending[user], "No pending request for user");
        CardToken storage tokenCard = tokens[tokenId];
        require(tokenCard.owner == address(0), "Token already exists");

        tokens[tokenId] = CardToken({
            owner: user,
            region: region,
            issuedAt: block.timestamp,
            isActive: true,
            totalUsage: 0,
            cardHash: cardHash
        });

        userTokens[user].push(tokenId);

        emit TokenIssued(user, tokenId, region, requestId, cardHash);
        userPending[user] = false;
        mRequestIdTokenId[requestId] = tokenId;
    }

    /**
     * @notice Off-chain gửi thông báo thất bại cấp token
     */
    function rejectToken(address user, bytes32 requestId, string calldata reason) external onlyBEProcessor {
        require(userPending[user], "No pending request for user");
        emit TokenFailed(user, requestId, reason);
        userPending[user] = false;
    }

    function setTokenActive(bytes32 tokenId, bool active) external onlyBEProcessor {
        // Có thể yêu cầu chỉ admin hoặc backend processor được quyền gọi
        require(tokens[tokenId].owner != address(0), "Invalid token");
        tokens[tokenId].isActive = active;
    }

    function getUserTokens(address user) external view returns (bytes32[] memory) {
        return userTokens[user];
    }
    /**
     * @notice Thực hiện yêu cầu thanh toán
     */
    function charge(bytes32 tokenId, address merchant, uint256 amount) external onlyUnlocked onlyTokenOwner(tokenId) returns(bool,string memory){
        require(merchant == msg.sender,"sender must be merchant if topup");
        require(amount > 0, "Amount must be greater than 0");
        require(tokenId != bytes32(0), "token empty");
        require(merchant != address(0), "token empty");

        // Time ranges
        uint256 minute = block.timestamp / 60;
        uint256 hour = block.timestamp / 3600;
        uint256 day = block.timestamp / 86400;
        uint256 week = block.timestamp / 604800;

        // MerchantRule storage rule = merchantRules[merchant];
        CardToken storage tokenCard = tokens[tokenId];
        bytes32 cardHash = tokenCard.cardHash;

        if (lockedCards[cardHash]) {
            emit ChargeRejected(msg.sender, tokenId, "Card is locked");
            return (false,"Card is locked");
        }


        // Global rule check cho token
        require(tokenUsagePerMinute[tokenId][minute] < smRule.maxPerMinute, "SM: token minute limit");
        require(tokenUsagePerHour[tokenId][hour] < smRule.maxPerHour, "SM: token hour limit");
        require(tokenUsagePerDay[tokenId][day] < smRule.maxPerDay, "SM: token day limit");
        require(tokenUsagePerWeek[tokenId][week] < smRule.maxPerWeek, "SM: token week limit");

        // Global rule check cho card
        require(cardUsagePerMinute[cardHash][minute] < smRule.maxPerMinute, "SM: card minute limit");
        require(cardUsagePerHour[cardHash][hour] < smRule.maxPerHour, "SM: card hour limit");
        require(cardUsagePerDay[cardHash][day] < smRule.maxPerDay, "SM: card day limit");
        require(cardUsagePerWeek[cardHash][week] < smRule.maxPerWeek, "SM: card week limit");
        
        require(tokens[tokenId].totalUsage < smRule.maxTotal, "SM: token max total");


        // Record usage
        if (tokenUsagePerMinute[tokenId][minute] == 0) {
            tokenUsageTimestamps[tokenId].push(minute);
        }
        tokenUsagePerMinute[tokenId][minute]++;
        tokenUsagePerHour[tokenId][hour]++;
        tokenUsagePerDay[tokenId][day]++;
        tokenUsagePerWeek[tokenId][week]++;
        tokens[tokenId].totalUsage++;

        if (cardUsagePerMinute[cardHash][minute] == 0) {
            cardUsageTimestamps[cardHash].push(minute);
        }
        cardUsagePerMinute[cardHash][minute]++;
        cardUsagePerHour[cardHash][hour]++;
        cardUsagePerDay[cardHash][day]++;
        cardUsagePerWeek[cardHash][week]++;

        if (recentToken[tokenId] == 0) {
            recentTokenList.push(tokenId);
        }
        recentToken[tokenId] = block.timestamp;

        if (recentCard[cardHash] == 0) {
            recentCardList.push(cardHash);
        }
        recentCard[cardHash] = block.timestamp;


        mTokenIdToLastTxID[tokenId] = "";
        emit ChargeRequest(msg.sender, tokenId, merchant, amount);
        return (true,"passed");
    }

    /**
     * @notice Thực hiện yêu cầu thanh toán
     */
    function chargeMerchant(bytes32 tokenId, address merchant, uint256 amount) external onlyUnlocked onlyTokenOwner(tokenId) returns(bool,string memory){
        require(amount > 0, "Amount must be greater than 0");
        require(tokenId != bytes32(0), "token empty");
        require(merchant != address(0), "token empty");

        // Time ranges
        uint256 minute = block.timestamp / 60;
        uint256 hour = block.timestamp / 3600;
        uint256 day = block.timestamp / 86400;
        uint256 week = block.timestamp / 604800;

        MerchantRule storage rule = merchantRules[merchant];
        CardToken storage tokenCard = tokens[tokenId];
        bytes32 cardHash = tokenCard.cardHash;

        if (lockedCards[cardHash]) {
            emit ChargeRejected(msg.sender, tokenId, "Card is locked");
            return (false,"Card is locked");
        }

        // Global rule check cho token
        require(tokenUsagePerMinute[tokenId][minute] < smRule.maxPerMinute, "SM: token minute limit");
        require(tokenUsagePerHour[tokenId][hour] < smRule.maxPerHour, "SM: token hour limit");
        require(tokenUsagePerDay[tokenId][day] < smRule.maxPerDay, "SM: token day limit");
        require(tokenUsagePerWeek[tokenId][week] < smRule.maxPerWeek, "SM: token week limit");

        // Global rule check cho card
        require(cardUsagePerMinute[cardHash][minute] < smRule.maxPerMinute, "SM: card minute limit");
        require(cardUsagePerHour[cardHash][hour] < smRule.maxPerHour, "SM: card hour limit");
        require(cardUsagePerDay[cardHash][day] < smRule.maxPerDay, "SM: card day limit");
        require(cardUsagePerWeek[cardHash][week] < smRule.maxPerWeek, "SM: card week limit");
        
        require(tokens[tokenId].totalUsage < smRule.maxTotal, "SM: token max total");


        // Check region
        if (!_regionAllowed(tokenCard.region, rule.allowedRegions)) {
            emit ChargeRejected(msg.sender, tokenId, "Region not allowed");
            return (false,"Region not allowed");
        }

        // Check token-level usage limits
        if (tokenUsagePerMinute[tokenId][minute] >= rule.maxPerMinute) {
            emit ChargeRejected(msg.sender, tokenId, "Max per minute exceeded");
            return (false,"Max per minute exceeded");
        }
        if (tokenUsagePerHour[tokenId][hour] >= rule.maxPerHour) {
            emit ChargeRejected(msg.sender, tokenId, "Max per hour exceeded");
            return (false,"Max per hour exceeded");
        }
        if (tokenUsagePerDay[tokenId][day] >= rule.maxPerDay) {
            emit ChargeRejected(msg.sender, tokenId, "Max per day exceeded");
            return (false,"Max per day exceeded");
        }
        if (tokenUsagePerWeek[tokenId][week] >= rule.maxPerWeek) {
            emit ChargeRejected(msg.sender, tokenId, "Max per week exceeded");
            return (false,"Max per week exceeded");
        }

        // Check card-level usage limits
        if (cardUsagePerMinute[cardHash][minute] >= rule.maxPerMinute) {
            emit ChargeRejected(msg.sender, tokenId, "Card max per minute exceeded");
            return (false,"Card max per minute exceeded");
        }
        if (cardUsagePerHour[cardHash][hour] >= rule.maxPerHour) {
            emit ChargeRejected(msg.sender, tokenId, "Card max per hour exceeded");
            return (false,"Card max per hour exceeded");
        }
        if (cardUsagePerDay[cardHash][day] >= rule.maxPerDay) {
            emit ChargeRejected(msg.sender, tokenId, "Card max per day exceeded");
            return (false,"Card max per day exceeded");
        }
        if (cardUsagePerWeek[cardHash][week] >= rule.maxPerWeek) {
            emit ChargeRejected(msg.sender, tokenId, "Card max per week exceeded");
            return (false,"Card max per week exceeded");
        }

        // Record usage
        if (tokenUsagePerMinute[tokenId][minute] == 0) {
            tokenUsageTimestamps[tokenId].push(minute);
        }
        tokenUsagePerMinute[tokenId][minute]++;
        tokenUsagePerHour[tokenId][hour]++;
        tokenUsagePerDay[tokenId][day]++;
        tokenUsagePerWeek[tokenId][week]++;
        tokens[tokenId].totalUsage++;

        if (cardUsagePerMinute[cardHash][minute] == 0) {
            cardUsageTimestamps[cardHash].push(minute);
        }
        cardUsagePerMinute[cardHash][minute]++;
        cardUsagePerHour[cardHash][hour]++;
        cardUsagePerDay[cardHash][day]++;
        cardUsagePerWeek[cardHash][week]++;

        if (recentToken[tokenId] == 0) {
            recentTokenList.push(tokenId);
        }
        recentToken[tokenId] = block.timestamp;

        if (recentCard[cardHash] == 0) {
            recentCardList.push(cardHash);
        }
        recentCard[cardHash] = block.timestamp;



        emit ChargeRequest(msg.sender, tokenId, merchant, amount);
        return (true,"passed");
    }

    function setGlobalRule(
        uint256 maxPerMinute,
        uint256 maxPerHour,
        uint256 maxPerDay,
        uint256 maxPerWeek,
        uint256 maxTotal
    ) external onlyAdmin {
        smRule = GlobalRule({
            maxPerMinute: maxPerMinute,
            maxPerHour: maxPerHour,
            maxPerDay: maxPerDay,
            maxPerWeek: maxPerWeek,
            maxTotal: maxTotal
        });
    }

    /**
     * @notice Cấu hình rule của merchant
     */
    function setMerchantRule(
        string[] calldata allowedRegions,
        uint256 maxPerMinute,
        uint256 maxPerHour,
        uint256 maxPerDay,
        uint256 maxPerWeek,
        address merchant
    ) external onlyAdmin {
        merchantRules[merchant] = MerchantRule({
            allowedRegions: allowedRegions,
            maxPerMinute: maxPerMinute,
            maxPerHour: maxPerHour,
            maxPerDay: maxPerDay,
            maxPerWeek: maxPerWeek
        });
    }

    function setCardLocked(bytes32 cardHash, bool locked) external onlyBEProcessor {
        if (!locked) {
            delete lockedCards[cardHash]; //false la mo khoa
        } else {
            lockedCards[cardHash] = locked; //true khoa
        }
    }


    // function cleanUsage(uint256 beforeTimestamp) external onlyAdmin {
    //     require(isLocked, "Must lock contract before cleaning");

    //     // Clean tokens
    //     for (uint256 i = 0; i < recentTokenList.length; i++) {
    //         bytes32 tokenId = recentTokenList[i];
    //         if (recentToken[tokenId] == 0 || recentToken[tokenId] >= beforeTimestamp) {
    //             continue;
    //         }

    //         // Xóa usage theo thời gian cũ
    //         _clearTokenUsage(tokenId, beforeTimestamp);
    //         delete recentToken[tokenId];
    //     }

    //     // Clean cardHash
    //     for (uint256 i = 0; i < recentCardList.length; i++) {
    //         bytes32 cardHash = recentCardList[i];
    //         if (recentCard[cardHash] == 0 || recentCard[cardHash] >= beforeTimestamp) {
    //             continue;
    //         }

    //         _clearCardUsage(cardHash, beforeTimestamp);
    //         delete recentCard[cardHash];
    //     }
        
    //     delete recentTokenList;
    //     delete recentToken;

    //     delete recentCardList;
    //     delete recentCard;
    // }
    function cleanUsage(uint256 beforeTimestamp) external onlyAdmin {
        require(isLocked, "Must lock contract before cleaning");

        // Clean tokens
        console.log("recentTokenList.length:",recentTokenList.length);
        for (uint256 i = 0; i < recentTokenList.length; i++) {
            
            bytes32 tokenId = recentTokenList[i];
            if (recentToken[tokenId] == 0 || recentToken[tokenId] >= beforeTimestamp) {
                console.log("ddddd:",recentToken[tokenId]);
                console.log("ccccc:",beforeTimestamp);
                continue;
            }

            // Xóa usage theo thời gian cũ
            _clearUsage(tokenUsageTimestamps[tokenId], tokenUsagePerMinute[tokenId], beforeTimestamp);
            _clearUsage(tokenUsageTimestamps[tokenId], tokenUsagePerHour[tokenId], beforeTimestamp * 60);
            _clearUsage(tokenUsageTimestamps[tokenId], tokenUsagePerDay[tokenId], beforeTimestamp * 1440);
            _clearUsage(tokenUsageTimestamps[tokenId], tokenUsagePerWeek[tokenId], beforeTimestamp * 10080);
            delete recentToken[tokenId];
        }

        // Clean cardHash
        for (uint256 i = 0; i < recentCardList.length; i++) {
            bytes32 cardHash = recentCardList[i];
            if (recentCard[cardHash] == 0 || recentCard[cardHash] >= beforeTimestamp) {
                continue;
            }

            _clearUsage(cardUsageTimestamps[cardHash], cardUsagePerMinute[cardHash], beforeTimestamp);
            _clearUsage(cardUsageTimestamps[cardHash], cardUsagePerHour[cardHash], beforeTimestamp * 60);
            _clearUsage(cardUsageTimestamps[cardHash], cardUsagePerDay[cardHash], beforeTimestamp * 1440);
            _clearUsage(cardUsageTimestamps[cardHash], cardUsagePerWeek[cardHash], beforeTimestamp * 10080);
            delete recentCard[cardHash];
        }
    }
    function _clearUsage(
        uint256[] storage timestamps,
        mapping(uint256 => uint256) storage usageMap,
        uint256 before
    ) internal {
        uint256 length = timestamps.length;
        console.log("length:",length);
        for (uint256 i = 0; i < length; ) {
            uint256 ts = timestamps[i];
            if (ts < before) {
                delete usageMap[ts];
                // delete usageMap[ts / 60];
                // Remove timestamp from array efficiently
                timestamps[i] = timestamps[length - 1];
                timestamps.pop();
                length--;
            } else {
                i++;
            }
        }
    }

    // ===== INTERNAL =====

    function _regionAllowed(string memory region, string[] storage allowedRegions) internal view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(region));
        for (uint256 i = 0; i < allowedRegions.length; i++) {
            if (keccak256(abi.encodePacked(allowedRegions[i])) == hash) {
                return true;
            }
        }
        return false;
    }

    // function _clearTokenUsage(bytes32 tokenId, uint256 beforeTimestamp) internal {
    //     uint256 cutoffMinute = beforeTimestamp / 60;
    //     uint256[] storage list = tokenUsageTimestamps[tokenId];
    //     for (uint256 i = 0; i < list.length; i++) {
    //         uint256 minute = list[i];
    //         if (minute < cutoffMinute) {
    //             delete tokenUsagePerMinute[tokenId][minute];
    //             delete tokenUsagePerHour[tokenId][minute / 60];
    //             delete tokenUsagePerDay[tokenId][minute / 1440];
    //             delete tokenUsagePerWeek[tokenId][minute / 10080];
    //         }
    //     }

    //     delete tokenUsageTimestamps[tokenId];

    // }

    function _clearCardUsage(bytes32 cardHash, uint256 beforeTimestamp) internal {
        uint256 cutoffMinute = beforeTimestamp / 60;
        uint256[] storage list = cardUsageTimestamps[cardHash];
        for (uint256 i = 0; i < list.length; i++) {
            uint256 minute = list[i];
            if (minute < cutoffMinute) {
                delete cardUsagePerMinute[cardHash][minute];
                delete cardUsagePerHour[cardHash][minute / 60];
                delete cardUsagePerDay[cardHash][minute / 1440];
                delete cardUsagePerWeek[cardHash][minute / 10080];
            }
        }

        delete cardUsageTimestamps[cardHash];
    }
    function getLastTxID(bytes32 tokenId) external view returns(string memory){
        return mTokenIdToLastTxID[tokenId];
    }
    function UpdateTxStatus(bytes32 tokenId,string memory txID,TxStatus status, uint64 atTime, string memory reason) external onlyBEProcessor {
        mTxIdToStatus[txID] = TransactionStatus({
            txID : txID,
            status : status,
            atTime : atTime,
            reason : reason
        });
        mTokenIdToLastTxID[tokenId] = txID;
        
    }
    function MintUTXO(uint256 parentValue,address ownerPool,string memory transactionID)external onlyAdmin returns (address newPool,bytes32 parentHash){
        parentHash = keccak256(abi.encodePacked(msg.sender, parentValue, block.timestamp, block.number));
        newPool = ULTRA_UTXO.mint(parentHash, parentValue, ownerPool, token);
        PoolInfo memory poolInfo = PoolInfo({
            ownerPool: ownerPool,
            parentHash: parentHash,
            pool: newPool,
            parentValue: parentValue
        });
        mTransactionIdToPoolInfo[transactionID] = poolInfo;
        return (newPool,parentHash);
    }
    function getPoolInfo(string memory _transactionID) external view returns(PoolInfo memory) {
        return mTransactionIdToPoolInfo[_transactionID];
    }

    function getTx(string memory txID)external view returns(TransactionStatus memory transaction){
        transaction =  mTxIdToStatus[txID];
        return transaction;
    } 
    
    function requestUpdateTxStatus(bytes32 tokenId, string memory txID) external {
        require(mTxIdToStatus[txID].status == TxStatus.BEING_PROCESSED,"only request at BEING_PROCESSED state");
        emit RequestUpdateTxStatus(txID,tokenId);
    }

}
