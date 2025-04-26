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
	"strings"
	"time"

	// "time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/meta-node-blockchain/noti-contract/internal/model"
)

func ValidateCard(card model.CardData) error {
	if len(card.ExpYear) != 4 {
		return fmt.Errorf("expireYear must be exactly 4 characters")
	}
	return nil
}
func SendToThirdParty(card model.CardData, amount *big.Int, merchant common.Address, thirdPartyApiUrl string) (model.TxResponse,error) {
    var result model.TxResponse
    if err := ValidateCard(card); err != nil {
        fmt.Println("Validation error:", err)
        return result,err
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
        CVV string `json:"cvv"`
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
        CVV : card.CVV,
    }

    // Chuyển thành JSON
    data, err := json.Marshal(payload)
    if err != nil {
        log.Printf("❌ JSON marshal thất bại: %v", err)
        return result,err
    }

    // Debug JSON nếu cần
    log.Printf("📤 JSON gửi đi: %s", string(data))

    // Tạo request
    req, err := http.NewRequest("POST", thirdPartyApiUrl, bytes.NewBuffer(data))
    if err != nil {
        log.Printf("❌ Tạo request thất bại: %v", err)
        return result,err
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
        return result,err
    }
    defer resp.Body.Close()

   // Đọc nội dung phản hồi
    body, err := io.ReadAll(resp.Body)
    if err != nil {
        log.Printf("❌ Không đọc được body phản hồi: %v", err)
        return result,err
    }
    log.Println("📨 transaction ID la:", payload.TxID)
    // In thử body để debug
    log.Println("📨 Raw response:", string(body))
    if strings.Contains(string(body), "success") {
        result = model.TxResponse{
            Message       :string(body),
            Status        :"success",
            TransactionID :payload.TxID,
        }
        return result,nil
    }else if strings.Contains(string(body), "being processed") {
        result = model.TxResponse{
            Message       :string(body),
            Status        :"being processed",
            TransactionID :payload.TxID,
        }
        return result,nil
    }else {
        err := json.Unmarshal(body, &result) 
        if err != nil{
            log.Println("❌ Không thể parse JSON:", err)
            result = model.TxResponse{
                Message       :string(body),
                Status        :"failed",
                TransactionID :payload.TxID,
            }
            return result,nil    
        }
        return result,nil
    }
    
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
func UpdateStatus(txID string) string {
    url := "https://payment-card.vipn.net/transaction/detail"
    payload := fmt.Sprintf(`{"tx_id":"%s","m_id":"pos123"}`, txID)

    req, err := http.NewRequest("POST", url, strings.NewReader(payload))
    if err != nil {
        log.Println("❌ Lỗi tạo request:", err)
        return ""
    }

    // Thêm đầy đủ các header như trình duyệt thật
    req.Header.Add("Content-Type", "application/json")
    req.Header.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
    req.Header.Add("Accept", "*/*")
    req.Header.Add("Accept-Language", "en-US,en;q=0.9")
    req.Header.Add("Origin", "https://payment-card.vipn.net")
    req.Header.Add("Referer", "https://payment-card.vipn.net/")
    req.Header.Add("Connection", "keep-alive")
    req.Header.Add("Sec-Fetch-Site", "same-origin")
    req.Header.Add("Sec-Fetch-Mode", "cors")
    req.Header.Add("Sec-Fetch-Dest", "empty")

    // Nếu đã login thủ công, có thể copy Cookie từ trình duyệt
    req.Header.Add("Cookie", "paste_cookies_here_if_needed")

    client := &http.Client{
        Timeout: 10 * time.Second,
    }

    res, err := client.Do(req)
    if err != nil {
        log.Println("❌ Lỗi gửi request:", err)
        return ""
    }
    defer res.Body.Close()

    body, err := io.ReadAll(res.Body)
    if err != nil {
        log.Println("❌ Lỗi đọc response:", err)
        return ""
    }

    log.Println("📥 Phản hồi trạng thái:", string(body))

    var result struct {
        Status string `json:"status"`
    }
    if err := json.Unmarshal(body, &result); err != nil {
        log.Println("❌ Không parse được status:", err)
        return ""
    }

    return result.Status
}

// func callSmartContractUpdate(txID, status string, atTime int64) {
//     // Gọi hàm trên smart contract để cập nhật trạng thái: success | failed
//     log.Printf("📡 Cập nhật trạng thái lên smart contract: %s = %s = %s \n", txID, status,atTime)
//     // TODO: Gọi contract thực tế bằng Go hoặc thông qua một package như go-ethereum
// }