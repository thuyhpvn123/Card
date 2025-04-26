package model
type TxResponse struct {
    Message       string `json:"message"`
    Status        string `json:"status"`
    TransactionID string `json:"transactionID"`
}