// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============================================================
//  SC-5 · Delivery Orders (PARS Queue)
//  DCBA — Dual-Chain Blockchain Architecture
// ============================================================
//
//  PURPOSE:
//  This contract manages the delivery order queue.
//  Orders are NOT processed first-come-first-served.
//  They are processed by PRIORITY (the PARS score from SC-3).
//
//  PARS TIERS:
//  CRITICAL (90-100): Deliver within 3 minutes  — life-critical meds
//  HIGH     (70-89):  Deliver within 10 minutes — urgent meds
//  MODERATE (40-69):  Deliver within 30 minutes — routine meds
//  LOW      (0-39):   Deliver within 2 hours    — non-urgent
//
//  FLOW:
//  1. HP calls submitOrder() with the prescription hash + PARS score
//  2. SC-5 calls SC-7 to verify the prescription is real
//  3. If valid, order is stored and assigned to a Warehouse + DS
//  4. Warehouse calls confirmStock() to say drugs are ready
//  5. SC-5 emits an event → DS picks it up and runs DCS (SC-4)
//
//  DEPLOY AFTER: SC-1, SC-3, SC-7
// ============================================================

interface ISC1_v5 {
    function isActive(address who) external view returns (bool);
}
interface ISC7_v5 {
    function verifyHash(bytes32 rxHash) external returns (bool);
}

