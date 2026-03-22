// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============================================================
//  SC-6 · Delivery Lifecycle Manager
//  DCBA — Dual-Chain Blockchain Architecture
// ============================================================
//
//  PURPOSE:
//  This contract tracks the real-world delivery journey
//  from warehouse pickup to patient doorstep.
//
//  STATE MACHINE:
//  PENDING → CONFIRMED → DISPATCHED → IN_FLIGHT → DELIVERED
//                                        ↓ (if problem)
//                                    DEVIATED (re-dispatch)
//
//  KEY FEATURES:
//  1. GPS Logging: UAV submits an IPFS hash every ~1 second
//     during IN_FLIGHT. Each hash points to a GPS coordinate
//     stored off-chain on IPFS. This creates a tamper-proof
//     location trail that RA can audit.
//
//  2. Deviation Detection: DS flags a route anomaly.
//     The order goes to DEVIATED state and needs re-dispatch.
//
//  3. Delivery Confirmation: Patient confirms delivery by
//     providing a simple signature (their address + orderId).
//     This triggers the reputation update in SC-4.
//
//  DEPLOY AFTER: SC-1, SC-4, SC-5
// ============================================================

interface ISC1_v6 {
    function isActive(address who) external view returns (bool);
}
interface ISC4 {
    function updateReputation(address uav, int256 delta) external;
}

