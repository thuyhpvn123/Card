package utils

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"

	"github.com/ethereum/go-ethereum/common"
	"github.com/meta-node-blockchain/noti-contract/internal/model"

)
func SendToThirdParty(card model.CardData, amount *big.Int, merchant common.Address, thirdPartyApiUrl string) bool {
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

    req, err := http.NewRequest("POST", thirdPartyApiUrl, bytes.NewBuffer(data))
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
// Pad helper
func padLeft(str string, length int, pad string) string {
    for len(str) < length {
        str = pad + str
    }
    return str
}

// Dummy tx generator
func generateTxID() string {
    return "tx_123456789"
}