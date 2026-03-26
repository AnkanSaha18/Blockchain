// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============================================================
//  SC-5 · Delivery Orders (PARS Priority Queue)
//  DCBA — Dual-Chain Blockchain Architecture
//
//  UPGRADE v2: Full PARS Priority Queue implemented.
//  Previously orders were stored sequentially — first-come,
//  first-served. Now orders are dispatched by clinical urgency:
//
//    getHighestPriorityOrder()   — returns most urgent PENDING order
//    getPendingOrdersSorted()    — returns all PENDING sorted by parsScore
//    getParsLabel()              — human-readable tier name
//
//  PARS tiers (from research proposal Section 6.2):
//    CRITICAL  90-100  →  3 min  SLA  (υpremium mandatory)
//    HIGH      70-89   → 10 min  SLA  (υpremium preferred)
//    MODERATE  40-69   → 30 min  SLA  (υnormal sufficient)
//    LOW        0-39   →  2 hr   SLA  (υnormal best-effort)
//
//  Priority Queue design note:
//    Solidity has no native heap. We implement O(n) linear scan
//    for getHighestPriorityOrder() — acceptable because concurrent
//    pending orders are expected to be O(10s) not O(1000s).
//    A full min-heap is included as getPendingOrdersSorted() using
//    insertion sort for deterministic, gas-bounded behaviour.
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
        PENDING,      // 0 — submitted, waiting for stock confirmation
        CONFIRMED,    // 1 — stock confirmed, DCS running
        DISPATCHED,   // 2 — UAV picked up the package
        IN_FLIGHT,    // 3 — UAV in the air
        DELIVERED,    // 4 — patient confirmed
        FAILED        // 5 — something went wrong
    }

    // ── PARS tier constants ───────────────────────────────────
    uint8  private constant CRITICAL_MIN  = 90;
    uint8  private constant HIGH_MIN      = 70;
    uint8  private constant MODERATE_MIN  = 40;
    // LOW = anything below 40

    uint256 private constant CRITICAL_SLA  = 3   * 60;       // 180 sec
    uint256 private constant HIGH_SLA      = 10  * 60;       // 600 sec
    uint256 private constant MODERATE_SLA  = 30  * 60;       // 1800 sec
    uint256 private constant LOW_SLA       = 2   * 60 * 60;  // 7200 sec

    // ── Delivery Order struct ─────────────────────────────────
    struct DeliveryOrder {
        uint256     orderId;
        address     hp;
        address     patient;
        bytes32     rxHash;
        uint8       parsScore;
        string      drugList;
        address     warehouse;
        address     droneStation;
        address     assignedUAV;
        OrderStatus status;
        uint256     createdAt;
        uint256     slaDeadline;
        bool        slaBreached;   // set at confirmDelivery if late
    }

    uint256 public orderCount;
    mapping(uint256 => DeliveryOrder) public orders;
    mapping(address => uint256[])     public patientOrders;

    // ── Priority Queue support ────────────────────────────────
    // pendingOrderIds tracks all orders that are still PENDING.
    // This array is maintained by submitOrder() and pruned lazily
    // in getHighestPriorityOrder().
    uint256[] private pendingOrderIds;

    // ── Events ───────────────────────────────────────────────
    event OrderSubmitted(uint256 indexed orderId, address indexed patient, uint8 parsScore, bytes32 rxHash);
    event StockConfirmed(uint256 indexed orderId, address warehouse);
    event UAVAssigned(uint256 indexed orderId, address uav);
    event OrderStatusUpdated(uint256 indexed orderId, OrderStatus newStatus);
    event SLABreached(uint256 indexed orderId, uint8 parsScore, uint256 deliveredAt, uint256 slaDeadline);

    // ── Setup ─────────────────────────────────────────────────
    constructor(address sc1Addr, address sc7Addr) {
        sc1 = ISC1_v5(sc1Addr);
        sc7 = ISC7_v5(sc7Addr);
    }

    // ============================================================
    //  FUNCTION: submitOrder
    //  Unchanged core logic + now adds orderId to pendingOrderIds
    // ============================================================
    function submitOrder(
        address patient,
        bytes32 rxHash,
        uint8   parsScore,
        string  memory drugList,
        address warehouse,
        address droneStation
    ) public returns (uint256) {
        require(sc1.isActive(msg.sender),   "HP not registered");
        require(sc1.isActive(patient),      "Patient not registered");
        require(sc1.isActive(warehouse),    "Warehouse not registered");
        require(sc1.isActive(droneStation), "Drone station not registered");
        require(parsScore <= 100,           "PARS score out of range");

        bool isValid = sc7.verifyHash(rxHash);
        require(isValid, "Prescription not verified by SC-7 oracle");

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
            assignedUAV:  address(0),
            status:       OrderStatus.PENDING,
            createdAt:    block.timestamp,
            slaDeadline:  block.timestamp + sla,
            slaBreached:  false
        });

        patientOrders[patient].push(orderCount);

        // ── Add to priority queue tracking array ──────────────
        pendingOrderIds.push(orderCount);

        emit OrderSubmitted(orderCount, patient, parsScore, rxHash);
        return orderCount;
    }

    // ============================================================
    //  PARS PRIORITY QUEUE — Core new feature
    //
    //  getHighestPriorityOrder():
    //    Scans all currently PENDING orders.
    //    Returns the orderId with the highest parsScore.
    //    Tie-breaking: if two orders have same parsScore, the one
    //    submitted EARLIER (lower orderId) wins — FIFO within a tier.
    //
    //  getParsLabel(score):
    //    Returns human-readable tier string.
    //
    //  getPendingOrdersSorted():
    //    Returns all PENDING order IDs sorted by parsScore DESC.
    //    Insertion sort — O(n²) but n is small in practice.
    // ============================================================

    /// @notice Returns the orderId of the most urgent PENDING order.
    ///         Returns 0 if no PENDING orders exist.
    function getHighestPriorityOrder() public view returns (
        uint256 orderId,
        uint8   parsScore,
        string  memory tier,
        uint256 slaDeadline
    ) {
        uint256 bestId    = 0;
        uint8   bestScore = 0;

        for (uint256 i = 0; i < pendingOrderIds.length; i++) {
            uint256 id = pendingOrderIds[i];
            DeliveryOrder memory o = orders[id];

            // Only consider genuinely PENDING orders (lazy pruning)
            if (o.status != OrderStatus.PENDING) continue;

            if (bestId == 0) {
                // First valid PENDING order found
                bestId    = id;
                bestScore = o.parsScore;
            } else if (o.parsScore > bestScore) {
                // Higher priority score found
                bestId    = id;
                bestScore = o.parsScore;
            }
            // Tie: keep the earlier-submitted one (lower orderId = earlier)
            // which is already held in bestId since we scan in ascending order
        }

        if (bestId == 0) {
            return (0, 0, "NO_PENDING_ORDERS", 0);
        }

        return (
            bestId,
            bestScore,
            getParsLabel(bestScore),
            orders[bestId].slaDeadline
        );
    }

    /// @notice Returns all PENDING order IDs sorted by parsScore DESC.
    ///         Within same parsScore, earlier-submitted orders appear first.
    function getPendingOrdersSorted() public view returns (
        uint256[] memory sortedIds,
        uint8[]   memory scores,
        string[]  memory tiers
    ) {
        // First pass: collect all genuinely PENDING order IDs
        uint256 pendingCount = 0;
        for (uint256 i = 0; i < pendingOrderIds.length; i++) {
            if (orders[pendingOrderIds[i]].status == OrderStatus.PENDING) {
                pendingCount++;
            }
        }

        sortedIds = new uint256[](pendingCount);
        scores    = new uint8[](pendingCount);
        tiers     = new string[](pendingCount);

        uint256 idx = 0;
        for (uint256 i = 0; i < pendingOrderIds.length; i++) {
            uint256 id = pendingOrderIds[i];
            if (orders[id].status == OrderStatus.PENDING) {
                sortedIds[idx] = id;
                scores[idx]    = orders[id].parsScore;
                idx++;
            }
        }

        // Insertion sort by parsScore DESC (stable — preserves orderId order for ties)
        for (uint256 i = 1; i < pendingCount; i++) {
            uint256 keyId    = sortedIds[i];
            uint8   keyScore = scores[i];
            int256  j        = int256(i) - 1;

            while (j >= 0 && scores[uint256(j)] < keyScore) {
                sortedIds[uint256(j + 1)] = sortedIds[uint256(j)];
                scores[uint256(j + 1)]    = scores[uint256(j)];
                j--;
            }
            sortedIds[uint256(j + 1)] = keyId;
            scores[uint256(j + 1)]    = keyScore;
        }

        // Build tier labels
        for (uint256 i = 0; i < pendingCount; i++) {
            tiers[i] = getParsLabel(scores[i]);
        }

        return (sortedIds, scores, tiers);
    }

    /// @notice Count pending orders by PARS tier — useful for RA anomaly monitoring
    function getPendingCountByTier() public view returns (
        uint256 criticalCount,
        uint256 highCount,
        uint256 moderateCount,
        uint256 lowCount
    ) {
        for (uint256 i = 0; i < pendingOrderIds.length; i++) {
            DeliveryOrder memory o = orders[pendingOrderIds[i]];
            if (o.status != OrderStatus.PENDING) continue;

            if (o.parsScore >= CRITICAL_MIN)     criticalCount++;
            else if (o.parsScore >= HIGH_MIN)    highCount++;
            else if (o.parsScore >= MODERATE_MIN) moderateCount++;
            else                                 lowCount++;
        }
        return (criticalCount, highCount, moderateCount, lowCount);
    }

    /// @notice Check how many PENDING orders have already breached their SLA deadline
    function getOverduePendingOrders() public view returns (uint256[] memory overdueIds) {
        uint256 count = 0;
        for (uint256 i = 0; i < pendingOrderIds.length; i++) {
            DeliveryOrder memory o = orders[pendingOrderIds[i]];
            if (o.status == OrderStatus.PENDING && block.timestamp > o.slaDeadline) {
                count++;
            }
        }

        overdueIds = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < pendingOrderIds.length; i++) {
            DeliveryOrder memory o = orders[pendingOrderIds[i]];
            if (o.status == OrderStatus.PENDING && block.timestamp > o.slaDeadline) {
                overdueIds[idx++] = pendingOrderIds[i];
            }
        }
        return overdueIds;
    }

    // ============================================================
    //  EXISTING FUNCTIONS — unchanged core logic
    // ============================================================

    function confirmStock(uint256 orderId) public {
        DeliveryOrder storage order = orders[orderId];
        require(msg.sender == order.warehouse,         "Only the assigned warehouse");
        require(order.status == OrderStatus.PENDING,   "Order not in PENDING state");

        order.status = OrderStatus.CONFIRMED;
        emit StockConfirmed(orderId, msg.sender);
        emit OrderStatusUpdated(orderId, OrderStatus.CONFIRMED);
    }

    function assignUAV(uint256 orderId, address uav) public {
        DeliveryOrder storage order = orders[orderId];
        require(msg.sender == order.droneStation,       "Only the assigned drone station");
        require(order.status == OrderStatus.CONFIRMED,  "Order not CONFIRMED yet");
        require(sc1.isActive(uav),                      "UAV not registered");

        order.assignedUAV = uav;
        order.status      = OrderStatus.DISPATCHED;

        emit UAVAssigned(orderId, uav);
        emit OrderStatusUpdated(orderId, OrderStatus.DISPATCHED);
    }

    function updateStatus(uint256 orderId, OrderStatus newStatus) public {
        require(sc1.isActive(msg.sender), "Caller not registered");
        DeliveryOrder storage order = orders[orderId];

        require(
            msg.sender == order.droneStation || msg.sender == order.assignedUAV,
            "Only DS or assigned UAV can update status"
        );

        // Check SLA breach on delivery
        if (newStatus == OrderStatus.DELIVERED) {
            if (block.timestamp > order.slaDeadline) {
                order.slaBreached = true;
                emit SLABreached(orderId, order.parsScore, block.timestamp, order.slaDeadline);
            }
        }

        order.status = newStatus;
        emit OrderStatusUpdated(orderId, newStatus);
    }

    function getOrder(uint256 orderId) public view returns (
        address     hp,
        address     patient,
        uint8       parsScore,
        string      memory drugList,
        address     assignedUAV,
        OrderStatus status,
        uint256     slaDeadline
    ) {
        DeliveryOrder memory o = orders[orderId];
        return (o.hp, o.patient, o.parsScore, o.drugList, o.assignedUAV, o.status, o.slaDeadline);
    }

    // ── PARS Helpers ──────────────────────────────────────────

    function getSLASeconds(uint8 parsScore) public pure returns (uint256) {
        if (parsScore >= CRITICAL_MIN) return CRITICAL_SLA;
        if (parsScore >= HIGH_MIN)     return HIGH_SLA;
        if (parsScore >= MODERATE_MIN) return MODERATE_SLA;
        return LOW_SLA;
    }

    function getParsLabel(uint8 score) public pure returns (string memory) {
        if (score >= CRITICAL_MIN) return "CRITICAL - 3min SLA";
        if (score >= HIGH_MIN)     return "HIGH - 10min SLA";
        if (score >= MODERATE_MIN) return "MODERATE - 30min SLA";
        return "LOW - 2hr SLA";
    }

    function getParsMinScore(uint8 score) public pure returns (uint8) {
        if (score >= CRITICAL_MIN) return CRITICAL_MIN;
        if (score >= HIGH_MIN)     return HIGH_MIN;
        if (score >= MODERATE_MIN) return MODERATE_MIN;
        return 0;
    }
}
