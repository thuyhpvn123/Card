// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/console.sol";
/**
 * @title Smart Contract mô phỏng hệ thống séc chuyển nhượng ẩn danh trên blockchain
 * @notice Hỗ trợ hai cơ chế séc: có người nhận và không người nhận
 *
 * === THUẬT TOÁN ===
 *
 * Bước 1: Gửi tiền và tạo danh sách séc:
 * - Người gửi (A) gửi tiền vào smart contract.
 * - A tạo nhiều cặp khóa ngẫu nhiên (priv/pub key) và gửi hash của pubKey cùng với số tiền lên contract.
 * - Contract lưu lại danh sách hash pubKey và số tiền tối đa có thể dùng cho mỗi pubKey (mỗi séc).
 *
 * Bước 2: Ký và chuyển nhượng séc (offline):
 *
 * Cách 1: Séc có người nhận - hỗ trợ chuyển nhượng từng phần
 * - A ký một séc cho một địa chỉ ngẫu nhiên do B tạo, chỉ rõ địa chỉ B là người nhận và số tiền.
 * - B có thể ký lại séc đó để chuyển tiếp một phần cho C bằng địa chỉ mới do C tạo.
 * - Khi C muốn rút tiền, C cần trình chuỗi các chữ ký từ A → B → C.
 * - Không cần cơ chế chống front-run vì thông tin người nhận đã được cố định ở mỗi bước.
 *
 * Cách 2: Séc không có người nhận - hỗ trợ chuyển nhượng toàn phần
 * - A ký séc không chỉ rõ người nhận, bất kỳ ai có séc đều có thể nhận toàn bộ giá trị.
 * - Khi người dùng cuối (C) muốn rút tiền, cần đăng ký ý định trước với contract bằng postClaimIntent.
 * - Sau một khoảng thời gian an toàn (ví dụ 5 giây), C mới có thể gọi claimCheque để rút tiền.
 * - Điều này ngăn chặn front-run nơi một node mạng có thể lấy chữ ký của A và nộp trước C.
 *
 * Bước 3: Rút tiền:
 * - Người nhận cung cấp chuỗi chữ ký chuyển nhượng hợp lệ.
 * - Contract kiểm tra toàn bộ chuỗi pubKeyHash, chữ ký, và trạng thái séc.
 * - Nếu hợp lệ, số tiền được chuyển và trạng thái séc cuối cùng được đánh dấu đã dùng.
 *
 * Hủy séc:
 * - A có thể gọi reclaim để đánh dấu séc sẽ huỷ.
 * - Sau 72 giờ, A có thể rút lại tiền nếu séc chưa bị sử dụng.
 */
