package app

import (
	"fmt"
	"log"
	"os"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/gin-gonic/gin"
	"github.com/meta-node-blockchain/meta-node/cmd/client"
	"github.com/meta-node-blockchain/meta-node/pkg/logger"
	// "github.com/meta-node-blockchain/meta-node/types"
	"github.com/meta-node-blockchain/cardvisa/internal/network"
	"github.com/meta-node-blockchain/cardvisa/internal/config"
		"github.com/meta-node-blockchain/cardvisa/internal/services"
	c_config "github.com/meta-node-blockchain/meta-node/cmd/client/pkg/config"
	"github.com/meta-node-blockchain/cardvisa/internal/database"
	"github.com/meta-node-blockchain/cardvisa/internal/model"

)

type App struct {
	Config *config.AppConfig
	ApiApp *gin.Engine

	ChainClient *client.Client
	EventChan   chan model.EventLog
	StopChan    chan bool

	CardHandler *network.CardHandler
	// StorageClient *client.Client
}

func NewApp(
	configPath string,
	loglevel int,
) (*App, error) {
	loggerConfig := &logger.LoggerConfig{
		Flag:    loglevel,
		Outputs: []*os.File{os.Stdout},
	}
	logger.SetConfig(loggerConfig)

	config, err := config.LoadConfig(configPath)
	if err != nil {
		log.Fatal("invalid configuration", err)
		return nil, err
	}
	app := &App{}
	app.ChainClient, err = client.NewClient(
		&c_config.ClientConfig{
			Version_:                config.MetaNodeVersion,
			PrivateKey_:             config.PrivateKey_,
			ParentAddress:           config.AdminAddress,
			ParentConnectionAddress: config.ParentConnectionAddress,
			// DnsLink_:                config.DnsLink(),
			ConnectionAddress_:      config.ConnectionAddress_,
			ParentConnectionType:    config.ParentConnectionType,
			ChainId:                 config.ChainId,
		},
	)
	if err != nil {
		logger.Error(fmt.Sprintf("error when create chain client %v", err))
		return nil, err
	}
	// app.StorageClient, err = client.NewClient(
	// 	&c_config.ClientConfig{
	// 		Version_:                config.MetaNodeVersion,
	// 		PrivateKey_:             config.PrivateKey_,
	// 		ParentAddress:           config.AdminAddress,
	// 		ParentConnectionAddress: config.ParentConnectionAddress,
	// 		// DnsLink_:                config.DnsLink(),
	// 		ConnectionAddress_:      config.ConnectionAddress_,
	// 		ParentConnectionType:    config.ParentConnectionType,
	// 		ChainId:                 config.ChainId,
	// 	},
	// )
	// if err != nil {
	// 	logger.Error(fmt.Sprintf("error when create storage client %v", err))
	// 	return nil, err
	// }
	// app.EventChan, err = app.StorageClient.Subcribe(
	// 	common.HexToAddress(config.StorageAddress),
	// 	common.HexToAddress(config.CardAddress),
	// 	config.ParentConnectionAddress,
	// )
	// if err != nil {
	// 	logger.Error(fmt.Sprintf("error when Subcribes %v", emodelsrr))
	// 	return nil, err
	// }
	app.EventChan = make(chan model.EventLog, 1000) // buffer 100 để tránh nghẽn
	leveldb, err :=database.Open(config.PathLevelDB)
	readerHub, err := os.Open(config.CardABIPath)
	if err != nil {
		logger.Error("Error occured while read create card smart contract abi")
		return nil, err
	}
	defer readerHub.Close()

	cardAbi, err := abi.JSON(readerHub)
	if err != nil {
		logger.Error("Error occured while parse create card smart contract abi")
		return nil, err
	}

	bserverPrivateKey, err := os.ReadFile(config.ServerPrivateKeyPath)
	if err != nil {
		logger.Error("Can not read private key pem file")
		return nil, err
	}
	bserverPublicKey, err := os.ReadFile(config.StoredPubKey)
	if err != nil {
		logger.Error("Can not read private key pem file")
		return nil, err
	}
	servs := services.NewSendTransactionService(
		app.ChainClient,
		&cardAbi,
		common.HexToAddress(config.CardAddress),
		common.HexToAddress(config.AdminAddress),
	)

	app.CardHandler = network.NewCardEventHandler(
		config,
		servs,
		&cardAbi,
		string(bserverPrivateKey),
		leveldb,
		config.ThirdPartyApiUrl,
		string(bserverPublicKey),
		app.EventChan,
	)

	app.Config = config
	return app, nil
}

func (app *App) Run() {
	app.StopChan = make(chan bool)
	if app.CardHandler != nil {
		app.CardHandler.VerifyPublicKey()
		// app.CardHandler.GetPoolInfo()
	} else {
		logger.Error("CardHandler is nil. Cannot verify public key")
		return
	}
	go app.CardHandler.ListenEvents() // BẮT ĐẦU LẮNG NGHE EVENT
	for {
		select {
		case <-app.StopChan:
			return
		case eventLogs := <-app.EventChan:
			fmt.Println("📩 Event Received:", eventLogs)
			// logger.Debug("📩 Event Received:", eventLogs)
			app.CardHandler.HandleConnectSmartContract(eventLogs)
			
		}
	}
}

func (app *App) Stop() error {
	app.ChainClient.Close()

	logger.Warn("App Stopped")
	return nil
}
