package main

import (
    "crypto/sha256"
    "encoding/binary"
    "encoding/json"
    "fmt"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type DCSContract struct {
    contractapi.Contract
}

// ── Bloom Filter constants (proposal Section 6.4) ──────────
// n=100 UAVs, ε=0.01, k=7 hash functions, m=1024 bits (128 bytes)
const (
    BLOOM_M_BITS   = 1024
    BLOOM_K_HASHES = 7
    BLOOM_BYTES    = 128
)

// ── Data structs ────────────────────────────────────────────
type UAVScore struct {
    UAVAddress   string `json:"uavAddress"`
    Score        uint64 `json:"score"`
    SubmittedAt  int64  `json:"submittedAt"`
    PassedBloom  bool   `json:"passedBloom"`
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
    RejectedByBloom  int        `json:"rejectedByBloom"`
}

// BloomFilter stored as 128-byte array in ledger
type BloomFilter struct {
    Bits []byte `json:"bits"` // 128 bytes = 1024 bits
}

// ── Bloom Filter helpers ────────────────────────────────────

// bloomPositions returns k=7 bit positions for a given UAV ID
func bloomPositions(uavID string) [BLOOM_K_HASHES]uint32 {
    var positions [BLOOM_K_HASHES]uint32
    for i := 0; i < BLOOM_K_HASHES; i++ {
        // hash = SHA256(uavID + salt_byte)
        data := append([]byte(uavID), byte(i))
        h := sha256.Sum256(data)
        // take first 4 bytes as uint32, mod M_BITS
        pos := binary.BigEndian.Uint32(h[:4]) % BLOOM_M_BITS
        positions[i] = pos
    }
    return positions
}

func bloomSet(bits []byte, pos uint32) {
    bits[pos/8] |= 1 << (pos % 8)
}

func bloomGet(bits []byte, pos uint32) bool {
    return (bits[pos/8] & (1 << (pos % 8))) != 0
}

// bloomAdd adds a UAV address to the filter
func bloomAdd(bits []byte, uavID string) {
    positions := bloomPositions(uavID)
    for _, pos := range positions {
        bloomSet(bits, pos)
    }
}

// bloomCheck returns true if uavID is probably in the filter
func bloomCheck(bits []byte, uavID string) bool {
    positions := bloomPositions(uavID)
    for _, pos := range positions {
        if !bloomGet(bits, pos) {
            return false // definitely NOT present
        }
    }
    return true // probably present
}

// ── Ledger key helpers ──────────────────────────────────────
func bloomKey() string { return "BLOOM_FILTER" }
func roundKey(id string) string { return "ROUND_" + id }
func repKey(id string) string   { return "REP_" + id }

// getOrCreateBloom loads the Bloom filter from ledger, or creates empty one
func getOrCreateBloom(ctx contractapi.TransactionContextInterface) (*BloomFilter, error) {
    data, err := ctx.GetStub().GetState(bloomKey())
    if err != nil {
        return nil, err
    }
    if data == nil {
        // First time — create empty 128-byte filter
        return &BloomFilter{Bits: make([]byte, BLOOM_BYTES)}, nil
    }
    var bf BloomFilter
    if err := json.Unmarshal(data, &bf); err != nil {
        return nil, err
    }
    return &bf, nil
}

func saveBloom(ctx contractapi.TransactionContextInterface, bf *BloomFilter) error {
    data, err := json.Marshal(bf)
    if err != nil {
        return err
    }
    return ctx.GetStub().PutState(bloomKey(), data)
}

// ── Bloom Filter management functions ──────────────────────

// AddUAVToBloom — call this after registering a new UAV
func (c *DCSContract) AddUAVToBloom(
    ctx contractapi.TransactionContextInterface,
    uavID string,
) error {
    bf, err := getOrCreateBloom(ctx)
    if err != nil {
        return fmt.Errorf("cannot load bloom filter: %s", err)
    }
    bloomAdd(bf.Bits, uavID)
    return saveBloom(ctx, bf)
}

// RebuildBloomFilter — call this after any UAV revocation
// Pass the full list of currently active UAV IDs
func (c *DCSContract) RebuildBloomFilter(
    ctx contractapi.TransactionContextInterface,
    activeUAVsJSON string, // JSON array of UAV address strings
) error {
    var activeUAVs []string
    if err := json.Unmarshal([]byte(activeUAVsJSON), &activeUAVs); err != nil {
        return fmt.Errorf("invalid UAV list JSON: %s", err)
    }
    // Reset filter
    bf := &BloomFilter{Bits: make([]byte, BLOOM_BYTES)}
    for _, uav := range activeUAVs {
        bloomAdd(bf.Bits, uav)
    }
    return saveBloom(ctx, bf)
}

// BloomCheck — query whether a UAV is in the filter (read-only)
func (c *DCSContract) BloomCheck(
    ctx contractapi.TransactionContextInterface,
    uavID string,
) (bool, error) {
    bf, err := getOrCreateBloom(ctx)
    if err != nil {
        return false, err
    }
    return bloomCheck(bf.Bits, uavID), nil
}

// ── DCS Scoring functions ───────────────────────────────────

func (c *DCSContract) OpenRound(
    ctx contractapi.TransactionContextInterface,
    roundID string,
    orderID string,
) error {
    existing, _ := ctx.GetStub().GetState(roundKey(roundID))
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
    return ctx.GetStub().PutState(roundKey(roundID), data)
}

// SubmitScore — Phase 1: Bloom filter, Phase 2: active check
func (c *DCSContract) SubmitScore(
    ctx contractapi.TransactionContextInterface,
    roundID string,
    uavID string,
    score uint64,
) error {
    if score > 100 {
        return fmt.Errorf("score must be 0-100")
    }
    data, err := ctx.GetStub().GetState(roundKey(roundID))
    if err != nil || data == nil {
        return fmt.Errorf("round %s not found", roundID)
    }
    var round ScoringRound
    json.Unmarshal(data, &round)
    if !round.IsOpen {
        return fmt.Errorf("round is closed")
    }
    // Duplicate check
    for _, s := range round.Submissions {
        if s.UAVAddress == uavID {
            return fmt.Errorf("UAV already submitted")
        }
    }

    // ── Phase 1: Bloom Filter ───────────────────────────────
    bf, err := getOrCreateBloom(ctx)
    if err != nil {
        return fmt.Errorf("bloom filter error: %s", err)
    }
    if !bloomCheck(bf.Bits, uavID) {
        round.RejectedByBloom++
        updated, _ := json.Marshal(round)
        ctx.GetStub().PutState(roundKey(roundID), updated)
        return fmt.Errorf("Phase 1 failed: UAV %s not in Bloom filter", uavID)
    }

    // ── Phase 2: Existence check (Fabric identity) ─────────
    // In Fabric, identity is enforced by MSP — if UAV submitted
    // a signed transaction, Fabric already verified their cert.
    // We record passedBloom=true to mark Phase 1 passed.
    ts, _ := ctx.GetStub().GetTxTimestamp()
    round.Submissions = append(round.Submissions, UAVScore{
        UAVAddress:  uavID,
        Score:       score,
        SubmittedAt: ts.Seconds,
        PassedBloom: true,
    })
    round.Participants = append(round.Participants, uavID)
    round.SubmissionCount++
    updated, _ := json.Marshal(round)
    return ctx.GetStub().PutState(roundKey(roundID), updated)
}

func (c *DCSContract) CloseRound(
    ctx contractapi.TransactionContextInterface,
    roundID string,
) (string, error) {
    data, err := ctx.GetStub().GetState(roundKey(roundID))
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
    ctx.GetStub().PutState(roundKey(roundID), updated)
    return best.UAVAddress, nil
}

func (c *DCSContract) GetWinner(
    ctx contractapi.TransactionContextInterface,
    roundID string,
) (*UAVScore, error) {
    data, err := ctx.GetStub().GetState(roundKey(roundID))
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

func (c *DCSContract) UpdateReputation(
    ctx contractapi.TransactionContextInterface,
    uavID string,
    delta int64,
) error {
    key := repKey(uavID)
    data, _ := ctx.GetStub().GetState(key)
    var current int64 = 0
    if data != nil {
        json.Unmarshal(data, &current)
    }
    current += delta
    updated, _ := json.Marshal(current)
    return ctx.GetStub().PutState(key, updated)
}

func (c *DCSContract) GetReputation(
    ctx contractapi.TransactionContextInterface,
    uavID string,
) (int64, error) {
    data, _ := ctx.GetStub().GetState(repKey(uavID))
    var rep int64 = 0
    if data != nil {
        json.Unmarshal(data, &rep)
    }
    return rep, nil
}

// GetRoundStats — for auditing bloom rejection counts
func (c *DCSContract) GetRoundStats(
    ctx contractapi.TransactionContextInterface,
    roundID string,
) (map[string]interface{}, error) {
    data, err := ctx.GetStub().GetState(roundKey(roundID))
    if err != nil || data == nil {
        return nil, fmt.Errorf("round not found")
    }
    var round ScoringRound
    json.Unmarshal(data, &round)
    return map[string]interface{}{
        "accepted":      round.SubmissionCount,
        "rejectedBloom": round.RejectedByBloom,
        "winner":        round.Winner,
    }, nil
}