contract SecureCheque {
    enum ChequeStatus { Unused, Used, Reclaimed }

    struct Cheque {
        address creator;           // Người tạo séc
        bytes32 pubKeyHash;        // Hash của public key dùng để xác minh chữ ký
        uint256 maxAmount;         // Số tiền tối đa có thể rút từ séc này
        uint256 reclaimTime;       // Thời điểm yêu cầu reclaim
        ChequeStatus status;        // Trạng thái của séc
        bytes offchainSig;         // Chữ ký từ hệ thống offchain để xác thực séc hợp lệ
    }

    struct WithdrawalIntent {
        bytes32 initialSigHash;    // Hash của chữ ký khởi tạo để xác minh
        uint256 timestamp;         // Thời gian gửi intent
    }

    uint256 public reclaimDelay = 72 hours;             // Thời gian chờ reclaim
    uint256 public frontRunWindow = 3 seconds;          // Thời gian chờ xác nhận intent

    mapping(bytes32 => Cheque) public cheques;            // Lưu trữ thông tin séc bởi pubKeyHash
    mapping(address => WithdrawalIntent) public intents;// Lưu trữ intent theo địa chỉ người rút

    mapping(address => uint256) public balances;// Lưu trữ balances


    event ChequesBatchRegistered(bytes32[] pubKeyHashes, uint256 amount);
    event IntentRegistered(bytes32 indexed initialSigHash, address indexed recipient);
    event ChequeClaimed(address indexed by, uint256 amount);
    event ChequeReclaimRequested(bytes32 indexed pubKeyHash, uint256 reclaimTime);
    event ChequeReclaimed(address indexed by, uint256 amount);

    receive() external payable {}

    address private owner;
    address private trustedSigner;

    // Đảm bảo chỉ có owner mới có thể gọi một số hàm đặc biệt
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier onlySigner() {
        require(msg.sender == trustedSigner, "Not authorized");
        _;
    }

    // Constructor thiết lập chủ sở hữu hợp đồng
    constructor() {
        owner = msg.sender; // Người triển khai hợp đồng sẽ là owner
    }

    function setTrustedSigner(address signer) external onlyOwner {
        trustedSigner = signer;
    }

    /**
     * @notice Đăng ký batch séc mới
     * @param receiverHashes Mảng các hash của public key // là mảng hash của địa chỉ ví những người nhận chứ ko phải publickey
     * @param amount Giá trị của mỗi séc
     */
    function registerCheques(bytes32[] calldata receiverHashes, uint256 amount) external payable {
        uint256 total = amount * receiverHashes.length;
        require(amount > 0, "Incorrect amount");
        // require(total < 100, "Incorrect total");
        require(total < 100 *10**18, "Incorrect total");
        require(msg.value == total, "Incorrect total amount");

        for (uint256 i = 0; i < receiverHashes.length; i++) {
            bytes32 hash = receiverHashes[i];
            // require(cheques[hash].creator == address(0), "Already exists");
            cheques[hash] = Cheque(msg.sender, hash, amount, 0, ChequeStatus.Unused, "");
        }

        emit ChequesBatchRegistered(receiverHashes, amount);
    }

     /**
     * @notice Golang (offchain signer) gửi chữ ký xác thực pubKeyHash
     * @dev Đảm bảo chỉ admin hoặc trusted signer được phép gọi
     * @param pubKeyHashes Danh sách các hash của public key
     * @param signatures Danh sách chữ ký ECDSA cho từng pubKeyHash
     */
    function uploadOffchainSignatures(
        bytes32[] calldata pubKeyHashes,
        bytes[] calldata signatures
    ) external onlySigner {
        require(pubKeyHashes.length == signatures.length, "Length mismatch");
        for (uint256 i = 0; i < pubKeyHashes.length; i++) {
            require(cheques[pubKeyHashes[i]].maxAmount > 0, "Invalid cheque");
            require(bytes(cheques[pubKeyHashes[i]].offchainSig).length == 0, "Invalid cheque");
            cheques[pubKeyHashes[i]].offchainSig = signatures[i];
        }
    }

    /**
     * @notice Gửi ý định rút tiền trước, tránh tấn công front-run (chỉ áp dụng cho séc không có người nhận)
     * @param initialSigHash Hash của chữ ký đầu tiên trong chuỗi
     */
    function postClaimIntent(bytes32 initialSigHash) external {
        require(intents[msg.sender].timestamp == 0, "Intent already exists");
        intents[msg.sender] = WithdrawalIntent(initialSigHash, block.timestamp);
        emit IntentRegistered(initialSigHash, msg.sender);
    }
    
    function clearClaimIntent() external {
        delete intents[msg.sender];
    }

    struct TransferStep {
        address to;
        uint256 nextAmount;
        bytes signature;
    }

    /**
    * @notice Cho phép người nhận yêu cầu một séc bằng cách xác thực và xử lý một chuỗi các bước chuyển nhượng.
    * Hàm này xác minh chữ ký ban đầu và tùy chọn xử lý một chuỗi các bước chuyển nhượng, mỗi bước chuyển nhượng một phần số tiền của séc đến một người nhận mới.
    * Người nhận cuối cùng sẽ nhận được số tiền còn lại sau khi tất cả các bước chuyển nhượng đã được xử lý.
    *
    * @dev Hàm này sử dụng chữ ký ban đầu (`sigInitial`) để xác minh nguồn gốc của séc và kiểm tra từng bước trong chuỗi chuyển nhượng có chữ ký hợp lệ.
    * Mỗi bước phải bao gồm một chữ ký hợp lệ tương ứng với người nhận trước đó và số tiền chính xác. Sau khi tất cả các bước chuyển nhượng được xử lý, người nhận cuối cùng sẽ nhận được số tiền còn lại.
    * Trạng thái của séc được đánh dấu là "Đã sử dụng" để ngăn ngừa việc yêu cầu lại séc.
    * Các điều kiện cần phải thoả mãn trước khi hàm có thể thực thi:
    *   - Mảng `transferSteps` không được vượt quá 10 bước.
    *   - Tổng số tiền yêu cầu (`amountInitial`) không được vượt quá số tiền tối đa cho phép của séc.
    *   - Chữ ký ban đầu (`sigInitial`) phải khớp với hash tính toán từ người gửi và `amountInitial`.
    *   - Nếu `transferSteps` rỗng, phải xác minh intent (đảm bảo intent đã được tạo và chờ đợi đủ lâu).
    *   - Mỗi bước chuyển nhượng phải có chữ ký hợp lệ và khớp với người nhận trước đó.
    *   - Người nhận cuối cùng sẽ nhận được số tiền còn lại.
    *   - Trạng thái của séc sẽ được cập nhật thành "Đã sử dụng" sau khi séc được yêu cầu thành công.
    *   - Số tiền chưa sử dụng của séc sẽ được hoàn lại cho người phát hành.
    *
    * @param transferSteps Một mảng các `TransferStep` structs, mỗi struct đại diện cho một bước chuyển nhượng trong chuỗi. 
    *                      Mỗi struct bao gồm:
    *                      - `to` (address): Người nhận chuyển nhượng.
    *                      - `nextAmount` (uint256): Số tiền được chuyển trong bước này.
    *                      - `signature` (bytes): Chữ ký của người gửi chuyển nhượng, xác nhận tính hợp lệ của bước chuyển nhượng.
    * @param amountInitial Số tiền ban đầu của séc. Đây là số tiền tối đa có thể yêu cầu hoặc chuyển nhượng.
    * @param sigInitial Chữ ký ban đầu xác nhận nguồn gốc của séc. Dùng để xác minh người phát hành séc.
    *
    * @dev Sự kiện `ChequeClaimed` sẽ được phát ra khi séc được yêu cầu thành công.
    */
    function claimCheque(
        TransferStep[] calldata transferSteps, // Chuyển một array của struct vào
        uint256 amountInitial,
        bytes calldata sigInitial
    ) external {
        require(
            transferSteps.length < 10,
            "Too many steps"
        );

        // ======= STEP 1: Tính hash để kiểm tra sigInitial =========
        bytes32 initialHash;
        if (transferSteps.length == 0) {
            initialHash = keccak256(abi.encodePacked(msg.sender, amountInitial));
        } else {
            initialHash = keccak256(abi.encodePacked(address(0), transferSteps[0].to, amountInitial));
        }

        // ======= STEP 2: Phục hồi người phát hành gốc từ sigInitial =========
        address initialSigner = recoverSigner(initialHash, sigInitial);
        bytes32 firstPubKeyHash = keccak256(abi.encodePacked(initialSigner));

        // ======= STEP 3: Kiểm tra trạng thái của séc =========
        Cheque storage cheque = cheques[firstPubKeyHash];
        require(cheque.status == ChequeStatus.Unused, "Cheque already used or canceled");
        require(amountInitial <= cheque.maxAmount, "Amount exceeds cheque max");

        // ======= STEP 4: Xác minh intent nếu không có chuyển nhượng =========
        if (transferSteps.length == 0) {
            // ======= STEP 4.1: Xử lý chuỗi không có chuyển nhượng =========
            WithdrawalIntent memory intent = intents[msg.sender];
            require(intent.timestamp != 0, "Missing intent");
            require(block.timestamp - intent.timestamp >= frontRunWindow, "Intent not matured");
            require(intent.initialSigHash == keccak256(sigInitial), "Initial signature mismatch");

            balances[msg.sender] += amountInitial;
        } else {
            // ======= STEP 4.2: Xử lý chuỗi có chuyển nhượng =========
            address prevAddr = address(0);
            uint256 remainingAmount = amountInitial;

            for (uint256 i = 0; i < transferSteps.length; i++) {
                TransferStep memory step = transferSteps[i];

                // Xử lý từng bước chuyển nhượng
                uint256 nextAmount = step.nextAmount;
                require(nextAmount <= remainingAmount, "Transfer exceeds current amount");

                bytes32 msgHash = keccak256(abi.encodePacked(prevAddr, step.to, nextAmount));
                address signer = recoverSigner(msgHash, step.signature);
                bytes32 pubKeyHash = keccak256(abi.encodePacked(signer));

                // Bước đầu tiên: xác minh chữ ký khớp pubKeyHash gốc
                if (i == 0) {
                    require(pubKeyHash == firstPubKeyHash, "Initial pubKeyHash mismatch");
                } else {
                    require(signer == prevAddr, "Signer must match previous recipient");
                }

                // Ghi nhận phần dư cho người chuyển nhượng
                uint256 transferRemainder = remainingAmount - nextAmount;
                if (transferRemainder > 0) {
                    balances[signer] += transferRemainder;
                }

                remainingAmount = nextAmount;
                prevAddr = step.to;
            }
            // Cuối cùng, người nhận nhận được currentAmount
            balances[msg.sender] += remainingAmount;
        }

        // ======= STEP 6: Đánh dấu séc gốc đã được dùng =========
        cheque.status = ChequeStatus.Used;

        // ======= STEP 7: Ghi nhận phần dư cuối cùng cho người cuối trong chuỗi =========
        uint256 refundAmount = cheque.maxAmount - amountInitial;

        if (refundAmount > 0) {
            balances[cheque.creator] += refundAmount;
        }

        emit ChequeClaimed(msg.sender, amountInitial);
    }

    function redeem(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Not the owner");

        balances[msg.sender] -= amount;

        payable(msg.sender).transfer(amount);

    }


    /**
     * @notice Gửi yêu cầu reclaim lại séc chưa dùng
     * @param pubKeyHashes Danh sách các pubKeyHash tương ứng với các séc
     */
    function requestReclaim(bytes32[] calldata pubKeyHashes) external {
        for (uint256 i = 0; i < pubKeyHashes.length; i++) {
            bytes32 pubKeyHash = pubKeyHashes[i];
            Cheque storage c = cheques[pubKeyHash];
            require(c.creator == msg.sender, "Not the owner");
            require(c.status == ChequeStatus.Unused, "Cannot reclaim");
            require(c.reclaimTime == 0, "Already requested");

            c.reclaimTime = block.timestamp;
            emit ChequeReclaimRequested(pubKeyHash, c.reclaimTime);
        }
    }

    /**
     * @notice Thực hiện hoàn tiền séc sau khi đã yêu cầu reclaim và chờ đủ 72 giờ
     * @param pubKeyHashes Danh sách các hash của public key liên kết với séc cần reclaim
     * @param signatures Danh sách chữ ký xác nhận reclaim từ người tạo tương ứng với mỗi pubKeyHash
     */
    function executeReclaim(bytes32[] calldata pubKeyHashes, bytes[] calldata signatures) external {
        require(pubKeyHashes.length == signatures.length, "Length mismatch");

        for (uint256 i = 0; i < pubKeyHashes.length; i++) {
            bytes32 pubKeyHash = pubKeyHashes[i];
            Cheque storage c = cheques[pubKeyHash];
            require(c.creator == msg.sender, "Not the owner");
            require(c.status == ChequeStatus.Unused, "Cheque cannot be reclaimed");
            require(c.reclaimTime > 0, "Reclaim not requested");
            require(block.timestamp >= c.reclaimTime + reclaimDelay, "Reclaim time not elapsed");

            bytes32 reclaimHash = keccak256(abi.encodePacked(pubKeyHash, "reclaim"));
            address signerAddr = recoverSigner(reclaimHash, signatures[i]);
            require(signerAddr == msg.sender, "Invalid signature");

            c.status = ChequeStatus.Reclaimed;

            balances[msg.sender] += c.maxAmount;

            emit ChequeReclaimed(msg.sender, c.maxAmount);
        }
    }

    /**
     * @notice Khôi phục địa chỉ ký từ chữ ký ECDSA
     */
    // function recoverSigner(bytes32 messageHash, bytes memory signature) public pure returns (address) {
    //     bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    //     (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
    //     return ecrecover(ethSignedMessageHash, v, r, s);
    // }

    // /**
    //  * @notice Tách r, s, v từ signature chuẩn ECDSA
    //  */
    // function splitSignature(bytes memory sig) public pure returns (bytes32 r, bytes32 s, uint8 v) {
    //     require(sig.length == 65, "Incorrect signature format");
    //     assembly {
    //         r := mload(add(sig, 32))
    //         s := mload(add(sig, 64))
    //         v := byte(0, mload(add(sig, 96)))
    //     }
    // }
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
