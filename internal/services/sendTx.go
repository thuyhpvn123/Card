package services

import (
	"encoding/hex"
	"fmt"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	e_common "github.com/ethereum/go-ethereum/common"
	"github.com/meta-node-blockchain/cardvisa/internal/model"
	"github.com/meta-node-blockchain/meta-node/cmd/client"
	"github.com/meta-node-blockchain/meta-node/pkg/logger"
	pb "github.com/meta-node-blockchain/meta-node/pkg/proto"
	"github.com/meta-node-blockchain/meta-node/pkg/transaction"
	"math/big"
	"time"
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
	sendTransactionAndGetResult(
		methodName string,
		input []byte,
		unpackTo string,
		attempts int,
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
// General transaction handler with retry, unpack, and timeout logic
func (h *sendTransactionService) sendTransactionAndGetResult(
	methodName string,
	input []byte,
	unpackTo string,
	attempts int,
) (interface{}, error) {
	callData := transaction.NewCallData(input)

	bData, err := callData.Marshal()
	if err != nil {
		logger.Error(fmt.Sprintf("Marshal calldata for %s failed", methodName), err)
		return nil, err
	}

	relatedAddress := []e_common.Address{}
	maxGas := uint64(5_000_000)
	maxGasPrice := uint64(1_000_000_000)
	timeUse := uint64(0)

	for attempt := 1; attempt <= attempts; attempt++ {
		ch := make(chan model.ResultData, 1)
		go func() {
			receipt, err := h.chainClient.SendTransactionWithDeviceKey(
				h.fromAddress,
				h.cardAddress,
				big.NewInt(0),
				bData,
				relatedAddress,
				maxGas,
				maxGasPrice,
				timeUse,
			)
			ch <- model.ResultData{
				Receipt: receipt,
				Err:     err,
			}
		}()

		select {
		case res := <-ch:
			if res.Err != nil {
				logger.Error(fmt.Sprintf("SendTransactionWithDeviceKey error in %s", methodName), res.Err)
				return nil, res.Err
			}

			fmt.Printf("rc %s: %v\n", methodName, res.Receipt)

			if res.Receipt.Status() == pb.RECEIPT_STATUS_RETURNED {
				if unpackTo != "" {
					kq := make(map[string]interface{})
					err := h.cardAbi.UnpackIntoMap(kq, unpackTo, res.Receipt.Return())
					if err != nil {
						logger.Error(fmt.Sprintf("UnpackIntoMap error for %s", methodName), err)
						return nil, err
					}
					return kq, nil
				}
				return true, nil
			}
			return hex.EncodeToString(res.Receipt.Return()), nil

		case <-time.After(60 * time.Second):
			logger.Error(fmt.Sprintf("Timeout in %s", methodName))
			if attempt < attempts {
				time.Sleep(1 * time.Second)
				continue
			}
			return nil, fmt.Errorf("timeout after %d attempts in %s", attempts, methodName)
		}
	}

	return nil, fmt.Errorf("unexpected error in %s", methodName)
}

// SubmitToken calls submitToken method of smart contract
func (h *sendTransactionService) SubmitToken(
	user common.Address,
	tokenid [32]byte,
	region string,
	requestId [32]byte,
	cardHash [32]byte,
) (interface{}, error) {
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
		logger.Error("Pack error in SubmitToken", err)
		return nil, err
	}

	return h.sendTransactionAndGetResult("submitToken", input, "", 3)
}

// UpdateTxStatus calls UpdateTxStatus method of smart contract
func (h *sendTransactionService) UpdateTxStatus(
	tokenid [32]byte,
	txID string,
	status uint8,
	atTime uint64,
	reason string,
) (interface{}, error) {
	fmt.Println("UpdateTxStatus")
	input, err := h.cardAbi.Pack(
		"UpdateTxStatus",
		tokenid,
		txID,
		status,
		atTime,
		reason,
	)
	if err != nil {
		logger.Error("Pack error in UpdateTxStatus", err)
		return nil, err
	}

	return h.sendTransactionAndGetResult("UpdateTxStatus", input, "", 1)
}

// GetTx calls getTx method of smart contract and unpacks response
func (h *sendTransactionService) GetTx(
	txID string,
) (interface{}, error) {
	fmt.Println("GetTx")
	input, err := h.cardAbi.Pack("getTx", txID)
	if err != nil {
		logger.Error("Pack error in GetTx", err)
		return nil, err
	}

	return h.sendTransactionAndGetResult("getTx", input, "getTx", 1)
}

// CallVerifyPublicKey calls getBackendPubKey and returns only the value
func (h *sendTransactionService) CallVerifyPublicKey() (interface{}, error) {
	fmt.Println("getBackendPubKey")
	input, err := h.cardAbi.Pack("getBackendPubKey")
	if err != nil {
		logger.Error("Pack error in getBackendPubKey", err)
		return nil, err
	}

	result, err := h.sendTransactionAndGetResult("getBackendPubKey", input, "getBackendPubKey", 1)
	if err != nil {
		return nil, err
	}

	if m, ok := result.(map[string]interface{}); ok {
		return m[""], nil
	}

	return result, nil
}
// GetPoolInfo calls getPoolInfo method of smart contract and unpacks response
func (h *sendTransactionService) GetPoolInfo(
	txID string,
) (interface{}, error) {
	input, err := h.cardAbi.Pack("getPoolInfo", txID)
	if err != nil {
		logger.Error("Pack error in GetPoolInfo", err)
		return nil, err
	}

	return h.sendTransactionAndGetResult("getPoolInfo", input, "getPoolInfo", 1)
}
func (h *sendTransactionService) MintUTXO(
	parentValue *big.Int,
	ownerPool common.Address,
	txID string,
) (interface{}, error) {
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
	return h.sendTransactionAndGetResult("MintUTXO", input, "MintUTXO", 1)

}
// func (h *sendTransactionService) GetPoolInfo(
// 	txID string,
// ) (interface{}, error) {
// 	var result interface{}
// 	fmt.Println("GetPoolInfo")
// 	input, err := h.cardAbi.Pack(
// 		"getPoolInfo",
// 		txID,
// 	)
// 	if err != nil {
// 		logger.Error("error when pack call data getPoolInfo", err)
// 		return nil, err
// 	}
// 	callData := transaction.NewCallData(input)

// 	bData, err := callData.Marshal()
// 	if err != nil {
// 		logger.Error("error when marshal call data getPoolInfo", err)
// 		return nil, err
// 	}
// 	fmt.Println("input: ", hex.EncodeToString(bData))
// 	relatedAddress := []e_common.Address{}
// 	maxGas := uint64(5_000_000)
// 	maxGasPrice := uint64(1_000_000_000)
// 	timeUse := uint64(0)
// 	fmt.Println("h.fromAddress:", h.fromAddress)
// 	ch := make(chan model.ResultData, 1)
// 	go func() {
// 		receipt, err := h.chainClient.SendTransactionWithDeviceKey(
// 			h.fromAddress,
// 			h.cardAddress,
// 			big.NewInt(0),
// 			bData,
// 			relatedAddress,
// 			maxGas,
// 			maxGasPrice,
// 			timeUse,
// 		)
// 		ch <- model.ResultData{
// 			Receipt: receipt,
// 			Err:     err,
// 		}
// 	}()
// 	select {
// 	case res := <-ch:
// 		if res.Err != nil {
// 			logger.Error("SendTransactionWithDeviceKey error", res.Err)
// 			return nil, res.Err
// 		}
// 		fmt.Println("rc getPoolInfo:", res.Receipt)
// 		if res.Receipt.Status() == pb.RECEIPT_STATUS_RETURNED {

// 			kq := make(map[string]interface{})
// 			err = h.cardAbi.UnpackIntoMap(kq, "getPoolInfo", res.Receipt.Return())
// 			if err != nil {
// 				logger.Error("UnpackIntoMap")
// 				return nil, err
// 			}
// 			result = kq["transaction"]
// 			logger.Info("getPoolInfo - Result - Success")
// 		} else {
// 			result = hex.EncodeToString(res.Receipt.Return())
// 			logger.Info("getPoolInfo - Result - ", result)
// 		}
// 		return result, nil
// 	case <-time.After(10 * time.Second):
// 		logger.Error("Timeout when calling SendTransactionWithDeviceKey")
// 		return nil, fmt.Errorf("timeout: no receipt after 10 seconds")
// 	}

// }

// func (h *sendTransactionService) CallVerifyPublicKey() (interface{}, error) {
// 	var result interface{}
// 	input, err := h.cardAbi.Pack(
// 		"getBackendPubKey",
// 	)
// 	if err != nil {
// 		logger.Error("error when pack call data getBackendPubKey", err)
// 		return nil, err
// 	}
// 	callData := transaction.NewCallData(input)

// 	bData, err := callData.Marshal()
// 	if err != nil {
// 		logger.Error("error when marshal call data getBackendPubKey", err)
// 		return nil, err
// 	}
// 	fmt.Println("input: ", hex.EncodeToString(bData))
// 	relatedAddress := []e_common.Address{}
// 	maxGas := uint64(5_000_000)
// 	maxGasPrice := uint64(1_000_000_000)
// 	timeUse := uint64(0)
// 	ch := make(chan model.ResultData, 1)
// 	go func() {
// 		receipt, err := h.chainClient.SendTransactionWithDeviceKey(
// 			h.fromAddress,
// 			h.cardAddress,
// 			big.NewInt(0),
// 			bData,
// 			relatedAddress,
// 			maxGas,
// 			maxGasPrice,
// 			timeUse,
// 		)
// 		ch <- model.ResultData{
// 			Receipt: receipt,
// 			Err:     err,
// 		}
// 	}()
// 	select {
// 	case res := <-ch:
// 		if res.Err != nil {
// 			logger.Error("SendTransactionWithDeviceKey error", res.Err)
// 			return nil, res.Err
// 		}
// 		fmt.Println("rc getBackendPubKey:", res.Receipt)
// 		if res.Receipt.Status() == pb.RECEIPT_STATUS_RETURNED {
// 			kq := make(map[string]interface{})
// 			err = h.cardAbi.UnpackIntoMap(kq, "getBackendPubKey", res.Receipt.Return())
// 			if err != nil {
// 				logger.Error("UnpackIntoMap")
// 				return nil, err
// 			}
// 			result = kq[""]
// 			logger.Info("getBackendPubKey - Result - ", kq)
// 		} else {
// 			result = hex.EncodeToString(res.Receipt.Return())
// 			logger.Info("getBackendPubKey - Result - ", result)

// 		}
// 		return result, nil
// 	case <-time.After(10 * time.Second):
// 		logger.Error("Timeout when calling SendTransactionWithDeviceKey")
// 		return nil, fmt.Errorf("timeout: no receipt after 10 seconds")
// 	}
// }

// func (h *sendTransactionService) SubmitToken(
// 	user common.Address,
// 	tokenid [32]byte,
// 	region string,
// 	requestId [32]byte,
// 	cardHash [32]byte,
// ) (interface{}, error) {
// 	var result interface{}
// 	fmt.Println("SubmitToken")
// 	input, err := h.cardAbi.Pack(
// 		"submitToken",
// 		user,
// 		tokenid,
// 		region,
// 		requestId,
// 		cardHash,
// 	)
// 	if err != nil {
// 		logger.Error("error when pack call data submitToken", err)
// 		return nil, err
// 	}
// 	callData := transaction.NewCallData(input)

// 	bData, err := callData.Marshal()
// 	if err != nil {
// 		logger.Error("error when marshal call data submitToken", err)
// 		return nil, err
// 	}
// 	fmt.Println("input: ", hex.EncodeToString(bData))
// 	relatedAddress := []e_common.Address{}
// 	maxGas := uint64(5_000_000)
// 	maxGasPrice := uint64(1_000_000_000)
// 	timeUse := uint64(0)
// 	fmt.Println("h.fromAddress:", h.fromAddress)
// 	for attempt := 1; attempt <= 3; attempt++ {
// 		fmt.Printf("Attempt %d: sending transaction...\n", attempt)
// 		ch := make(chan model.ResultData, 1)
// 		go func() {
// 			receipt, err := h.chainClient.SendTransactionWithDeviceKey(
// 				h.fromAddress,
// 				h.cardAddress,
// 				big.NewInt(0),
// 				bData,
// 				relatedAddress,
// 				maxGas,
// 				maxGasPrice,
// 				timeUse,
// 			)
// 			ch <- model.ResultData{
// 				Receipt: receipt,
// 				Err:     err,
// 			}
// 		}()
// 		select {
// 		case res := <-ch:
// 			if res.Err != nil {
// 				logger.Error("SendTransactionWithDeviceKey error", res.Err)
// 				return nil, res.Err
// 			}
// 			fmt.Println("rc submitToken:", res.Receipt)
// 			if res.Receipt.Status() == pb.RECEIPT_STATUS_RETURNED {
// 				logger.Info("SubmitToken - Result - Success")
// 				result = true
// 			} else {
// 				result = hex.EncodeToString(res.Receipt.Return())
// 				logger.Info("SubmitToken - Result - ", result)

// 			}
// 			return result, nil
		
// 		case <-time.After(10 * time.Second):
// 			logger.Error("Timeout when calling SendTransactionWithDeviceKey")
// 			if attempt < 3 {
// 				time.Sleep(1 * time.Second)
// 				continue
// 			}
// 			return nil, fmt.Errorf("timeout after 3 attempts")
// 		}
// 	}
// 	return nil, fmt.Errorf("unexpected error in SubmitToken")

// }
// func (h *sendTransactionService) UpdateTxStatus(
// 	tokenid [32]byte,
// 	txID string,
// 	status uint8,
// 	atTime uint64,
// 	reason string,
// ) (interface{}, error) {
// 	var result interface{}
// 	fmt.Println("UpdateTxStatus")
// 	input, err := h.cardAbi.Pack(
// 		"UpdateTxStatus",
// 		tokenid,
// 		txID,
// 		status,
// 		atTime,
// 		reason,
// 	)
// 	if err != nil {
// 		logger.Error("error when pack call data UpdateTxStatus", err)
// 		return nil, err
// 	}
// 	callData := transaction.NewCallData(input)

// 	bData, err := callData.Marshal()
// 	if err != nil {
// 		logger.Error("error when marshal call data UpdateTxStatus", err)
// 		return nil, err
// 	}
// 	fmt.Println("input: ", hex.EncodeToString(bData))
// 	relatedAddress := []e_common.Address{}
// 	maxGas := uint64(5_000_000)
// 	maxGasPrice := uint64(1_000_000_000)
// 	timeUse := uint64(0)
// 	fmt.Println("h.fromAddress:", h.fromAddress)
// 	ch := make(chan model.ResultData, 1)

// 	go func() {
// 		receipt, err := h.chainClient.SendTransactionWithDeviceKey(
// 			h.fromAddress,
// 			h.cardAddress,
// 			big.NewInt(0),
// 			bData,
// 			relatedAddress,
// 			maxGas,
// 			maxGasPrice,
// 			timeUse,
// 		)
// 		ch <- model.ResultData{
// 			Receipt: receipt,
// 			Err:     err,
// 		}
// 	}()

// 	select {
// 	case res := <-ch:
// 		if res.Err != nil {
// 			logger.Error("SendTransactionWithDeviceKey error", res.Err)
// 			return nil, res.Err
// 		}
// 		fmt.Println("rc UpdateTxStatus:", res.Receipt)
// 		if res.Receipt.Status() == pb.RECEIPT_STATUS_RETURNED {
// 			logger.Info("UpdateTxStatus - Result - Success")
// 			result = true
// 		} else {
// 			result = hex.EncodeToString(res.Receipt.Return())
// 			logger.Info("UpdateTxStatus - Result - ", result)
// 		}
// 		return result, nil

// 	case <-time.After(10 * time.Second):
// 		logger.Error("Timeout when calling SendTransactionWithDeviceKey")
// 		return nil, fmt.Errorf("timeout: no receipt after 10 seconds")
// 	}
// }
// func (h *sendTransactionService) GetTx(
// 	txID string,
// ) (interface{}, error) {
// 	var result interface{}
// 	fmt.Println("getTx")
// 	input, err := h.cardAbi.Pack(
// 		"getTx",
// 		txID,
// 	)
// 	if err != nil {
// 		logger.Error("error when pack call data getTx", err)
// 		return nil, err
// 	}
// 	callData := transaction.NewCallData(input)

// 	bData, err := callData.Marshal()
// 	if err != nil {
// 		logger.Error("error when marshal call data getTx", err)
// 		return nil, err
// 	}
// 	fmt.Println("input: ", hex.EncodeToString(bData))
// 	relatedAddress := []e_common.Address{}
// 	maxGas := uint64(5_000_000)
// 	maxGasPrice := uint64(1_000_000_000)
// 	timeUse := uint64(0)
// 	fmt.Println("h.fromAddress:", h.fromAddress)
// 	ch := make(chan model.ResultData, 1)
// 	go func() {
// 		receipt, err := h.chainClient.SendTransactionWithDeviceKey(
// 			h.fromAddress,
// 			h.cardAddress,
// 			big.NewInt(0),
// 			bData,
// 			relatedAddress,
// 			maxGas,
// 			maxGasPrice,
// 			timeUse,
// 		)
// 		ch <- model.ResultData{
// 			Receipt: receipt,
// 			Err:     err,
// 		}
// 	}()
// 	select {
// 	case res := <-ch:
// 		if res.Err != nil {
// 			logger.Error("SendTransactionWithDeviceKey error", res.Err)
// 			return nil, res.Err
// 		}
// 		fmt.Println("rc getTx:", res.Receipt)
// 		if res.Receipt.Status() == pb.RECEIPT_STATUS_RETURNED {

// 			kq := make(map[string]interface{})
// 			err = h.cardAbi.UnpackIntoMap(kq, "getTx", res.Receipt.Return())
// 			if err != nil {
// 				logger.Error("UnpackIntoMap")
// 				return nil, err
// 			}
// 			result = kq["transaction"]
// 			logger.Info("getTx - Result - Success")
// 		} else {
// 			result = hex.EncodeToString(res.Receipt.Return())
// 			logger.Info("getTx - Result - ", result)
// 		}
// 		return result, nil
// 	case <-time.After(10 * time.Second):
// 		logger.Error("Timeout when calling SendTransactionWithDeviceKey")
// 		return nil, fmt.Errorf("timeout: no receipt after 10 seconds")
// 	}
// }
// func (h *sendTransactionService) MintUTXO(
// 	parentValue *big.Int,
// 	ownerPool common.Address,
// 	txID string,
// ) (interface{}, error) {
// 	var result interface{}
// 	start1 := time.Now()
// 	fmt.Println("MintUTXO")
// 	input, err := h.cardAbi.Pack(
// 		"MintUTXO",
// 		parentValue,
// 		ownerPool,
// 		txID,
// 	)
// 	if err != nil {
// 		logger.Error("error when pack call data MintUTXO", err)
// 		return nil, err
// 	}
// 	callData := transaction.NewCallData(input)

// 	bData, err := callData.Marshal()
// 	if err != nil {
// 		logger.Error("error when marshal call data MintUTXO", err)
// 		return nil, err
// 	}
// 	fmt.Println("input: ", hex.EncodeToString(bData))
// 	relatedAddress := []e_common.Address{}
// 	maxGas := uint64(5_000_000)
// 	maxGasPrice := uint64(1_000_000_000)
// 	timeUse := uint64(0)
// 	fmt.Println("h.fromAddress:", h.fromAddress)
// 	ch := make(chan model.ResultData, 1)
// 	go func() {
// 		receipt, err := h.chainClient.SendTransactionWithDeviceKey(
// 			h.fromAddress,
// 			h.cardAddress,
// 			big.NewInt(0),
// 			bData,
// 			relatedAddress,
// 			maxGas,
// 			maxGasPrice,
// 			timeUse,
// 		)
// 		ch <- model.ResultData{
// 			Receipt: receipt,
// 			Err:     err,
// 		}
// 	}()
// 	select {
// 	case res := <-ch:
// 		if res.Err != nil {
// 			logger.Error("SendTransactionWithDeviceKey error", res.Err)
// 			return nil, res.Err
// 		}
// 		fmt.Println("rc MintUTXO:", res.Receipt)
// 		if res.Receipt.Status() == pb.RECEIPT_STATUS_RETURNED {
// 			kq := make(map[string]interface{})
// 			err = h.cardAbi.UnpackIntoMap(kq, "MintUTXO", res.Receipt.Return())
// 			if err != nil {
// 				logger.Error("UnpackIntoMap MintUTXO")
// 				return nil, err
// 			}
// 			newPool := kq["newPool"]
// 			parentHash := kq["newPool"]
// 			fmt.Println("newPool:", newPool)
// 			fmt.Println("parentHash:", parentHash)
// 			logger.Info("MintUTXO - Result - Success")
// 		} else {
// 			result = hex.EncodeToString(res.Receipt.Return())
// 			logger.Info("MintUTXO - Result - ", result)
// 		}
// 		fmt.Println("⏱️ Tổng thời gian88888888888:", time.Since(start1))

// 		return result, nil
// 	case <-time.After(10 * time.Second):
// 		logger.Error("Timeout when calling SendTransactionWithDeviceKey")
// 		return nil, fmt.Errorf("timeout: no receipt after 10 seconds")
// 	}
// }
