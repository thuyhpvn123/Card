package main


// tạo abigen:
// abigen --contract CardTokenManager --pkg cardtokenmanager --out CardTokenManager.go
//
import (
    "bytes"
    "context"
    "crypto/ecdsa"
    "crypto/elliptic"
    "crypto/rand"
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "log"
    "math/big"
    "net/http"
    "os"
    "os/signal"
    // "strings"
    "syscall"

    "github.com/ethereum/go-ethereum"
    "github.com/ethereum/go-ethereum/accounts/abi/bind"
    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/core/types"
    "github.com/ethereum/go-ethereum/crypto"
    "github.com/ethereum/go-ethereum/ethclient"
    "github.com/syndtr/goleveldb/leveldb"
)

// Config cấu hình ứng dụng
type Config struct {
    PrivateKeyHex    string `json:"privateKeyHex"`
    RPCUrl           string `json:"rpcUrl"`
    ContractAddress  string `json:"contractAddress"`
    ThirdPartyApiUrl string `json:"thirdPartyApiUrl"`
}

// CardData chứa thông tin thẻ đã giải mã
type CardData struct {
    CardNumber string
    ExpMonth   string
    ExpYear    string
    CVV        string
}

var (
    config     Config
    client     *ethclient.Client
    contract   *CardTokenManager
    db         *leveldb.DB
    privateKey *ecdsa.PrivateKey
    publicKey  []byte
)

func main() {
    loadConfig()
    initBlockchain()
    verifyPublicKey()
    initLevelDB()
    defer db.Close()

    // Lắng nghe sự kiện
    go listenTokenRequests()
    go listenChargeRequests()

    // Chờ tín hiệu dừng
    stop := make(chan os.Signal, 1)
    signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
    <-stop

    log.Println("Dừng ứng dụng.")
}

func loadConfig() {
    file, err := os.Open("config.json")
    if err != nil {
        log.Fatalf("Không thể mở tệp cấu hình: %v", err)
    }
    defer file.Close()
    decoder := json.NewDecoder(file)
    err = decoder.Decode(&config)
    if err != nil {
        log.Fatalf("Không thể đọc tệp cấu hình: %v", err)
    }

    privateKeyBytes, err := hex.DecodeString(config.PrivateKeyHex)
    if err != nil {
        log.Fatalf("Khóa riêng tư không hợp lệ: %v", err)
    }
    privateKey, err = crypto.ToECDSA(privateKeyBytes)
    if err != nil {
        log.Fatalf("Không thể tạo khóa riêng tư: %v", err)
    }
    publicKey = elliptic.Marshal(elliptic.P256(), privateKey.PublicKey.X, privateKey.PublicKey.Y)
}

func initBlockchain() {
    var err error
    client, err = ethclient.Dial(config.RPCUrl)
    if err != nil {
        log.Fatalf("Không thể kết nối tới Ethereum RPC: %v", err)
    }

    contractAddress := common.HexToAddress(config.ContractAddress)
    contract, err = NewCardTokenManager(contractAddress, client)
    if err != nil {
        log.Fatalf("Không thể kết nối tới smart contract: %v", err)
    }
}

func verifyPublicKey() {
    storedPubKey, err := contract.GetBackendPubKey(&bind.CallOpts{})
    if err != nil {
        log.Fatalf("Không thể lấy khóa công khai từ smart contract: %v", err)
    }

    if !bytes.Equal(publicKey, storedPubKey) {
        log.Fatalf("Khóa công khai không khớp với smart contract.")
    }

    log.Println("Xác thực khóa công khai thành công.")
}

func initLevelDB() {
    var err error
    db, err = leveldb.OpenFile("leveldb", nil)
    if err != nil {
        log.Fatalf("Không thể mở LevelDB: %v", err)
    }
}

