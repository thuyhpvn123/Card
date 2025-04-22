package services

import (
	"encoding/hex"
	"fmt"
	"math/big"

	pb "github.com/meta-node-blockchain/meta-node/pkg/proto"
	"github.com/meta-node-blockchain/meta-node/pkg/transaction"
	"github.com/meta-node-blockchain/meta-node/pkg/logger"

	"github.com/meta-node-blockchain/meta-node/cmd/client"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	e_common "github.com/ethereum/go-ethereum/common"
)

type SendTransactionService interface {
	SubmitToken(
		user common.Address,
		tokenid [32]byte,
		region string,
		requestId [32]byte,
		cardHash [32]byte,
	) (interface{}, error)
	CallVerifyPublicKey() (interface{}, error) 
}
type sendTransactionService struct {
	chainClient        *client.Client
	cardAbi     *abi.ABI
	cardAddress e_common.Address
	fromAddress e_common.Address
}

func NewSendTransactionService(
	chainClient *client.Client,
	cardAbi *abi.ABI,
	cardAddress e_common.Address,
	fromAddress e_common.Address,
) SendTransactionService {
	return &sendTransactionService{
		chainClient:        chainClient,
		cardAbi:     cardAbi,
		cardAddress: cardAddress,
		fromAddress: fromAddress,
	}
}

func (h *sendTransactionService) CallVerifyPublicKey() (interface{}, error) {
	var result interface{}
	input, err := h.cardAbi.Pack(
		"getBackendPubKey",
	)
	if err != nil {
		logger.Error("error when pack call data getBackendPubKey", err)
		return nil, err
	}
	callData := transaction.NewCallData(input)

	bData, err := callData.Marshal()
	if err != nil {
		logger.Error("error when marshal call data getBackendPubKey", err)
		return nil, err
	}
	fmt.Println("input: ", hex.EncodeToString(bData))
	relatedAddress := []e_common.Address{}
	maxGas := uint64(5_000_000)
	maxGasPrice := uint64(1_000_000_000)
	timeUse := uint64(0)
	receipt, err := h.chainClient.SendTransactionWithDeviceKey(
		h.fromAddress,
		h.cardAddress,
		big.NewInt(0),
		// 4,
		bData,
		relatedAddress,
		maxGas,
		maxGasPrice,
		timeUse,
	)
	fmt.Println("rc getBackendPubKey:", receipt)
	if receipt.Status() == pb.RECEIPT_STATUS_RETURNED {
		kq := make(map[string]interface{})
		err = h.cardAbi.UnpackIntoMap(kq, "getBackendPubKey", receipt.Return())
		if err != nil {
			logger.Error("UnpackIntoMap")
			return nil, err
		}
		result = kq[""]
		logger.Info("getBackendPubKey - Result - ", kq)
	} else {
		result = hex.EncodeToString(receipt.Return())
		logger.Info("getBackendPubKey - Result - ", result)

	}
	return result, nil
}

func (h *sendTransactionService) SubmitToken(
	user common.Address,
	tokenid [32]byte,
	region string,
	requestId [32]byte,
	cardHash [32]byte,
) (interface{}, error) {
	var result interface{}
	fmt.Println("SubmitToken")
	input, err := h.cardAbi.Pack(
		"submitToken",
		user,
		tokenid,
		region,
		requestId,
		cardHash,
	)
	if err != nil {
		logger.Error("error when pack call data submitToken", err)
		return nil, err
	}
	callData := transaction.NewCallData(input)

	bData, err := callData.Marshal()
	if err != nil {
		logger.Error("error when marshal call data submitToken", err)
		return nil, err
	}
	fmt.Println("input: ", hex.EncodeToString(bData))
	relatedAddress := []e_common.Address{}
	maxGas := uint64(5_000_000)
	maxGasPrice := uint64(1_000_000_000)
	timeUse := uint64(0)
	fmt.Println("h.fromAddress:",h.fromAddress)
	receipt, err := h.chainClient.SendTransactionWithDeviceKey(
		h.fromAddress,
		h.cardAddress,
		big.NewInt(0),
		// pb.ACTION_CALL_SMART_CONTRACT,
		bData,
		relatedAddress,
		maxGas,
		maxGasPrice,
		timeUse,
	)
	fmt.Println("rc submitToken:", receipt)
	if receipt.Status() == pb.RECEIPT_STATUS_RETURNED {
		logger.Info("SubmitToken - Result - Success")
		result = true
	} else {
		result = hex.EncodeToString(receipt.Return())
		logger.Info("SubmitToken - Result - ", result)

	}
	return result, nil
}
