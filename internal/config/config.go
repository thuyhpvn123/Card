package config

import (
	"fmt"

	// "github.com/ethereum/go-ethereum/common"
	"github.com/spf13/viper"
)

type AppConfig struct {
	API_PORT        string
	MYSQL_URL       string
	MetaNodeVersion string
	DnsLink_        string

	PrivateKey_           string
	ParentAddress         string
	NodeConnectionAddress string
	StorageAddress        string

	CardAddress string
	CardABIPath string

	ServerPrivateKeyPath     string
	ParentConnectionAddress  string
	ParentConnectionType     string
	ConnectionAddress_       string
	ChainId                  uint64
	StorageConnectionAddress string
	AdminAddress string
	PathLevelDB string
	ThirdPartyApiUrl string
}

var Config *AppConfig

func LoadConfig(path string) (*AppConfig, error) {
	viper.SetConfigFile(path)

	if err := viper.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var config AppConfig
	if err := viper.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config:   %w", err)
	}

	Config = &config
	return &config, nil
}

// func (c *AppConfig) Version() string {
// 	return c.MetaNodeVersion
// }
//
// func (c *AppConfig) NodeType() string {
// 	return "explorer"
// }

// func (c *AppConfig) PrivateKey() []byte {
// 	return common.FromHex(c.WalletPrivateKey)
// }

// func (c *AppConfig) PublicConnectionAddress() string {
// 	return c.SocketPublicConnectionAddress
// }

// func (c *AppConfig) ConnectionAddress() string {
// 	return c.SocketConnectionAddress
// }

func (c *AppConfig) DnsLink() string {
	return c.DnsLink_
}
