package network

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	e_common "github.com/ethereum/go-ethereum/common"
	"github.com/meta-node-blockchain/meta-node/pkg/logger"
	"github.com/meta-node-blockchain/meta-node/types"
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
}

func NewCardEventHandler(
	config *config.AppConfig,
	service services.SendTransactionService,
	cardABI *abi.ABI,
	ServerPrivateKey string,
	DB *leveldb.DB,
	thirdPartyURL string,
	storedPubKey string,
) *CardHandler {
	return &CardHandler{
		config:           config,
		service: service,
		cardABI:          cardABI,
		ServerPrivateKey: ServerPrivateKey,
		DB : DB,
		thirdPartyURL:thirdPartyURL,
		storedPubKey:storedPubKey,
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
		"data":hex.EncodeToString(encryptedCardData),

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
	// Convert HEX string to bytes
	serverPrivateKeyBytes, err := hex.DecodeString(h.ServerPrivateKey)
	if err != nil {
		logger.Error("Lỗi giải mã HEX: %v", err)
		return
	}
	
	encyptedCard := encryptedCardData[65:]
	clientPublicKey := encryptedCardData[:65]
	iv := encyptedCard[:16]
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
