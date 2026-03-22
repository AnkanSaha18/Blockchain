package main

import (
	"fmt"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

func main() {
	dcsContract      := new(DCSContract)
	lifecycleContract := new(LifecycleContract)

	chaincode, err := contractapi.NewChaincode(dcsContract, lifecycleContract)
	if err != nil {
		fmt.Printf("Error creating DCBA UOC chaincode: %s", err)
		return
	}
	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting DCBA UOC chaincode: %s", err)
	}
}