func listenTokenRequests() {

    query := ethereum.FilterQuery{
        Addresses: []common.Address{common.HexToAddress(config.ContractAddress)},
        Topics:    [][]common.Hash{{crypto.Keccak256Hash([]byte("TokenRequest(address,bytes,bytes32)"))}},

    }

    logs := make(chan types.Log)
    sub, err := client.SubscribeFilterLogs(context.Background(), query, logs)
    if err != nil {
        log.Fatalf("Không thể đăng ký lắng nghe sự kiện TokenRequest: %v", err)
    }

    for {
        select {
        case err := <-sub.Err():
            log.Fatalf("Lỗi khi lắng nghe sự kiện TokenRequest: %v", err)
        case vLog := <-logs:

            if len(vLog.Topics) < 2 {
                log.Printf("❌ Không đủ topic trong log")
                return
            }

            event := new(cardtokenmanager.CardTokenManagerTokenRequest)
            err := contract.UnpackLog(event, "TokenRequest", vLog)
            if err != nil {
                log.Printf("❌ Không decode được log TokenRequest: %v", err)
                return
            }
            go handleTokenRequest(event, db, privateKey)
        }
    }
}

func handleTokenRequest(event *cardtokenmanager.CardTokenManagerTokenRequest, db *leveldb.DB, backendPriv *ecdsa.PrivateKey) {
    log.Printf("🔐 TokenRequest from: %s", event.User.Hex())

    // Giả định encryptedCardData = userPubKey(65 byte) + encryptedData
    raw := event.EncryptedCardData
    userPubX, userPubY := elliptic.Unmarshal(elliptic.P256(), raw[:65])
    if userPubX == nil {
        log.Printf("❌ Invalid public key")
        return
    }
    sharedKey, err := deriveSharedKey(userPubX, userPubY, backendPriv)
    if err != nil {
        log.Printf("❌ ECDH failed: %v", err)
        return
    }

    // Decrypt card data
    plaintext, err := decryptAESGCM(sharedKey, raw[65:])
    if err != nil {
        log.Printf("❌ AES decrypt failed: %v", err)
        return
    }

    var card CardData
    if err := json.Unmarshal(plaintext, &card); err != nil {
        log.Printf("❌ JSON decode failed: %v", err)
        return
    }

    if !sendToThirdParty(card, big.NewInt(0), common.Address{}) {
        log.Printf("❌ Pre-charge failed")
        return
    }

    // Lưu thông tin đã mã hóa vào LevelDB (dùng requestId làm key)
    key := "token_" + event.RequestId.Hex()//sua thanh tokenid
    if err := db.Put([]byte(key), raw, nil); err != nil {
        log.Printf("❌ Save to DB failed: %v", err)
        return
    }
    log.Printf("✅ TokenRequest verified and saved")
}


func listenChargeRequests() {
    query := ethereum.FilterQuery{
        Addresses: []common.Address{common.HexToAddress(config.ContractAddress)},
        Topics:    [][]common.Hash{{crypto.Keccak256Hash([]byte("ChargeRequest(bytes32,address,address,uint256)"))}},
    }

    logs := make(chan types.Log)
    sub, err := client.SubscribeFilterLogs(context.Background(), query, logs)
    if err != nil {
        log.Fatalf("Không thể đăng ký lắng nghe sự kiện ChargeRequest: %v", err)
    }

    for {
        select {
        case err := <-sub.Err():
            log.Fatalf("Lỗi khi lắng nghe sự kiện ChargeRequest: %v", err)
        case vLog := <-logs:

            if len(vLog.Topics) < 2 {
                log.Printf("❌ Không đủ topic trong log")
                return
            }


            event := new(cardtokenmanager.CardTokenManagerChargeRequest)
            err := contract.UnpackLog(event, "TokenRequest", vLog)
            if err != nil {
                log.Printf("❌ Không decode được log TokenRequest: %v", err)
                return
            }
            go handleChargeRequest(event, db, privateKey)
        }
    }
}

