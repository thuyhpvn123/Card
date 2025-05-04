package network

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"strings"

	// "strings"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	e_common "github.com/ethereum/go-ethereum/common"
	"github.com/meta-node-blockchain/meta-node/pkg/logger"
	"github.com/meta-node-blockchain/noti-contract/internal/config"
	"github.com/meta-node-blockchain/noti-contract/internal/database"
	"github.com/meta-node-blockchain/noti-contract/internal/model"
	"github.com/meta-node-blockchain/noti-contract/internal/services"
	"github.com/meta-node-blockchain/noti-contract/internal/utils"
	"github.com/syndtr/goleveldb/leveldb"
)

type CardHandler struct {
	config           *config.AppConfig
	service          services.SendTransactionService
	cardABI          *abi.ABI
	ServerPrivateKey string
	DB               *leveldb.DB
	thirdPartyURL    string
	storedPubKey     string
	eventChan        chan model.EventLog
	cancelMonitors   map[string]context.CancelFunc
	cancelMu         sync.Mutex
}

func NewCardEventHandler(
	config *config.AppConfig,
	service services.SendTransactionService,
	cardABI *abi.ABI,
	ServerPrivateKey string,
	DB *leveldb.DB,
	thirdPartyURL string,
	storedPubKey string,
	eventChan chan model.EventLog,
) *CardHandler {
	return &CardHandler{
		config:           config,
		service:          service,
		cardABI:          cardABI,
		ServerPrivateKey: ServerPrivateKey,
		DB:               DB,
		thirdPartyURL:    thirdPartyURL,
		storedPubKey:     storedPubKey,
		eventChan:        eventChan,
		cancelMonitors:   make(map[string]context.CancelFunc),
	}
}
// func (h *CardHandler) GetPoolInfo() {
// 	kq, err := h.service.GetPoolInfo("tx_afbc7147acc")
// 	if err != nil {
// 		logger.Error("GetPoolInfo fail: %v", err)
// 		return
// 	}
// 	fmt.Println("GetPoolInfo:",kq)
// }

func (h *CardHandler) VerifyPublicKey() {
	serverPubKey, err := h.service.CallVerifyPublicKey()
	if err != nil {
		logger.Error("Không thể lấy khóa công khai từ smart contract: %v", err)
		return
	}
	storedPubKeyBytes, err := hex.DecodeString(h.storedPubKey)
	serverPubKeyBytes, ok := serverPubKey.([]byte)
	if !ok {
		logger.Error("Error when parse server PubKey.")
		return
	}
	if !bytes.Equal(serverPubKeyBytes, storedPubKeyBytes) {
		logger.Error("Khóa công khai không khớp với smart contract.")
		return
	}

	logger.Info("Xác thực khóa công khai thành công.")
}
func (h *CardHandler) ListenEvents() {
	go func() {
		logger.Info("⏳ Start listening for new events...")

		rpcURL := h.config.RpcURL
		contractAddress := h.config.CardAddress

		// Đọc ABI
		abiBytes, err := os.ReadFile(h.config.CardABIPath)
		if err != nil {
			logger.Error("Error reading ABI file:", err)
			return
		}
		abiJSON := string(abiBytes)

		// Lấy topic0 cho TokenRequest và ChargeRequest
		tokenRequestTopic, err := utils.GetTopic0FromABI(abiJSON, "TokenRequest")
		if err != nil {
			logger.Error("Error getting TokenRequest topic0:", err)
			return
		}
		chargeRequestTopic, err := utils.GetTopic0FromABI(abiJSON, "ChargeRequest")
		if err != nil {
			logger.Error("Error getting ChargeRequest topic0:", err)
			return
		}
		chargeRejectedTopic, err := utils.GetTopic0FromABI(abiJSON, "ChargeRejected")
		if err != nil {
			logger.Error("Error getting ChargeRejected topic0:", err)
			return
		}

		var lastBlock string

		for {
			select {
			default:
				// Lấy latest block
				block, err := utils.GetLatestBlockNumber(rpcURL)
				if err != nil {
					logger.Error("Failed to get latest block:", err)
					time.Sleep(2 * time.Second)
					continue
				}

				if block == lastBlock {
					time.Sleep(1 * time.Second)
					continue
				}
				lastBlock = block

				// Lặp qua từng topic để lấy log
				topics := []string{tokenRequestTopic, chargeRequestTopic, chargeRejectedTopic}
				for _, topic := range topics {
					logs, err := utils.GetLogs(rpcURL, block, block, contractAddress, topic)
					if err != nil {
						logger.Error("Error fetching logs for topic", topic, ":", err)
						time.Sleep(1 * time.Second)
						continue
					}

					for _, raw := range logs {
						var log model.EventLog
						if err := json.Unmarshal(raw, &log); err != nil {
							logger.Warn("Cannot decode event log:", err)
							continue
						}
						h.eventChan <- log
					}
				}

				time.Sleep(1 * time.Second)
			}
		}
	}()
}

