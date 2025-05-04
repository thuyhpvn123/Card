package services

import (
	"encoding/hex"
	"fmt"
	"math/big"
	"time"

	"github.com/meta-node-blockchain/meta-node/pkg/logger"
	pb "github.com/meta-node-blockchain/meta-node/pkg/proto"
	"github.com/meta-node-blockchain/meta-node/pkg/transaction"

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
	UpdateTxStatus(
		tokenid [32]byte,
		txID string,
		status uint8,
		atTime uint64,
		reason string,
	) (interface{}, error)
	GetTx(
		txID string,
	) (interface{}, error)
	MintUTXO(
		parentValue *big.Int,
		ownerPool common.Address,
		txID string,
	) (interface{}, error)
	GetPoolInfo(
		txID string,
	) (interface{}, error)
}
type sendTransactionService struct {
	chainClient *client.Client
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
		chainClient: chainClient,
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
	fmt.Println("h.fromAddress:", h.fromAddress)
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
func (h *sendTransactionService) UpdateTxStatus(
	tokenid [32]byte,
	txID string,
	status uint8,
	atTime uint64,
	reason string,
) (interface{}, error) {
	var result interface{}
	fmt.Println("UpdateTxStatus")
	start1 := time.Now()
	input, err := h.cardAbi.Pack(
		"UpdateTxStatus",
		tokenid,
		txID,
		status,
		atTime,
		reason,
	)
	if err != nil {
		logger.Error("error when pack call data UpdateTxStatus", err)
		return nil, err
	}
	callData := transaction.NewCallData(input)

	bData, err := callData.Marshal()
	if err != nil {
		logger.Error("error when marshal call data UpdateTxStatus", err)
		return nil, err
	}
	fmt.Println("input: ", hex.EncodeToString(bData))
	relatedAddress := []e_common.Address{}
	maxGas := uint64(5_000_000)
	maxGasPrice := uint64(1_000_000_000)
	timeUse := uint64(0)
	fmt.Println("h.fromAddress:", h.fromAddress)
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
	fmt.Println("rc UpdateTxStatus:", receipt)
	fmt.Println("⏱️ Tổng thời gian999999999:", time.Since(start1))

	if receipt.Status() == pb.RECEIPT_STATUS_RETURNED {
		logger.Info("UpdateTxStatus - Result - Success")
		result = true
	} else {
		result = hex.EncodeToString(receipt.Return())
		logger.Info("UpdateTxStatus - Result - ", result)

	}
	return result, nil
}
func (h *sendTransactionService) GetTx(
	txID string,
) (interface{}, error) {
	var result interface{}
	fmt.Println("getTx")
	input, err := h.cardAbi.Pack(
		"getTx",
		txID,
	)
	if err != nil {
		logger.Error("error when pack call data getTx", err)
		return nil, err
	}
	callData := transaction.NewCallData(input)

	bData, err := callData.Marshal()
	if err != nil {
		logger.Error("error when marshal call data getTx", err)
		return nil, err
	}
	fmt.Println("input: ", hex.EncodeToString(bData))
	relatedAddress := []e_common.Address{}
	maxGas := uint64(5_000_000)
	maxGasPrice := uint64(1_000_000_000)
	timeUse := uint64(0)
	fmt.Println("h.fromAddress:", h.fromAddress)
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
	fmt.Println("rc getTx:", receipt)
	if receipt.Status() == pb.RECEIPT_STATUS_RETURNED {

		kq := make(map[string]interface{})
		err = h.cardAbi.UnpackIntoMap(kq, "getTx", receipt.Return())
		if err != nil {
			logger.Error("UnpackIntoMap")
			return nil, err
		}
		result = kq["transaction"]
		logger.Info("getTx - Result - Success")
	} else {
		result = hex.EncodeToString(receipt.Return())
		logger.Info("getTx - Result - ", result)
	}
	return result, nil
}
func (h *sendTransactionService) MintUTXO(
	parentValue *big.Int,
	ownerPool common.Address,
	txID string,
) (interface{}, error) {
	var result interface{}
	start1 := time.Now()
	fmt.Println("MintUTXO")
	input, err := h.cardAbi.Pack(
		"MintUTXO",
		parentValue,
		ownerPool,
		txID,
	)
	if err != nil {
		logger.Error("error when pack call data MintUTXO", err)
		return nil, err
	}
	callData := transaction.NewCallData(input)

	bData, err := callData.Marshal()
	if err != nil {
		logger.Error("error when marshal call data MintUTXO", err)
		return nil, err
	}
	fmt.Println("input: ", hex.EncodeToString(bData))
	relatedAddress := []e_common.Address{}
	maxGas := uint64(5_000_000)
	maxGasPrice := uint64(1_000_000_000)
	timeUse := uint64(0)
	fmt.Println("h.fromAddress:", h.fromAddress)
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
	fmt.Println("rc MintUTXO:", receipt)
	if receipt.Status() == pb.RECEIPT_STATUS_RETURNED {
		kq := make(map[string]interface{})
		err = h.cardAbi.UnpackIntoMap(kq, "MintUTXO", receipt.Return())
		if err != nil {
			logger.Error("UnpackIntoMap MintUTXO")
			return nil, err
		}
		newPool := kq["newPool"]
		parentHash := kq["newPool"]
		fmt.Println("newPool:", newPool)
		fmt.Println("parentHash:", parentHash)
		logger.Info("MintUTXO - Result - Success")
	} else {
		result = hex.EncodeToString(receipt.Return())
		logger.Info("MintUTXO - Result - ", result)
	}
	fmt.Println("⏱️ Tổng thời gian88888888888:", time.Since(start1))

	return result, nil
}
func (h *sendTransactionService) GetPoolInfo(
	txID string,
) (interface{}, error) {
	var result interface{}
	fmt.Println("GetPoolInfo")
	start1 := time.Now()
	input, err := h.cardAbi.Pack(
		"getPoolInfo",
		txID,
	)
	if err != nil {
		logger.Error("error when pack call data getPoolInfo", err)
		return nil, err
	}
	callData := transaction.NewCallData(input)

	bData, err := callData.Marshal()
	if err != nil {
		logger.Error("error when marshal call data getPoolInfo", err)
		return nil, err
	}
	fmt.Println("input: ", hex.EncodeToString(bData))
	relatedAddress := []e_common.Address{}
	maxGas := uint64(5_000_000)
	maxGasPrice := uint64(1_000_000_000)
	timeUse := uint64(0)
	fmt.Println("h.fromAddress:", h.fromAddress)
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
	fmt.Println("rc getPoolInfo:", receipt)
	fmt.Println("⏱️ Tổng thời gianpppppppppp:", time.Since(start1))
	if receipt.Status() == pb.RECEIPT_STATUS_RETURNED {

		kq := make(map[string]interface{})
		err = h.cardAbi.UnpackIntoMap(kq, "getPoolInfo", receipt.Return())
		if err != nil {
			logger.Error("UnpackIntoMap")
			return nil, err
		}
		result = kq["transaction"]
		logger.Info("getPoolInfo - Result - Success")
	} else {
		result = hex.EncodeToString(receipt.Return())
		logger.Info("getPoolInfo - Result - ", result)
	}
	return result, nil
}