func handleChargeRequest(event *cardtokenmanager.CardTokenManagerChargeRequest, db *leveldb.DB, backendPriv *ecdsa.PrivateKey) {
    log.Printf("💳 ChargeRequest: token=%x", event.TokenId[:6])

    key := "token_" + hex.EncodeToString(event.TokenId[:])
    raw, err := db.Get([]byte(key), nil)
    if err != nil {
        log.Printf("❌ Token not found in DB")
        return
    }

    // Unmarshal pubkey and decrypt
    userPubX, userPubY := elliptic.Unmarshal(elliptic.P256(), raw[:65])
    if userPubX == nil {
        log.Printf("❌ Invalid user pubkey")
        return
    }
    sharedKey, err := deriveSharedKey(userPubX, userPubY, backendPriv)
    if err != nil {
        log.Printf("❌ Derive shared key failed: %v", err)
        return
    }
    plaintext, err := decryptAESGCM(sharedKey, raw[65:])
    if err != nil {
        log.Printf("❌ Decrypt failed: %v", err)
        return
    }

    var card CardData
    if err := json.Unmarshal(plaintext, &card); err != nil {
        log.Printf("❌ Parse card failed: %v", err)
        return
    }
    if !sendToThirdParty(card, event.Amount, event.Merchant) {
        log.Printf("❌ Swipe API failed: %v", err)
        return
    }
    defer resp.Body.Close()

    log.Printf("✅ Swipe sent, status: %s", resp.Status)
}


func sendToThirdParty(card CardData, amount *big.Int, merchant common.Address) bool {
    payload := map[string]interface{}{
        "m_id":        "pos123",
        "tx_id":       generateTxID(),
        "card_number": card.CardNumber,
        "exp_date":    fmt.Sprintf("%s-%s", card.ExpYear, padLeft(card.ExpMonth, 2, "0")),
        "amount":      amount.Int64(),
        "wallet_to":   merchant.Hex()[2:], // loại bỏ "0x" prefix
        "fee_payer":   1,
    }

    data, _ := json.Marshal(payload)

    req, err := http.NewRequest("POST", config.ThirdPartyApiUrl, bytes.NewBuffer(data))
    if err != nil {
        log.Printf("❌ Tạo request thất bại: %v", err)
        return false
    }

    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")

    client := &http.Client{}
    resp, err := client.Do(req)
    if err != nil {
        log.Printf("❌ Gửi request thất bại: %v", err)
        return false
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        log.Printf("❌ Giao dịch bị từ chối, status: %s", resp.Status)
        return false
    }

    log.Println("✅ Giao dịch thành công.")
    return true
}

// === Crypto utils ===

func deriveSharedKey(pubX, pubY *big.Int, priv *ecdsa.PrivateKey) ([]byte, error) {
    if pubX == nil || pubY == nil || priv == nil {
        return nil, fmt.Errorf("invalid keys")
    }
    x, _ := elliptic.P256().ScalarMult(pubX, pubY, priv.D.Bytes())
    shared := sha256.Sum256(x.Bytes())
    return shared[:], nil
}

func encryptAESGCM(key []byte, plaintext []byte) ([]byte, error) {
    block, err := aes.NewCipher(key)
    if err != nil {
        return nil, err
    }
    gcm, err := cipher.NewGCM(block)
    if err != nil {
        return nil, err
    }
    nonce := make([]byte, gcm.NonceSize())
    rand.Read(nonce)
    ciphertext := gcm.Seal(nil, nonce, plaintext, nil)
    return append(nonce, ciphertext...), nil
}

func decryptAESGCM(key []byte, ciphertext []byte) ([]byte, error) {
    block, err := aes.NewCipher(key)
    if err != nil {
        return nil, err
    }
    gcm, err := cipher.NewGCM(block)
    if err != nil {
        return nil, err
    }
    nonce := ciphertext[:gcm.NonceSize()]
    return gcm.Open(nil, nonce, ciphertext[gcm.NonceSize():], nil)
}