func (h *CardHandler) HandleConnectSmartContract(event model.EventLog) {
	fmt.Println("event la:", event)
	switch event.Topics[0] {
	case h.cardABI.Events["TokenRequest"].ID.String():
		h.handleTokenRequest(event.Data)
	case h.cardABI.Events["ChargeRequest"].ID.String():
		h.handleChargeRequest(event.Data)
	case h.cardABI.Events["ChargeRejected"].ID.String():
		h.handleChargeRejected(event.Data)
	case h.cardABI.Events["RequestUpdateTxStatus"].ID.String():
		h.handleRequestUpdateTxStatus(event.Data)
	}

}
func (h *CardHandler) handleRequestUpdateTxStatus(data string) {
	fmt.Println("handleRequestUpdateTxStatus")
	result := make(map[string]interface{})
	err := h.cardABI.UnpackIntoMap(result, "RequestUpdateTxStatus", e_common.FromHex(data))
	if err != nil {
		logger.Error("can't unpack to map", err)
		return
	}
	txID, ok := result["transactionID"].(string)
	if !ok {
		logger.Error("fail in parse transactionID RequestUpdateTxStatus :", err)
		return
	}
	tokenId, ok := result["tokenId"].([32]byte)
	if !ok {
		logger.Error("fail in parse tokenId RequestUpdateTxStatus:", err)
		return
	}
	h.cancelMu.Lock()
	if cancel, ok := h.cancelMonitors[txID]; ok {
		cancel()
		delete(h.cancelMonitors, txID)
		logger.Info("✋ Đã yêu cầu dừng monitor giao dịch:", txID)
	}
	h.cancelMu.Unlock()
	kq, err := h.service.GetTx(txID)
	if err != nil {
		logger.Error("fail in GetTx", err)
		return
	}
	tx, ok := kq.(map[string]interface{})
	if !ok {
		logger.Error("Error when parse GetTx.")
		return
	}
	status, ok := tx["status"].(uint8)
	if !ok {
		logger.Error("Error when parse status handleRequestUpdateTxStatus.")
		return
	}
	reason, ok := tx["reason"].(string)
	if !ok {
		logger.Error("Error when parse reason handleRequestUpdateTxStatus.")
		return
	}

	if status == 1 {
		statusQuery := utils.UpdateStatus(txID)
		atTime := time.Now().Unix()
		if statusQuery == "success" {
			h.service.UpdateTxStatus(tokenId, txID, 2, uint64(atTime), "success")
			return
		} else {
			h.service.UpdateTxStatus(tokenId, txID, status, uint64(atTime), reason)
			return
		}
	}
}
func (h *CardHandler) handleChargeRejected(data string) {
	fmt.Println("handleChargeRejected")
	result := make(map[string]interface{})
	err := h.cardABI.UnpackIntoMap(result, "ChargeRejected", e_common.FromHex(data))
	if err != nil {
		logger.Error("can't unpack to map", err)
		return
	}
	user, ok := result["user"].(common.Address)
	if !ok {
		logger.Error("fail in parse user ChargeRejected :", err)
		return
	}
	fmt.Println("handleChargeRejected user:", user)
	tokenId, ok := result["tokenId"].([32]byte)
	if !ok {
		logger.Error("fail in parse tokenId ChargeRejected:", err)
		return
	}
	reason, ok := result["reason"].(string)
	if !ok {
		logger.Error("fail in parse reason ChargeRejected:", err)
		return
	}
	kq := map[string]interface{}{
		"user":    user,
		"tokenid": tokenId,
		"reason":  reason,
	}
	logger.Info("ChargeRejected:", kq)

}
func (h *CardHandler) handleTokenRequest(data string) {
	fmt.Println("handleTokenRequest")
	result := make(map[string]interface{})
	err := h.cardABI.UnpackIntoMap(result, "TokenRequest", e_common.FromHex(data))
	if err != nil {
		logger.Error("can't unpack to map", err)
		return
	}
	// Convert HEX string to bytes
	serverPrivateKeyBytes, err := hex.DecodeString(h.ServerPrivateKey)
	if err != nil {
		logger.Error("Lỗi giải mã HEX: %v", err)
		return
	}
	encryptedCardData, ok := result["encryptedCardData"].([]byte)
	if !ok {
		logger.Error("fail in parse encryptedCardData :", err)
		return
	}
	fmt.Println("encryptedCardData:", hex.EncodeToString(encryptedCardData))
	encyptedCard := encryptedCardData[65:]
	clientPublicKey := encryptedCardData[:65]
	fmt.Println("clientPublicKey:", hex.EncodeToString(clientPublicKey))
	fmt.Println("encyptedCard:", hex.EncodeToString(encyptedCard[16:]))
	iv := encyptedCard[:16]
	fmt.Println("iv la:", hex.EncodeToString(iv))

	token, err := utils.DecryptAESCBC(encyptedCard[16:], serverPrivateKeyBytes, clientPublicKey, iv)
	if err != nil {
		logger.Error("fail in decrypt token:", err)
		return
	}
	var card model.CardData
	if err := json.Unmarshal(token, &card); err != nil {
		logger.Error("❌ Parse card failed: %v", err)
		return
	}
	fmt.Println("card:", card)
	fmt.Println("expire year request:", card.ExpYear)
	fmt.Println("user la :", result["user"])
	fmt.Printf("type %v", result["user"])
	user, ok := result["user"].(common.Address)
	if !ok {
		logger.Error("fail in parse user:", err)
		return
	}
	requestId, ok := result["requestId"].([32]byte)
	if !ok {
		logger.Error("fail in parse requestId:", err)
		return
	}
	fmt.Println("requestId la:", hex.EncodeToString(requestId[:]))
	tokenId := utils.GenerateTokenID()
	fmt.Println("tokenId la:", hex.EncodeToString(tokenId[:]))
	cardHash := sha256.Sum256([]byte(card.CardNumber + card.ExpMonth + card.ExpYear))

	//api get region bo sung sau
	region := "VN"
	kq, err := h.service.SubmitToken(user, tokenId, region, requestId, cardHash)
	if err != nil {
		logger.Error("fail in SubmitToken:", err)
		return
	}
	kq1, ok := kq.(bool)
	if ok && kq1 {
		callmap := map[string]interface{}{
			"key":  "token_" + hex.EncodeToString(tokenId[:]),
			"data": string(encryptedCardData),
		}
		err = database.WriteValueStorage(callmap, h.DB)
		if err != nil {
			logger.Error("fail in save in leveldb handleTokenRequest:", err)
			return
		}
		logger.Info("Saved token in db")
	}

}

