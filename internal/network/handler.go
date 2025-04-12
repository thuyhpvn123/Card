package network

import (
	// "bytes"
	// "crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"fmt"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	e_common "github.com/ethereum/go-ethereum/common"

	// "github.com/meta-node-blockchain/meta-node/cmd/client"
	"github.com/meta-node-blockchain/meta-node/pkg/logger"
	"github.com/meta-node-blockchain/meta-node/types"
	"github.com/meta-node-blockchain/noti-contract/internal/config"
	"github.com/meta-node-blockchain/noti-contract/internal/model"
	"github.com/meta-node-blockchain/noti-contract/internal/services"
	"github.com/meta-node-blockchain/noti-contract/internal/utils"
	"github.com/syndtr/goleveldb/leveldb"
	"github.com/meta-node-blockchain/noti-contract/internal/database"

)

type CardHandler struct {
	config           *config.AppConfig
	service          services.SendTransactionService
	cardABI          *abi.ABI
	ServerPrivateKey string
	DB *leveldb.DB
}

func NewCardEventHandler(
	config *config.AppConfig,
	service services.SendTransactionService,
	cardABI *abi.ABI,
	ServerPrivateKey string,
	DB *leveldb.DB,
) *CardHandler {
	return &CardHandler{
		config:           config,
		service: service,
		cardABI:          cardABI,
		ServerPrivateKey: ServerPrivateKey,
		DB : DB,
	}
}
func (h *CardHandler) VerifyPublicKey(){
	// serverPubKey,err := h.service.CallVerifyPublicKey()
	// if err != nil {
    //     logger.Error("Không thể lấy khóa công khai từ smart contract: %v", err)
	// 	return
    // }
	// if !bytes.Equal(serverPubKey, h.storedPubKey) {
    //     logger.Error("Khóa công khai không khớp với smart contract.")
	// 	return
    // }

    // logger.Info("Xác thực khóa công khai thành công.")
}
func (h *CardHandler) HandleConnectSmartContract(events types.EventLogs) {
	for _, event := range events.EventLogList() {
		switch event.Topics()[0] {
		case h.cardABI.Events["TokenRequest"].ID.String()[2:]:
			h.handleTokenRequest(event.Data())
		case h.cardABI.Events["ChargeRequest"].ID.String()[2:]:
			h.handleChargeRequest(event.Data())
		}
	}
}
func (h *CardHandler) handleTokenRequest(data string) {
	result := make(map[string]interface{})
	err := h.cardABI.UnpackIntoMap(result, "TokenRequest", e_common.FromHex(data))
	if err != nil {
		logger.Error("can't unpack to map", err)
		return
	}
	fmt.Println("result la:",result)
	// Convert HEX string to bytes
	fmt.Println("h.ServerPrivateKey:",h.ServerPrivateKey)
	serverPrivateKeyBytes, err := hex.DecodeString(h.ServerPrivateKey)
	if err != nil {
		logger.Error("Lỗi giải mã HEX: %v", err)
		return
	}

	// Parse private key from DER format
	key, err := x509.ParseECPrivateKey(serverPrivateKeyBytes)
	if err != nil {
		logger.Error("Lỗi parse private key: %v", err)
		return
	}
	// serverPriv, ok := key.(*ecdsa.PrivateKey)
	// if !ok {
	// 	logger.Error("Parsed key is not ECDSA private key")
	// 	return
	// }
	encryptedCardData, ok := result["encryptedCardData"].([]byte)
	if !ok {
		logger.Error("fail in parse encryptedCardData :", err)
		return
	}
	fmt.Println("encryptedCardData:",hex.EncodeToString(encryptedCardData))
	encyptedCard := encryptedCardData[65:]
	clientPublicKey := encryptedCardData[:65]
	fmt.Println("clientPublicKey:",hex.EncodeToString(clientPublicKey))
	fmt.Println("encyptedCard:",hex.EncodeToString(encyptedCard))
	token, err := utils.DecryptAESGCM(encyptedCard, key, clientPublicKey)
	if err != nil {
		logger.Error("fail in decrypt token:", err)
		return
	}
	var card model.CardData
	if err := json.Unmarshal(token, &card); err != nil {
		logger.Error("❌ Parse card failed: %v", err)
		return
	}
	// if !sendToThirdParty(card, event.Amount, event.Merchant) {
	//     logger.Error("❌ Swipe API failed: %v", err)
	//     return
	// }
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
	tokenId := utils.GenerateTokenID()
	cardHash:= sha256.Sum256([]byte(card.CardNumber + card.ExpMonth + card.ExpYear))

	//api get region bo sung sau
	region := ""
	h.service.SubmitToken(user,tokenId,region,requestId,cardHash)
	callmap :=map[string]interface{}{
		"key": "token_" + hex.EncodeToString(tokenId[:]),
		"data":encyptedCard,

	}
	err = database.WriteValueStorage(callmap,h.DB)
	if err != nil {
		logger.Error("fail in save in leveldb handleTokenRequest:", err)
		return
	}
}

func (h *CardHandler) handleChargeRequest(data string) {
	result := make(map[string]interface{})
	err := h.cardABI.UnpackIntoMap(result, "ChargeRequest", e_common.FromHex(data))
	if err != nil {
		logger.Error("can't unpack to map", err)
		return
	}
	// Convert HEX string to bytes
	fmt.Println("h.ServerPrivateKey:",h.ServerPrivateKey)
	serverPrivateKeyBytes, err := hex.DecodeString(h.ServerPrivateKey)
	if err != nil {
		logger.Error("Lỗi giải mã HEX: %v", err)
		return
	}

	// Parse private key from DER format
	key, err := x509.ParseECPrivateKey(serverPrivateKeyBytes)
	if err != nil {
		logger.Error("Lỗi parse private key: %v", err)
		return
	}
	// serverPriv, ok := key.(*ecdsa.PrivateKey)
	// if !ok {
	// 	logger.Error("Parsed key is not ECDSA private key")
	// 	return
	// }
	encryptedCardData, ok := result["encryptedCardData"].([]byte)
	if !ok {
		logger.Error("fail in parse encryptedCardData:", err)
		return
	}
	fmt.Println("encryptedCardData:",hex.EncodeToString(encryptedCardData))
	encyptedCard := encryptedCardData[65:]
	clientPublicKey := encryptedCardData[:65]
	fmt.Println("clientPublicKey:",hex.EncodeToString(clientPublicKey))
	fmt.Println("encyptedCard:",hex.EncodeToString(encyptedCard))
	token, err := utils.DecryptAESGCM(encyptedCard, key, clientPublicKey)
	if err != nil {
		logger.Error("fail in decrypt token:", err)
		return
	}
	var card model.CardData
	if err := json.Unmarshal(token, &card); err != nil {
		logger.Error("❌ Parse card failed: %v", err)
		return
	}
	// if !sendToThirdParty(card, event.Amount, event.Merchant) {
	//     logger.Error("❌ Swipe API failed: %v", err)
	//     return
	// }
	user, ok := result["user"].(common.Address)
	if !ok {
		logger.Error("fail in parse scheduledTimes:", err)
		return
	}
	requestId, ok := result["requestId"].([32]byte)
	if !ok {
		logger.Error("fail in parse scheduledTimes:", err)
		return
	}
	tokenId := utils.GenerateTokenID()
	cardHash:= sha256.Sum256([]byte(card.CardNumber + card.ExpMonth + card.ExpYear))

	//api get region bo sung sau
	region := ""
	h.service.SubmitToken(user,tokenId,region,requestId,cardHash)
	
}
