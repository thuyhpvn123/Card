package utils

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"

	"github.com/ethereum/go-ethereum/common"
	"github.com/meta-node-blockchain/noti-contract/internal/model"
)
func ValidateCard(card model.CardData) error {
	if len(card.ExpYear) != 4 {
		return fmt.Errorf("expireYear must be exactly 4 characters")
	}
	return nil
}
func SendToThirdParty(card model.CardData, amount *big.Int, merchant common.Address, thirdPartyApiUrl string) bool {
    fmt.Println("card.ExpYear:",card.ExpYear)
    if err := ValidateCard(card); err != nil {
        fmt.Println("Validation error:", err)
    }
    // Struct định nghĩa đúng định dạng JSONcard
    type Payload struct {
        MID        string `json:"m_id"`
        TxID       string `json:"tx_id"`
        CardNumber string `json:"card_number"`
        ExpDate    string `json:"exp_date"`
        Amount     int64  `json:"amount"`
        WalletTo   string `json:"wallet_to"`
        FeePayer   int    `json:"fee_payer"`
    }

    // Tạo payload
    payload := Payload{
        MID:        "pos123",
        TxID:       generateTxID(),
        CardNumber: card.CardNumber,
        ExpDate:    fmt.Sprintf("%s-%s", card.ExpYear, padLeft(card.ExpMonth, 2, "0")),
        Amount:     amount.Int64(),
        WalletTo:   merchant.Hex()[2:], // loại bỏ "0x"
        FeePayer:   1,
    }

    // Chuyển thành JSON
    data, err := json.Marshal(payload)
    if err != nil {
        log.Printf("❌ JSON marshal thất bại: %v", err)
        return false
    }

    // Debug JSON nếu cần
    log.Printf("📤 JSON gửi đi: %s", string(data))

    // Tạo request
    req, err := http.NewRequest("POST", thirdPartyApiUrl, bytes.NewBuffer(data))
    if err != nil {
        log.Printf("❌ Tạo request thất bại: %v", err)
        return false
    }

    // Set headers
    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
    req.Header.Set("Accept", "application/json")

    // Gửi request
    client := &http.Client{}
    resp, err := client.Do(req)
    if err != nil {
        log.Printf("❌ Gửi request thất bại: %v", err)
        return false
    }
    defer resp.Body.Close()

    // Đọc nội dung phản hồi
    body, _ := io.ReadAll(resp.Body)

    if resp.StatusCode != http.StatusOK {
        log.Printf("❌ Giao dịch bị từ chối, status: %s, body: %s", resp.Status, string(body))
        return false
    }

    log.Println("✅ Giao dịch thành công.")
    return true
}
// Pad helper
func padLeft(str string, length int, pad string) string {
    for len(str) < length {
        str = pad + str
    }
    return str
}

// Dummy tx generator
func generateTxID() string {
    b := make([]byte, 5) // 5 bytes = 10 hex digits
    _, _ = rand.Read(b)
    hexPart := hex.EncodeToString(b)

    // Cần thêm 1 ký tự nữa để đủ 11 ký tự
    extraByte := make([]byte, 1)
    _, _ = rand.Read(extraByte)
    hexPart += fmt.Sprintf("%x", extraByte[0])[:1]

    return "tx_" + hexPart // tổng 14 ký tự
}