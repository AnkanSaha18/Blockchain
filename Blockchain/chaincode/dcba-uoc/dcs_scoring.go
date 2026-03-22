package main

import (
	"encoding/json"
	"fmt"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// ── DCS Scoring Chaincode (mirrors SC4 Solidity) ──────────

type DCSContract struct {
	contractapi.Contract
}

type UAVScore struct {
	UAVAddress  string `json:"uavAddress"`
	Score       uint64 `json:"score"`
	SubmittedAt int64  `json:"submittedAt"`
}

type ScoringRound struct {
	OrderID          string     `json:"orderId"`
	DroneStation     string     `json:"droneStation"`
	IsOpen           bool       `json:"isOpen"`
	Winner           string     `json:"winner"`
	WinnerScore      uint64     `json:"winnerScore"`
	SubmissionCount  int        `json:"submissionCount"`
	Participants     []string   `json:"participants"`
	Submissions      []UAVScore `json:"submissions"`
}

func (c *DCSContract) OpenRound(ctx contractapi.TransactionContextInterface, roundID string, orderID string) error {
	existing, _ := ctx.GetStub().GetState("ROUND_" + roundID)
	if existing != nil {
		return fmt.Errorf("round %s already exists", roundID)
	}
	caller, _ := ctx.GetClientIdentity().GetMSPID()
	round := ScoringRound{
		OrderID:      orderID,
		DroneStation: caller,
		IsOpen:       true,
		Participants: []string{},
		Submissions:  []UAVScore{},
	}
	data, _ := json.Marshal(round)
	return ctx.GetStub().PutState("ROUND_"+roundID, data)
}

func (c *DCSContract) SubmitScore(ctx contractapi.TransactionContextInterface, roundID string, uavID string, score uint64) error {
	if score > 100 {
		return fmt.Errorf("score must be 0-100")
	}
	data, err := ctx.GetStub().GetState("ROUND_" + roundID)
	if err != nil || data == nil {
		return fmt.Errorf("round %s not found", roundID)
	}
	var round ScoringRound
	json.Unmarshal(data, &round)
	if !round.IsOpen {
		return fmt.Errorf("round is closed")
	}
	for _, s := range round.Submissions {
		if s.UAVAddress == uavID {
			return fmt.Errorf("UAV already submitted")
		}
	}
	ts, _ := ctx.GetStub().GetTxTimestamp()
	round.Submissions = append(round.Submissions, UAVScore{
		UAVAddress:  uavID,
		Score:       score,
		SubmittedAt: ts.Seconds,
	})
	round.Participants = append(round.Participants, uavID)
	round.SubmissionCount++
	updated, _ := json.Marshal(round)
	return ctx.GetStub().PutState("ROUND_"+roundID, updated)
}

func (c *DCSContract) CloseRound(ctx contractapi.TransactionContextInterface, roundID string) (string, error) {
	data, err := ctx.GetStub().GetState("ROUND_" + roundID)
	if err != nil || data == nil {
		return "", fmt.Errorf("round %s not found", roundID)
	}
	var round ScoringRound
	json.Unmarshal(data, &round)
	if !round.IsOpen {
		return "", fmt.Errorf("round already closed")
	}
	if round.SubmissionCount == 0 {
		return "", fmt.Errorf("no submissions")
	}
	var best UAVScore
	for _, s := range round.Submissions {
		if s.Score > best.Score {
			best = s
		}
	}
	round.IsOpen      = false
	round.Winner      = best.UAVAddress
	round.WinnerScore = best.Score
	updated, _ := json.Marshal(round)
	ctx.GetStub().PutState("ROUND_"+roundID, updated)
	return best.UAVAddress, nil
}

func (c *DCSContract) GetWinner(ctx contractapi.TransactionContextInterface, roundID string) (*UAVScore, error) {
	data, err := ctx.GetStub().GetState("ROUND_" + roundID)
	if err != nil || data == nil {
		return nil, fmt.Errorf("round not found")
	}
	var round ScoringRound
	json.Unmarshal(data, &round)
	if round.IsOpen {
		return nil, fmt.Errorf("round still open")
	}
	return &UAVScore{UAVAddress: round.Winner, Score: round.WinnerScore}, nil
}

func (c *DCSContract) UpdateReputation(ctx contractapi.TransactionContextInterface, uavID string, delta int64) error {
	key := "REP_" + uavID
	data, _ := ctx.GetStub().GetState(key)
	var current int64 = 0
	if data != nil {
		json.Unmarshal(data, &current)
	}
	current += delta
	updated, _ := json.Marshal(current)
	return ctx.GetStub().PutState(key, updated)
}

func (c *DCSContract) GetReputation(ctx contractapi.TransactionContextInterface, uavID string) (int64, error) {
	data, _ := ctx.GetStub().GetState("REP_" + uavID)
	var rep int64 = 0
	if data != nil {
		json.Unmarshal(data, &rep)
	}
	return rep, nil
}