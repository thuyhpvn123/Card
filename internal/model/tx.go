package model
import "github.com/meta-node-blockchain/meta-node/types"
type TxResponse struct {
    Message       string `json:"message"`
    Status        string `json:"status"`
    TransactionID string `json:"transactionID"`
}

// Channel để nhận kết quả hoặc lỗi
type ResultData struct {
    Receipt types.Receipt
    Err     error
}