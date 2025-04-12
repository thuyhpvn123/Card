package utils

import (
	// "bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"

	// "crypto/x509"
	"encoding/hex"
	"fmt"
	"log"
)

// GenerateECDHKeyPair tạo cặp khóa ECDH (private, public)
func GenerateECDHKeyPair() (*ecdsa.PrivateKey, []byte) {
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		log.Fatalf("Error generating ECDH key pair: %v", err)
	}
	publicKeyBytes := elliptic.Marshal(elliptic.P256(), privateKey.PublicKey.X, privateKey.PublicKey.Y)
	return privateKey, publicKeyBytes
}

// ComputeSharedSecret tính toán shared secret từ khóa riêng & khóa công khai bên kia
func ComputeSharedSecret(privateKey *ecdsa.PrivateKey, peerPublicKeyBytes []byte) []byte {
	x, y := elliptic.Unmarshal(elliptic.P256(), peerPublicKeyBytes)
	if x == nil {
		log.Fatalf("Invalid peer public key")
	}
	sharedX, _ := privateKey.Curve.ScalarMult(x, y, privateKey.D.Bytes())
	return sharedX.Bytes()
}

// EncryptAESGCM mã hóa deviceToken bằng AES-GCM
func EncryptAESGCM(sharedSecret, plaintext []byte) (string, error) {
	block, err := aes.NewCipher(sharedSecret[:16]) // AES-128
	if err != nil {
		return "", err
	}
	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonce := make([]byte, aesGCM.NonceSize())
	_, err = rand.Read(nonce)
	if err != nil {
		return "", err
	}

	ciphertext := aesGCM.Seal(nonce, nonce, plaintext, nil)
	return hex.EncodeToString(ciphertext), nil
}

// DecryptAESGCM giải mã encryptedDeviceToken
func DecryptAESGCM(encryptedText []byte,serverPriv *ecdsa.PrivateKey,clientPublic []byte) ([]byte, error) {
	fmt.Println("clientPublic:",hex.EncodeToString(clientPublic))
	// sharedSecret := ComputeSharedSecret(serverPrivate, clientPublic)
	// clientPrivBytes, _ := hex.DecodeString(clientPrivHex)
	curve := elliptic.P256()
	// clientPriv := new(ecdsa.PrivateKey)
	// clientPriv.D = new(big.Int).SetBytes(clientPrivBytes)
	// clientPriv.PublicKey.Curve = curve
	clientPubX, clientPubY := elliptic.Unmarshal(elliptic.P256(), clientPublic)
	// if clientPriv.PublicKey.X == nil {
	// 	log.Fatalf("Invalid clientPublic")
	// }
	
	// sharedSecret, _ := serverPrivate.Curve.ScalarMult(x, y, serverPrivate.D.Bytes())
	x2, _ := curve.ScalarMult(clientPubX, clientPubY, serverPriv.D.Bytes())
	sharedSecret := sha256.Sum256(x2.Bytes())
	//
	block, err := aes.NewCipher(sharedSecret[:16]) // AES-128
	if err != nil {
		return []byte{}, err
	}
	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return []byte{}, err
	}

	nonceSize := aesGCM.NonceSize()
	if len(encryptedText) < nonceSize {
		return []byte{}, fmt.Errorf("Invalid encrypted data")
	}

	nonce, ciphertext := encryptedText[:nonceSize], encryptedText[nonceSize:]
	plaintext, err := aesGCM.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return []byte{}, err
	}

	return plaintext, nil
}

