package utils

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"golang.org/x/crypto/sha3"
)
var insecureClient = &http.Client{
	Timeout: 60 * time.Second,
	Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	},
}
type LogParams struct { 
	FromBlock string `json:"fromBlock" `
	ToBlock string `json:"toBlock" `
	Address string` json:"address" `
	Topics []string` json:"topics" `
}

type RPCRequest struct {
	 JSONRPC string `json:"jsonrpc" `
	 Method string `json:"method" `
	 Params []interface{} `json:"params" `
	 ID int `json:"id"` 
}

type RPCResponse struct { 
	JSONRPC string `json:"jsonrpc"`
	ID int `json:"id"` 
	Result []json.RawMessage `json:"result"` 
	Error *RPCError `json:"error,omitempty"`
 }

type RPCError struct { 
	Code int `json:"code" `
	Message string `json:"message"` 
}

func GetTopic0FromABI(abiJSON, eventName string) (string, error) { 
	parsedABI, err := abi.JSON(strings.NewReader(abiJSON)) 
	if err != nil { return "", err }
		event, ok := parsedABI.Events[eventName]
	if !ok {
		return "", fmt.Errorf("event %s not found", eventName)
	}

	hash := keccak256(event.Sig)
	return "0x" + fmt.Sprintf("%x", hash), nil
}

func keccak256(s string) []byte {
	 hash := sha3.NewLegacyKeccak256() 
	 hash.Write([]byte(s)) 
	 return hash.Sum(nil) 
}

func GetLogs(rpcURL, fromBlock, toBlock, contractAddress, topic0 string) ([]json.RawMessage, error) { 
	params := LogParams{ 
		FromBlock: fromBlock, 
		ToBlock: toBlock, 
		Address: contractAddress, 
		Topics: []string{topic0}, 
	}
	req := RPCRequest{
		JSONRPC: "2.0",
		Method:  "eth_getLogs",
		Params:  []interface{}{params},
		ID:      1,
	}
	data, _ := json.Marshal(req)
resp, err := insecureClient.Post(rpcURL, "application/json", bytes.NewBuffer(data))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var rpcResp RPCResponse
	if err := json.Unmarshal(body, &rpcResp); err != nil {
		return nil, err
	}
	if rpcResp.Error != nil {
		return nil, fmt.Errorf("RPC Error: %s", rpcResp.Error.Message)
	}

	return rpcResp.Result, nil
}
func GetLatestBlockNumber(rpcURL string) (string, error) { 
	req := RPCRequest{ 
		JSONRPC: "2.0", 
		Method: "eth_blockNumber",
		 Params: []interface{}{}, 
		 ID: 1, 
	}
	data, err := json.Marshal(req)
	if err != nil {
		return "", fmt.Errorf("failed to marshal JSON-RPC request: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	httpReq, err := http.NewRequestWithContext(ctx, "POST", rpcURL, bytes.NewBuffer(data))
	if err != nil {
		return "", fmt.Errorf("failed to create HTTP request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := insecureClient.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response body: %w", err)
	}

	var rpcResp struct {
		Result string `json:"result"`
		Error  *struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error,omitempty"`
	}

	if err := json.Unmarshal(body, &rpcResp); err != nil {
		return "", fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if rpcResp.Error != nil {
		return "", fmt.Errorf("RPC error %d: %s", rpcResp.Error.Code, rpcResp.Error.Message)
	}

	return rpcResp.Result, nil
}