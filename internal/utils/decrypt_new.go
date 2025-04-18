package utils

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"

	// "crypto/sha256"
	"encoding/hex"
	"fmt"

	// secp "github.com/decred/dcrd/dcrec/secp256k1/v4"
	// secp "secp256k1-cgo/secp"
	secp "github.com/meta-node-blockchain/noti-contract/internal/secp256k1-cgo/secp"
)

// // ECDH + SHA256 with version byte 0x02
// func ECDHSharedSecretHex(privBytes, pubBytes []byte) (string, error) {

// 	privKey := secp.PrivKeyFromBytes(privBytes)
// 	pubKey, err := secp.ParsePubKey(pubBytes)
// 	if err != nil {
// 		return "", err
// 	}

// 	shared := secp.GenerateSharedSecret(privKey, pubKey)

//		h := sha256.New()
//		h.Write([]byte{0x02}) // Version byte
//		h.Write(shared)
//		output := h.Sum(nil)
//		return hex.EncodeToString(output), nil
//	}
//
// ECDH + SHA256 with version byte 0x02
func ECDHSharedSecretHex(privBytes, pubBytes []byte) (string, error) {

	shared, err := secp.CreateECDH(hex.EncodeToString(privBytes), hex.EncodeToString(pubBytes))
	if err != nil {
		return "", err
	}

	return shared, nil
}

// func PublicKeyFromPrivateKeyHex(privHex string, compressed bool) (string, error) {
// 	privBytes, _ := hex.DecodeString(privHex)
// 	priv := secp.PrivKeyFromBytes(privBytes)
// 	var pubBytes []byte
// 	if compressed {
// 		pubBytes = priv.PubKey().SerializeCompressed()
// 	} else {
// 		pubBytes = priv.PubKey().SerializeUncompressed()
// 	}
// 	return hex.EncodeToString(pubBytes), nil
// }
// func PublicKeyFromPrivateKeyHex(privHex string, compressed bool) (string, error) {
// 	pubCompressed, err := secp.CreatePublicKey(privHex, true)
// 	if err != nil {
// 		return "", err
// 	}
// 	return pubCompressed, nil
// }

func padPKCS7(data []byte, blockSize int) []byte {
	padding := blockSize - len(data)%blockSize
	padtext := bytes.Repeat([]byte{byte(padding)}, padding)
	return append(data, padtext...)
}

func unpadPKCS7(data []byte) ([]byte, error) {
	length := len(data)
	if length == 0 {
		return nil, fmt.Errorf("data is empty")
	}
	padding := int(data[length-1])
	if padding > length {
		return nil, fmt.Errorf("invalid padding")
	}
	return data[:length-padding], nil
}

func EncryptAESCBC(key []byte, plaintext []byte, iv []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	plaintext = padPKCS7(plaintext, aes.BlockSize)
	ciphertext := make([]byte, len(plaintext))
	mode := cipher.NewCBCEncrypter(block, iv)
	mode.CryptBlocks(ciphertext, plaintext)
	return ciphertext, nil
}

func DecryptAESCBC(ciphertext []byte, privHexB, pubHexA []byte, iv []byte) ([]byte, error) {
	sharedBHex, _ := ECDHSharedSecretHex(privHexB, pubHexA)
	sharedBBytes, _ := hex.DecodeString(sharedBHex)
	block, err := aes.NewCipher(sharedBBytes)
	if err != nil {
		return nil, err
	}
	plaintext := make([]byte, len(ciphertext))
	mode := cipher.NewCBCDecrypter(block, iv)
	mode.CryptBlocks(plaintext, ciphertext)
	return unpadPKCS7(plaintext)
}
