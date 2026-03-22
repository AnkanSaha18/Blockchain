package main

import (
	"encoding/json"
	"fmt"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type LifecycleContract struct {
	contractapi.Contract
}

type GPSLog struct {
	IPFSHash  string `json:"ipfsHash"`
	Timestamp int64  `json:"timestamp"`
}

type Delivery struct {
	OrderID        string   `json:"orderId"`
	AssignedUAV    string   `json:"assignedUAV"`
	Patient        string   `json:"patient"`
	DroneStation   string   `json:"droneStation"`
	Status         string   `json:"status"` // DISPATCHED/IN_FLIGHT/DELIVERED/DEVIATED
	StartedAt      int64    `json:"startedAt"`
	DeliveredAt    int64    `json:"deliveredAt"`
	SLADeadline    int64    `json:"slaDeadline"`
	WithinSLA      bool     `json:"withinSLA"`
	GPSLogs        []GPSLog `json:"gpsLogs"`
	GPSUpdateCount int      `json:"gpsUpdateCount"`
	Deviated       bool     `json:"deviated"`
}

func (c *LifecycleContract) CreateDelivery(ctx contractapi.TransactionContextInterface,
	orderID string, uavID string, patient string, slaDeadline int64) error {

	existing, _ := ctx.GetStub().GetState("DEL_" + orderID)
	if existing != nil {
		return fmt.Errorf("delivery %s already exists", orderID)
	}
	ts, _ := ctx.GetStub().GetTxTimestamp()
	caller, _ := ctx.GetClientIdentity().GetMSPID()
	d := Delivery{
		OrderID:      orderID,
		AssignedUAV:  uavID,
		Patient:      patient,
		DroneStation: caller,
		Status:       "DISPATCHED",
		StartedAt:    ts.Seconds,
		SLADeadline:  slaDeadline,
		GPSLogs:      []GPSLog{},
	}
	data, _ := json.Marshal(d)
	return ctx.GetStub().PutState("DEL_"+orderID, data)
}

func (c *LifecycleContract) SetInFlight(ctx contractapi.TransactionContextInterface, orderID string) error {
	data, err := ctx.GetStub().GetState("DEL_" + orderID)
	if err != nil || data == nil {
		return fmt.Errorf("delivery not found")
	}
	var d Delivery
	json.Unmarshal(data, &d)
	if d.Status != "DISPATCHED" {
		return fmt.Errorf("delivery not in DISPATCHED state")
	}
	d.Status = "IN_FLIGHT"
	updated, _ := json.Marshal(d)
	return ctx.GetStub().PutState("DEL_"+orderID, updated)
}

func (c *LifecycleContract) LogGPS(ctx contractapi.TransactionContextInterface, orderID string, ipfsHash string) error {
	data, err := ctx.GetStub().GetState("DEL_" + orderID)
	if err != nil || data == nil {
		return fmt.Errorf("delivery not found")
	}
	var d Delivery
	json.Unmarshal(data, &d)
	if d.Status != "IN_FLIGHT" {
		return fmt.Errorf("UAV not in flight")
	}
	ts, _ := ctx.GetStub().GetTxTimestamp()
	d.GPSLogs = append(d.GPSLogs, GPSLog{IPFSHash: ipfsHash, Timestamp: ts.Seconds})
	d.GPSUpdateCount++
	updated, _ := json.Marshal(d)
	return ctx.GetStub().PutState("DEL_"+orderID, updated)
}

func (c *LifecycleContract) FlagDeviation(ctx contractapi.TransactionContextInterface, orderID string, reason string) error {
	data, err := ctx.GetStub().GetState("DEL_" + orderID)
	if err != nil || data == nil {
		return fmt.Errorf("delivery not found")
	}
	var d Delivery
	json.Unmarshal(data, &d)
	if d.Status != "IN_FLIGHT" {
		return fmt.Errorf("UAV not in flight")
	}
	d.Status   = "DEVIATED"
	d.Deviated = true
	updated, _ := json.Marshal(d)
	return ctx.GetStub().PutState("DEL_"+orderID, updated)
}

func (c *LifecycleContract) ConfirmDelivery(ctx contractapi.TransactionContextInterface, orderID string) error {
	data, err := ctx.GetStub().GetState("DEL_" + orderID)
	if err != nil || data == nil {
		return fmt.Errorf("delivery not found")
	}
	var d Delivery
	json.Unmarshal(data, &d)
	ts, _ := ctx.GetStub().GetTxTimestamp()
	d.Status      = "DELIVERED"
	d.DeliveredAt = ts.Seconds
	d.WithinSLA   = ts.Seconds <= d.SLADeadline
	updated, _ := json.Marshal(d)
	return ctx.GetStub().PutState("DEL_"+orderID, updated)
}

func (c *LifecycleContract) GetDelivery(ctx contractapi.TransactionContextInterface, orderID string) (*Delivery, error) {
	data, err := ctx.GetStub().GetState("DEL_" + orderID)
	if err != nil || data == nil {
		return nil, fmt.Errorf("delivery not found")
	}
	var d Delivery
	json.Unmarshal(data, &d)
	return &d, nil
}