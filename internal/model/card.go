package model
type CardData struct {
    CardNumber string `json:"cardNumber"`
	ExpMonth   string `json:"expireMonth"`
    ExpYear    string `json:"expireYear"`
    CVV        string `json:"cvv"`
}
