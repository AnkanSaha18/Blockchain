// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============================================================
//  SC-7 · Cross-Chain Oracle Bridge
//  DCBA — Dual-Chain Blockchain Architecture
// ============================================================
//
//  PURPOSE:
//  This contract is the "bridge" between the two chains.
//  In the real system, SC-3 lives on PDC (Patient Data Chain)
//  and SC-5 lives on UOC (UAV Operational Chain).
//
//  For Remix/testnet demo, both live on one chain, but this
//  contract still plays the role of the oracle:
//
//  FLOW:
//  1. When a doctor writes a prescription (SC-3), the
//     prescription hash (rxHash) is registered here.
//  2. When a delivery order is submitted (SC-5), SC-7 is
//     asked: "Is this prescription real and unused?"
//  3. SC-7 returns true (VALID) or false (INVALID/EXPIRED).
//  4. Each rxHash can only be verified ONCE — this prevents
//     someone from reusing the same prescription twice.
//     (This is called "replay attack prevention".)
//
//  DEPLOY ORDER: Deploy SC-7 right after SC-1.
// ============================================================

contract SC7_OracleBridge {

    // ── Who controls this oracle ──────────────────────────────
    address public trustedAuthority;  // same TA as SC-1
    address public sc3Address;        // SC-3 is the only one allowed
                                      // to register new hashes

    // ── The status of each prescription hash ─────────────────
    // A prescription hash starts as PENDING (not registered),
    // becomes VALID when SC-3 registers it,
    // and becomes USED once SC-5 verifies it (one-time use).
    enum HashStatus { PENDING, VALID, USED }

    struct PrescriptionRecord {
        HashStatus status;
        uint256    registeredAt;   // when SC-3 added it
        uint256    usedAt;         // when SC-5 consumed it (0 if not yet)
        address    registeredBy;   // which HP address registered it
    }

    // rxHash → its record
    mapping(bytes32 => PrescriptionRecord) public prescriptions;

    // ── Events ───────────────────────────────────────────────
    event HashRegistered(bytes32 indexed rxHash, address indexed hp);
    event HashVerified(bytes32 indexed rxHash, bool valid);

    // ── Setup ─────────────────────────────────────────────────
    constructor() {
        trustedAuthority = msg.sender;
    }

    modifier onlyTA() {
        require(msg.sender == trustedAuthority, "Only TA");
        _;
    }

    // ── Link SC-3 after deployment ────────────────────────────
    // TA calls this once after deploying SC-3, to tell SC-7
    // the address of SC-3 (so only SC-3 can register hashes).
    function setSC3Address(address _sc3) public onlyTA {
        sc3Address = _sc3;
    }

    // ============================================================
    //  FUNCTION: registerHash
    //  Who calls it: SC-3 (automatically when a record is added)
    //  What it does: Marks a prescription hash as VALID so it
    //  can later be verified by SC-5 for delivery.
    // ============================================================
    function registerHash(bytes32 rxHash, address hp) public {
        require(msg.sender == sc3Address, "Only SC-3 can register");
        require(
            prescriptions[rxHash].status == HashStatus.PENDING,
            "Hash already registered"
        );

        prescriptions[rxHash] = PrescriptionRecord({
            status:       HashStatus.VALID,
            registeredAt: block.timestamp,
            usedAt:       0,
            registeredBy: hp
        });

        emit HashRegistered(rxHash, hp);
    }

    // ============================================================
    //  FUNCTION: verifyHash
    //  Who calls it: SC-5 (when HP submits a delivery order)
    //  What it does:
    //    - Returns true  if hash is VALID (prescription is real)
    //    - Returns false if hash is PENDING (never registered)
    //    - Returns false if hash is USED   (already delivered once)
    //  The hash is then marked as USED so it cannot be reused.
    //  This is the replay attack prevention.
    // ============================================================
    function verifyHash(bytes32 rxHash) public returns (bool) {
        // Only SC-5 should call this in the full system.
        // For testnet demo, we allow any registered caller.
        PrescriptionRecord storage rec = prescriptions[rxHash];

        if (rec.status != HashStatus.VALID) {
            emit HashVerified(rxHash, false);
            return false;
        }

        // Mark as USED — cannot be verified again
        rec.status = HashStatus.USED;
        rec.usedAt = block.timestamp;

        emit HashVerified(rxHash, true);
        return true;
    }

    // ============================================================
    //  FUNCTION: checkHash  (read-only, no state change)
    //  Who calls it: Anyone wanting to see the current status
    //  Returns: 0=PENDING, 1=VALID, 2=USED
    // ============================================================
    function checkHash(bytes32 rxHash) public view returns (uint8) {
        return uint8(prescriptions[rxHash].status);
    }
}
