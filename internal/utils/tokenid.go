package utils

import (
	"crypto/rand"
	"crypto/sha256"
	"log"
)

func GenerateTokenID() [32]byte {
	// Random 64 bytes đầu vào để đảm bảo tính duy nhất
	randomBytes := make([]byte, 64)
	_, err := rand.Read(randomBytes)
	if err != nil {
		log.Fatalf("Failed to generate random bytes: %v", err)
	}

	// Hash bằng SHA-256 để lấy ra tokenId dạng [32]byte
	hash := sha256.Sum256(randomBytes)

	return hash
}