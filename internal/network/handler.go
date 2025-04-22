package network

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	e_common "github.com/ethereum/go-ethereum/common"
	"github.com/meta-node-blockchain/meta-node/pkg/logger"
	// "github.com/meta-node-blockchain/meta-node/types"
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
	DB *leveldb.DB
	thirdPartyURL string
	storedPubKey string
	eventChan chan model.EventLog
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
		service: service,
		cardABI:          cardABI,
		ServerPrivateKey: ServerPrivateKey,
		DB : DB,
		thirdPartyURL:thirdPartyURL,
		storedPubKey:storedPubKey,
		eventChan:eventChan,
	}
}
func (h *CardHandler) VerifyPublicKey(){
	serverPubKey,err := h.service.CallVerifyPublicKey()
	if err != nil {
        logger.Error("Không thể lấy khóa công khai từ smart contract: %v", err)
		return
    }
	storedPubKeyBytes,err := hex.DecodeString(h.storedPubKey)
	serverPubKeyBytes,ok := serverPubKey.([]byte)
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
				topics := []string{tokenRequestTopic, chargeRequestTopic,chargeRejectedTopic}
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
	// for _, event := range events.EventLogList() {
	// 	switch event.Topics()[0] {
	// 	case h.cardABI.Events["TokenRequest"].ID.String()[2:]:
	// 		h.handleTokenRequest(event.Data())
	// 	case h.cardABI.Events["ChargeRequest"].ID.String()[2:]:
	// 		h.handleChargeRequest(event.Data())
	// 	}
	// }
	fmt.Println("event la:",event)
	fmt.Println("id la:",h.cardABI.Events["ChargeRequest"].ID.String())
	switch event.Topics[0] {
	case h.cardABI.Events["TokenRequest"].ID.String():
		h.handleTokenRequest(event.Data)
	case h.cardABI.Events["ChargeRequest"].ID.String():
		h.handleChargeRequest(event.Data)
	case h.cardABI.Events["ChargeRejected"].ID.String():
		h.handleChargeRejected(event.Data)

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
	// user, ok := result["user"].(common.Address)
	// if !ok {
	// 	logger.Error("fail in parse user ChargeRejected :", err)
	// 	return
	// }
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
		// "user": user,
		"tokenid":tokenId,
		"reason":reason,
	}
	logger.Info("ChargeRejected:",kq)

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
	fmt.Println("encryptedCardData:",hex.EncodeToString(encryptedCardData))
	encyptedCard := encryptedCardData[65:]
	clientPublicKey := encryptedCardData[:65]
	fmt.Println("clientPublicKey:",hex.EncodeToString(clientPublicKey))
	fmt.Println("encyptedCard:",hex.EncodeToString(encyptedCard[16:]))
	iv := encyptedCard[:16]
	fmt.Println("iv la:",hex.EncodeToString(iv))

	token, err := utils.DecryptAESCBC(encyptedCard[16:], serverPrivateKeyBytes, clientPublicKey,iv)
	if err != nil {
		logger.Error("fail in decrypt token:", err)
		return
	}
	var card model.CardData
	if err := json.Unmarshal(token, &card); err != nil {
		logger.Error("❌ Parse card failed: %v", err)
		return
	}
	fmt.Println("card:",card)
	fmt.Println("expire year request:",card.ExpYear)
	fmt.Println("user la :",result["user"])
	fmt.Printf("type %v",result["user"])
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
	fmt.Println("requestId la:",hex.EncodeToString(requestId[:]))
	tokenId := utils.GenerateTokenID()
	fmt.Println("tokenId la:",hex.EncodeToString(tokenId[:]))
	cardHash:= sha256.Sum256([]byte(card.CardNumber + card.ExpMonth + card.ExpYear))

	//api get region bo sung sau
	region := "VN"
	kq ,err := h.service.SubmitToken(user,tokenId,region,requestId,cardHash)
	if err != nil {
		logger.Error("fail in SubmitToken:", err)
		return
	} 
	kq1,ok := kq.(bool)
	if ok && kq1{
		callmap :=map[string]interface{}{
			"key": "token_" + hex.EncodeToString(tokenId[:]),
			// "data":hex.EncodeToString(encryptedCardData),
			"data":string(encryptedCardData),
	
		}
		err = database.WriteValueStorage(callmap,h.DB)
		if err != nil {
			logger.Error("fail in save in leveldb handleTokenRequest:", err)
			return
		}
		logger.Info("Saved token in db")
		// if !utils.SendToThirdParty(card, big.NewInt(0), common.Address{},h.thirdPartyURL) {
		//     logger.Error("❌ Pre-charge failed")
		//     // return
		// }	
	}

}

func (h *CardHandler) handleChargeRequest(data string) {
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
	callmap :=map[string]interface{}{
		"key": "token_" + hex.EncodeToString(tokenId[:]),
	}
	encryptedCardData,err := database.ReadValueStorage(callmap,h.DB)
	if err != nil {
		logger.Error("fail in get encryptedCardData in db:", err)
		return
	}
	fmt.Println("encryptedCardData charge la:",string(encryptedCardData))
	// Convert HEX string to bytes
	serverPrivateKeyBytes, err := hex.DecodeString(h.ServerPrivateKey)
	if err != nil {
		logger.Error("Lỗi giải mã HEX: %v", err)
		return
	}
	// encryptedCardData = hex.DecodeString(
	encyptedCard := encryptedCardData[65:]
	clientPublicKey := encryptedCardData[:65]
	iv := encyptedCard[:16]
	token, err := utils.DecryptAESCBC(encyptedCard[16:], serverPrivateKeyBytes, clientPublicKey,iv)
	if err != nil {
		logger.Error("fail in decrypt token ChargeRequest:", err)
		return
	}
	var card model.CardData
	if err := json.Unmarshal(token, &card); err != nil {
		logger.Error("❌ Parse card failed: %v", err)
		return
	}
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

	if !utils.SendToThirdParty(card, amount, merchant,h.thirdPartyURL) {
	    logger.Error("❌ Swipe API failed: %v", err)
	    return
	}

	
}
