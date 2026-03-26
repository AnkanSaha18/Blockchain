package main

import (
    "encoding/json"
    "fmt"
    "sort"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type OrdersContract struct {
    contractapi.Contract
}

// ── PARS Constants ──────────────────────────────────────────
const (
    CRITICAL_MIN = 90
    HIGH_MIN     = 70
    MODERATE_MIN = 40
)

type DeliveryOrderFabric struct {
    OrderID      string `json:"orderId"`
    HP           string `json:"hp"`
    Patient      string `json:"patient"`
    RxHash       string `json:"rxHash"`
    ParsScore    uint8  `json:"parsScore"`
    DrugList     string `json:"drugList"`
    Warehouse    string `json:"warehouse"`
    DroneStation string `json:"droneStation"`
    AssignedUAV  string `json:"assignedUAV"`
    Status       string `json:"status"` // PENDING/CONFIRMED/DISPATCHED/IN_FLIGHT/DELIVERED
    CreatedAt    int64  `json:"createdAt"`
    SLADeadline  int64  `json:"slaDeadline"`
    SLABreached  bool   `json:"slaBreached"`
}

func orderKey(id string) string { return "FABRIC_ORDER_" + id }

func getSLASeconds(parsScore uint8) int64 {
    if parsScore >= CRITICAL_MIN { return 180 }
    if parsScore >= HIGH_MIN     { return 600 }
    if parsScore >= MODERATE_MIN { return 1800 }
    return 7200
}

func getParsLabel(parsScore uint8) string {
    if parsScore >= CRITICAL_MIN { return "CRITICAL - 3min SLA" }
    if parsScore >= HIGH_MIN     { return "HIGH - 10min SLA" }
    if parsScore >= MODERATE_MIN { return "MODERATE - 30min SLA" }
    return "LOW - 2hr SLA"
}

// SubmitOrder creates a new delivery order
func (c *OrdersContract) SubmitOrder(
    ctx contractapi.TransactionContextInterface,
    orderID string,
    hp string,
    patient string,
    rxHash string,
    parsScore uint8,
    drugList string,
    warehouse string,
    droneStation string,
) error {
    existing, _ := ctx.GetStub().GetState(orderKey(orderID))
    if existing != nil {
        return fmt.Errorf("order %s already exists", orderID)
    }
    ts, _ := ctx.GetStub().GetTxTimestamp()
    sla := getSLASeconds(parsScore)

    order := DeliveryOrderFabric{
        OrderID:      orderID,
        HP:           hp,
        Patient:      patient,
        RxHash:       rxHash,
        ParsScore:    parsScore,
        DrugList:     drugList,
        Warehouse:    warehouse,
        DroneStation: droneStation,
        Status:       "PENDING",
        CreatedAt:    ts.Seconds,
        SLADeadline:  ts.Seconds + sla,
    }
    data, _ := json.Marshal(order)
    return ctx.GetStub().PutState(orderKey(orderID), data)
}

// GetHighestPriorityOrder — returns the most urgent PENDING order
// This is the core PARS priority queue function
func (c *OrdersContract) GetHighestPriorityOrder(
    ctx contractapi.TransactionContextInterface,
    orderIDsJSON string, // JSON array of orderIDs to scan
) (*DeliveryOrderFabric, error) {
    var orderIDs []string
    if err := json.Unmarshal([]byte(orderIDsJSON), &orderIDs); err != nil {
        return nil, fmt.Errorf("invalid order IDs JSON: %s", err)
    }

    var best *DeliveryOrderFabric
    for _, id := range orderIDs {
        data, _ := ctx.GetStub().GetState(orderKey(id))
        if data == nil { continue }

        var order DeliveryOrderFabric
        json.Unmarshal(data, &order)

        if order.Status != "PENDING" { continue }

        if best == nil || order.ParsScore > best.ParsScore {
            best = &order
        }
        // Tie: keep earlier (lower ID order, already first in scan)
    }

    if best == nil {
        return nil, fmt.Errorf("no PENDING orders found")
    }
    return best, nil
}

// GetPendingOrdersSorted — returns all PENDING orders sorted by parsScore DESC
func (c *OrdersContract) GetPendingOrdersSorted(
    ctx contractapi.TransactionContextInterface,
    orderIDsJSON string,
) ([]DeliveryOrderFabric, error) {
    var orderIDs []string
    if err := json.Unmarshal([]byte(orderIDsJSON), &orderIDs); err != nil {
        return nil, fmt.Errorf("invalid order IDs JSON: %s", err)
    }

    var pending []DeliveryOrderFabric
    for _, id := range orderIDs {
        data, _ := ctx.GetStub().GetState(orderKey(id))
        if data == nil { continue }
        var order DeliveryOrderFabric
        json.Unmarshal(data, &order)
        if order.Status == "PENDING" {
            pending = append(pending, order)
        }
    }

    // Sort by ParsScore DESC, stable (preserves insertion order for ties)
    sort.SliceStable(pending, func(i, j int) bool {
        return pending[i].ParsScore > pending[j].ParsScore
    })

    return pending, nil
}

// GetPendingCountByTier — PARS anomaly detection support for RA
func (c *OrdersContract) GetPendingCountByTier(
    ctx contractapi.TransactionContextInterface,
    orderIDsJSON string,
) (map[string]int, error) {
    var orderIDs []string
    if err := json.Unmarshal([]byte(orderIDsJSON), &orderIDs); err != nil {
        return nil, fmt.Errorf("invalid order IDs JSON: %s", err)
    }

    counts := map[string]int{
        "CRITICAL": 0, "HIGH": 0, "MODERATE": 0, "LOW": 0,
    }
    for _, id := range orderIDs {
        data, _ := ctx.GetStub().GetState(orderKey(id))
        if data == nil { continue }
        var order DeliveryOrderFabric
        json.Unmarshal(data, &order)
        if order.Status != "PENDING" { continue }

        switch {
        case order.ParsScore >= CRITICAL_MIN:
            counts["CRITICAL"]++
        case order.ParsScore >= HIGH_MIN:
            counts["HIGH"]++
        case order.ParsScore >= MODERATE_MIN:
            counts["MODERATE"]++
        default:
            counts["LOW"]++
        }
    }
    return counts, nil
}

// GetOrder — read a single order
func (c *OrdersContract) GetOrder(
    ctx contractapi.TransactionContextInterface,
    orderID string,
) (*DeliveryOrderFabric, error) {
    data, err := ctx.GetStub().GetState(orderKey(orderID))
    if err != nil || data == nil {
        return nil, fmt.Errorf("order %s not found", orderID)
    }
    var order DeliveryOrderFabric
    json.Unmarshal(data, &order)
    return &order, nil
}

// UpdateOrderStatus — DS or UAV updates order status
func (c *OrdersContract) UpdateOrderStatus(
    ctx contractapi.TransactionContextInterface,
    orderID string,
    newStatus string,
) error {
    data, err := ctx.GetStub().GetState(orderKey(orderID))
    if err != nil || data == nil {
        return fmt.Errorf("order %s not found", orderID)
    }
    var order DeliveryOrderFabric
    json.Unmarshal(data, &order)

    ts, _ := ctx.GetStub().GetTxTimestamp()
    if newStatus == "DELIVERED" && ts.Seconds > order.SLADeadline {
        order.SLABreached = true
    }

    order.Status = newStatus
    updated, _ := json.Marshal(order)
    return ctx.GetStub().PutState(orderKey(orderID), updated)
}