contract SC6_DeliveryLifecycle {

    ISC1_v6 public sc1;
    ISC4    public sc4;

    // ── Delivery status (mirrors SC-5 for standalone tracking) ─
    enum DeliveryStatus {
        PENDING,      // 0
        CONFIRMED,    // 1
        DISPATCHED,   // 2
        IN_FLIGHT,    // 3
        DELIVERED,    // 4
        DEVIATED,     // 5 — route anomaly, needs re-dispatch
        FAILED        // 6
    }

    // ── Main delivery tracking record ────────────────────────
    struct Delivery {
        uint256 orderId;
        address assignedUAV;
        address patient;
        address droneStation;
        DeliveryStatus status;
        uint256 startedAt;        // when UAV took off
        uint256 deliveredAt;      // when patient confirmed
        bool    withinSLA;        // was SLA met?
        uint256 slaDeadline;
        uint256 gpsUpdateCount;   // how many GPS logs received
    }

    // ── GPS log entry ─────────────────────────────────────────
    // In real system: UAV uploads GPS coordinates to IPFS,
    // gets back an IPFS content hash, submits that hash here.
    struct GPSLog {
        string  ipfsHash;    // IPFS hash pointing to the GPS data
        uint256 timestamp;
    }

    // orderId → Delivery
    mapping(uint256 => Delivery) public deliveries;

    // orderId → list of GPS logs
    mapping(uint256 => GPSLog[]) public gpsLogs;

    // orderId → whether deviation was flagged
    mapping(uint256 => bool) public deviationFlagged;

    // ── Events ───────────────────────────────────────────────
    event DeliveryCreated(uint256 indexed orderId, address indexed uav, address indexed patient);
    event StatusUpdated(uint256 indexed orderId, DeliveryStatus newStatus);
    event GPSUpdated(uint256 indexed orderId, string ipfsHash, uint256 timestamp);
    event DeviationFlagged(uint256 indexed orderId, address droneStation, string reason);
    event DeliveryConfirmed(uint256 indexed orderId, address patient, bool withinSLA);

    // ── Setup ─────────────────────────────────────────────────
    constructor(address sc1Addr, address sc4Addr) {
        sc1 = ISC1_v6(sc1Addr);
        sc4 = ISC4(sc4Addr);
    }

    // ============================================================
    //  FUNCTION: createDelivery
    //  Who calls it: Drone Station (DS) after UAV is assigned
    //  What it does: Sets up the tracking record for this delivery
    // ============================================================
    function createDelivery(
        uint256 orderId,
        address uav,
        address patient,
        uint256 slaDeadline
    ) public {
        require(sc1.isActive(msg.sender), "DS not registered");
        require(sc1.isActive(uav),        "UAV not registered");
        require(deliveries[orderId].startedAt == 0, "Delivery already created");

        deliveries[orderId] = Delivery({
            orderId:        orderId,
            assignedUAV:    uav,
            patient:        patient,
            droneStation:   msg.sender,
            status:         DeliveryStatus.DISPATCHED,
            startedAt:      block.timestamp,
            deliveredAt:    0,
            withinSLA:      false,
            slaDeadline:    slaDeadline,
            gpsUpdateCount: 0
        });

        emit DeliveryCreated(orderId, uav, patient);
        emit StatusUpdated(orderId, DeliveryStatus.DISPATCHED);
    }

    // ============================================================
    //  FUNCTION: setInFlight
    //  Who calls it: UAV (when it takes off)
    //  What it does: Marks delivery as IN_FLIGHT, GPS logging begins
    // ============================================================
    function setInFlight(uint256 orderId) public {
        Delivery storage d = deliveries[orderId];
        require(msg.sender == d.assignedUAV, "Only the assigned UAV");
        require(d.status == DeliveryStatus.DISPATCHED, "Not in DISPATCHED state");

        d.status = DeliveryStatus.IN_FLIGHT;
        emit StatusUpdated(orderId, DeliveryStatus.IN_FLIGHT);
    }

    // ============================================================
    //  FUNCTION: logGPS
    //  Who calls it: UAV (every ~1 second during IN_FLIGHT)
    //
    //  Parameters:
    //  - orderId  : which delivery this GPS log belongs to
    //  - ipfsHash : IPFS content hash of the GPS data
    //               (off-chain: UAV uploads coordinates to IPFS,
    //                gets this hash back, then calls this function)
    //
    //  What it does: Appends an IPFS hash to the GPS trail.
    //  This creates an immutable, tamper-evident location record.
    // ============================================================
    function logGPS(uint256 orderId, string memory ipfsHash) public {
        Delivery storage d = deliveries[orderId];
        require(msg.sender == d.assignedUAV, "Only assigned UAV can log GPS");
        require(d.status == DeliveryStatus.IN_FLIGHT, "UAV not in flight");

        gpsLogs[orderId].push(GPSLog({
            ipfsHash:  ipfsHash,
            timestamp: block.timestamp
        }));

        d.gpsUpdateCount++;
        emit GPSUpdated(orderId, ipfsHash, block.timestamp);
    }

    // ============================================================
    //  FUNCTION: flagDeviation
    //  Who calls it: Drone Station (DS) monitoring the GPS feed
    //  What it does: Marks the delivery as deviated.
    //  The DS can then trigger a new DCS round (SC-4) to
    //  assign a replacement UAV.
    // ============================================================
    function flagDeviation(uint256 orderId, string memory reason) public {
        Delivery storage d = deliveries[orderId];
        require(msg.sender == d.droneStation, "Only assigned DS");
        require(d.status == DeliveryStatus.IN_FLIGHT, "UAV not in flight");

        d.status = DeliveryStatus.DEVIATED;
        deviationFlagged[orderId] = true;

        // Penalise the UAV reputation for deviating
        sc4.updateReputation(d.assignedUAV, -10);

        emit DeviationFlagged(orderId, msg.sender, reason);
        emit StatusUpdated(orderId, DeliveryStatus.DEVIATED);
    }

    // ============================================================
    //  FUNCTION: confirmDelivery
    //  Who calls it: Patient (when they physically receive the drugs)
    //  What it does:
    //  1. Marks delivery as DELIVERED
    //  2. Checks if SLA was met
    //  3. Updates UAV reputation in SC-4:
    //     +5 if on time, -5 if late
    // ============================================================
    function confirmDelivery(uint256 orderId) public {
        Delivery storage d = deliveries[orderId];
        require(msg.sender == d.patient, "Only the patient can confirm delivery");
        require(d.status == DeliveryStatus.IN_FLIGHT || d.status == DeliveryStatus.DISPATCHED,
                "Delivery not in progress");

        d.status      = DeliveryStatus.DELIVERED;
        d.deliveredAt = block.timestamp;

        // Was SLA met?
        bool onTime = (block.timestamp <= d.slaDeadline);
        d.withinSLA = onTime;

        // Update UAV reputation
        if (onTime) {
            sc4.updateReputation(d.assignedUAV, 5);   // on-time bonus
        } else {
            sc4.updateReputation(d.assignedUAV, -5);  // late penalty
        }

        emit DeliveryConfirmed(orderId, msg.sender, onTime);
        emit StatusUpdated(orderId, DeliveryStatus.DELIVERED);
    }

    // ============================================================
    //  FUNCTION: getDeliveryStatus
    //  Who calls it: Anyone (read-only)
    // ============================================================
    function getDeliveryStatus(uint256 orderId) public view returns (
        DeliveryStatus status,
        address uav,
        uint256 gpsUpdateCount,
        bool    withinSLA,
        bool    deviated
    ) {
        Delivery memory d = deliveries[orderId];
        return (d.status, d.assignedUAV, d.gpsUpdateCount, d.withinSLA, deviationFlagged[orderId]);
    }

    // ============================================================
    //  FUNCTION: getGPSLog
    //  Who calls it: RA (Regulatory Auditor) for audit
    //  What it does: Returns the full GPS trail for a delivery
    //  (list of IPFS hashes + timestamps)
    // ============================================================
    function getGPSLog(uint256 orderId) public view returns (
        string[] memory hashes,
        uint256[] memory timestamps
    ) {
        GPSLog[] memory logs = gpsLogs[orderId];
        string[]  memory h = new string[](logs.length);
        uint256[] memory t = new uint256[](logs.length);

        for (uint256 i = 0; i < logs.length; i++) {
            h[i] = logs[i].ipfsHash;
            t[i] = logs[i].timestamp;
        }
        return (h, t);
    }
}