func (h *CardHandler) handleChargeRequest(data string) {
	start := time.Now() 
	fmt.Println("handleChargeRequest")
	result := make(map[string]interface{})
	err := h.cardABI.UnpackIntoMap(result, "ChargeRequest", e_common.FromHex(data))
	if err != nil {
		logger.Error("can't unpack to map", err)
		return
	}
	tokenId, ok := result["tokenId"].([32]byte)
	if !ok {
		logger.Error("fail in parse tokenId:", err)
		return
	}
	callmap := map[string]interface{}{
		"key": "token_" + hex.EncodeToString(tokenId[:]),
	}
	encryptedCardData, err := database.ReadValueStorage(callmap, h.DB)
	if err != nil {
		logger.Error("fail in get encryptedCardData in db:", err)
		return
	}
	fmt.Println("encryptedCardData charge la:", string(encryptedCardData))
	// Convert HEX string to bytes
	serverPrivateKeyBytes, err := hex.DecodeString(h.ServerPrivateKey)
	if err != nil {
		logger.Error("Lỗi giải mã HEX: %v", err)
		return
	}
	encyptedCard := encryptedCardData[65:]
	clientPublicKey := encryptedCardData[:65]
	iv := encyptedCard[:16]
	token, err := utils.DecryptAESCBC(encyptedCard[16:], serverPrivateKeyBytes, clientPublicKey, iv)
	if err != nil {
		logger.Error("fail in decrypt token ChargeRequest:", err)
		return
	}
	var card model.CardData
	if err := json.Unmarshal(token, &card); err != nil {
		logger.Error("❌ Parse card failed: %v", err)
		return
	}
	fmt.Println("card.CVV:", card.CVV)
	amount, ok := result["amount"].(*big.Int)
	if !ok {
		logger.Error("fail in parse amount:", err)
		return
	}
	merchant, ok := result["merchant"].(common.Address)
	if !ok {
		logger.Error("fail in parse merchant:", err)
		return
	}
	fmt.Println("⏱️ Tổng thời gian111111111:", time.Since(start))
	atTime := time.Now().Unix()
	kq, err := utils.SendToThirdParty(card, amount, merchant, h.thirdPartyURL)
	fmt.Println("⏱️ Tổng thời gian22222222:", time.Since(start))
	if kq.Status == "failed" && !strings.Contains(kq.Message, "Transaction failed, pending"){
		logger.Info("❌ Giao dịch thất bại: %s", kq.Message)

		h.service.UpdateTxStatus(tokenId, kq.TransactionID, 0, uint64(atTime), kq.Message)
	}else if kq.Status == "success"{
		go h.service.UpdateTxStatus(tokenId, kq.TransactionID, 2, uint64(atTime), "success")
		go h.service.MintUTXO(amount, merchant, kq.TransactionID)
		fmt.Println("⏱️ Tổng thời gian4444444444:", time.Since(start))
	}else{
		// kq.Status == "being processed" || (kq.Status == "failed" && strings.Contains(kq.Message, "Transaction failed, pending") ){
		logger.Info("⏳ Giao dịch đang xử lý...")
		h.service.UpdateTxStatus(tokenId, kq.TransactionID, 1, uint64(atTime), "being processed")
		ctx, cancel := context.WithCancel(context.Background())

		h.cancelMu.Lock()
		if oldCancel, ok := h.cancelMonitors[kq.TransactionID]; ok {
			oldCancel() // hủy monitor cũ nếu có
		}
		h.cancelMonitors[kq.TransactionID] = cancel
		h.cancelMu.Unlock()
		go h.monitorTransaction(tokenId, ctx, kq.TransactionID, amount, merchant,start)
	}
}
func (h *CardHandler) monitorTransaction(tokenId [32]byte, ctx context.Context, txID string, parentValue *big.Int, ownerPool common.Address,start time.Time) {
	for i := 0; i < 5; i++ {
		select {
		case <-ctx.Done():
			logger.Info("🛑 Dừng kiểm tra giao dịch:", txID)
			return
		case <-time.After(1 * time.Second):
			status := utils.UpdateStatus(txID)
			atTime := time.Now().Unix()
			fmt.Println("⏱️ Tổng thời gian5555555555:", time.Since(start))
			if status == "success" {
				// kq, err := h.service.UpdateTxStatus(tokenId, txID, 2, uint64(atTime), "success")
				// result, ok := kq.(bool)
				// if err == nil && ok && result {
				// 	h.service.MintUTXO(parentValue, ownerPool, txID)
				// }
				h.service.UpdateTxStatus(tokenId, txID, 2, uint64(atTime), "success")
				fmt.Println("⏱️ Tổng thời gian666666666666:", time.Since(start))
				start1 := time.Now() 
				kq,_ := h.service.MintUTXO(parentValue, ownerPool, txID)
				fmt.Println("Done",kq)
				
				fmt.Println("⏱️ Tổng thời gian7777777777:", time.Since(start1))
				h.service.GetPoolInfo(txID)
				fmt.Println("⏱️ Tổng thời giankkkkkkkkkk:", time.Since(start1))
				fmt.Println("⏱️ Tổng thời gian:", time.Since(start))
				return
			}

			// if strings.Contains(status,"transaction not exists") {
			// 	h.service.UpdateTxStatus(tokenId, txID, 0, uint64(atTime), "fail")
			// 	return
			// }

			logger.Info("🔄 Vẫn đang kiểm tra...")
		}
	}
	logger.Info("❗ Hết thời gian kiểm tra.")
}