contract SC5_DeliveryOrders {

    ISC1_v5 public sc1;
    ISC7_v5 public sc7;

    // ── Order status lifecycle ────────────────────────────────
    enum OrderStatus {
        PENDING,      // submitted, waiting for stock confirmation
        CONFIRMED,    // stock confirmed, DCS running
        DISPATCHED,   // UAV picked up the package
        IN_FLIGHT,    // UAV is in the air, GPS streaming
        DELIVERED,    // patient confirmed delivery
        FAILED        // something went wrong
    }

    // ── What a delivery order looks like ─────────────────────
    struct DeliveryOrder {
        uint256     orderId;
        address     hp;           // who prescribed
        address     patient;      // who receives it
        bytes32     rxHash;       // prescription hash (verified by SC-7)
        uint8       parsScore;    // priority 0-100
        string      drugList;     // what drugs (plain text for demo)
        address     warehouse;    // which warehouse fulfils it
        address     droneStation; // which DS manages the UAV
        address     assignedUAV;  // the υpremium UAV
        OrderStatus status;
        uint256     createdAt;
        uint256     slaDeadline;  // when it must be delivered by
    }

    uint256 public orderCount;
    mapping(uint256 => DeliveryOrder) public orders;

    // patient → list of their order IDs
    mapping(address => uint256[]) public patientOrders;

    // ── Events ───────────────────────────────────────────────
    event OrderSubmitted(uint256 indexed orderId, address indexed patient, uint8 parsScore, bytes32 rxHash);
    event StockConfirmed(uint256 indexed orderId, address warehouse);
    event UAVAssigned(uint256 indexed orderId, address uav);
    event OrderStatusUpdated(uint256 indexed orderId, OrderStatus newStatus);

    // ── Setup ─────────────────────────────────────────────────
    constructor(address sc1Addr, address sc7Addr) {
        sc1 = ISC1_v5(sc1Addr);
        sc7 = ISC7_v5(sc7Addr);
    }

    // ============================================================
    //  FUNCTION: submitOrder
    //  Who calls it: HP (Healthcare Provider)
    //
    //  Parameters:
    //  - patient      : patient's wallet address
    //  - rxHash       : the prescription hash from SC-3
    //  - parsScore    : urgency (0-100), same as in SC-3
    //  - drugList     : plain text list of drugs
    //  - warehouse    : address of the drug warehouse to use
    //  - droneStation : address of the drone station to use
    //
    //  What it does:
    //  1. Verifies HP is registered
    //  2. Asks SC-7: is this prescription real and unused?
    //  3. If yes, creates the order with SLA deadline
    //  4. SLA deadline = now + (time based on PARS tier)
    // ============================================================
    function submitOrder(
        address patient,
        bytes32 rxHash,
        uint8   parsScore,
        string  memory drugList,
        address warehouse,
        address droneStation
    ) public returns (uint256) {
        require(sc1.isActive(msg.sender), "HP not registered");
        require(sc1.isActive(patient),    "Patient not registered");
        require(sc1.isActive(warehouse),  "Warehouse not registered");
        require(sc1.isActive(droneStation), "Drone station not registered");
        require(parsScore <= 100,         "PARS score out of range");

        // Ask SC-7: is this prescription valid?
        bool isValid = sc7.verifyHash(rxHash);
        require(isValid, "Prescription not verified by SC-7 oracle");

        // Calculate SLA deadline based on PARS score
        uint256 sla = getSLASeconds(parsScore);

        orderCount++;
        orders[orderCount] = DeliveryOrder({
            orderId:      orderCount,
            hp:           msg.sender,
            patient:      patient,
            rxHash:       rxHash,
            parsScore:    parsScore,
            drugList:     drugList,
            warehouse:    warehouse,
            droneStation: droneStation,
            assignedUAV:  address(0),  // assigned after DCS
            status:       OrderStatus.PENDING,
            createdAt:    block.timestamp,
            slaDeadline:  block.timestamp + sla
        });

        patientOrders[patient].push(orderCount);

        emit OrderSubmitted(orderCount, patient, parsScore, rxHash);
        return orderCount;
    }

    // ============================================================
    //  FUNCTION: confirmStock
    //  Who calls it: Drug Warehouse (DW)
    //  What it does: Warehouse says "yes, drugs are available"
    //  Moves order from PENDING → CONFIRMED
    // ============================================================
    function confirmStock(uint256 orderId) public {
        DeliveryOrder storage order = orders[orderId];
        require(msg.sender == order.warehouse, "Only the assigned warehouse");
        require(order.status == OrderStatus.PENDING, "Order not in PENDING state");

        order.status = OrderStatus.CONFIRMED;
        emit StockConfirmed(orderId, msg.sender);
        emit OrderStatusUpdated(orderId, OrderStatus.CONFIRMED);
    }

    // ============================================================
    //  FUNCTION: assignUAV
    //  Who calls it: Drone Station (DS) after SC-4 picks winner
    //  What it does: Records which UAV won the DCS round
    //  Moves order to DISPATCHED
    // ============================================================
    function assignUAV(uint256 orderId, address uav) public {
        DeliveryOrder storage order = orders[orderId];
        require(msg.sender == order.droneStation, "Only the assigned drone station");
        require(order.status == OrderStatus.CONFIRMED, "Order not CONFIRMED yet");
        require(sc1.isActive(uav), "UAV not registered");

        order.assignedUAV = uav;
        order.status      = OrderStatus.DISPATCHED;

        emit UAVAssigned(orderId, uav);
        emit OrderStatusUpdated(orderId, OrderStatus.DISPATCHED);
    }

    // ============================================================
    //  FUNCTION: updateStatus
    //  Who calls it: DS or UAV (to move through lifecycle states)
    //  What it does: Advances the order to the next status
    //  SC-6 also calls this internally.
    // ============================================================
    function updateStatus(uint256 orderId, OrderStatus newStatus) public {
        require(sc1.isActive(msg.sender), "Caller not registered");
        DeliveryOrder storage order = orders[orderId];

        // Basic checks — DS or assigned UAV can update
        require(
            msg.sender == order.droneStation || msg.sender == order.assignedUAV,
            "Only DS or assigned UAV can update status"
        );

        order.status = newStatus;
        emit OrderStatusUpdated(orderId, newStatus);
    }

    // ============================================================
    //  FUNCTION: getOrder
    //  Who calls it: Anyone (read-only)
    // ============================================================
    function getOrder(uint256 orderId) public view returns (
        address hp,
        address patient,
        uint8   parsScore,
        string  memory drugList,
        address assignedUAV,
        OrderStatus status,
        uint256 slaDeadline
    ) {
        DeliveryOrder memory o = orders[orderId];
        return (o.hp, o.patient, o.parsScore, o.drugList, o.assignedUAV, o.status, o.slaDeadline);
    }

    // ============================================================
    //  HELPER: getSLASeconds
    //  What it does: Converts PARS score to SLA deadline in seconds
    // ============================================================
    function getSLASeconds(uint8 parsScore) public pure returns (uint256) {
        if (parsScore >= 90) return 3  * 60;          // CRITICAL: 3 minutes
        if (parsScore >= 70) return 10 * 60;          // HIGH:     10 minutes
        if (parsScore >= 40) return 30 * 60;          // MODERATE: 30 minutes
        return                      2  * 60 * 60;     // LOW:      2 hours
    }

    // ============================================================
    //  HELPER: getParsLabel (same as SC-3, repeated for convenience)
    // ============================================================
    function getParsLabel(uint8 score) public pure returns (string memory) {
        if (score >= 90) return "CRITICAL - 3min SLA";
        if (score >= 70) return "HIGH - 10min SLA";
        if (score >= 40) return "MODERATE - 30min SLA";
        return "LOW - 2hr SLA";
    }
}
