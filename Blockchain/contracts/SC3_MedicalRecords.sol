// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============================================================
//  SC-3 · Medical Records (MBLOCK Store)
//  DCBA — Dual-Chain Blockchain Architecture
// ============================================================
//
//  PURPOSE:
//  This is where medical records (called MBLOCKs) are stored.
//  An MBLOCK is NOT the raw medical data — it is a reference
//  to encrypted data stored off-chain (e.g. IPFS).
//
//  IMPORTANT: In the real system, medical data is encrypted
//  with the patient's public key before uploading to IPFS.
//  Only the patient (with their private key) can decrypt it.
//  On-chain we only store the IPFS hash of that encrypted data.
//
//  THREE CHECKS BEFORE A RECORD IS ACCEPTED:
//  1. HP must be registered in SC-1 (Identity check)
//  2. HP must have patient's consent in SC-2 (Permission check)
//  3. The PARS score must be 0-100 (Valid range check)
//
//  After storing the record, SC-3 automatically registers
//  the prescription hash in SC-7 (oracle bridge) so that
//  SC-5 can later verify it for delivery.
//
//  DEPLOY AFTER: SC-1, SC-2, SC-7
// ============================================================

interface ISC1_v3 {
    function isActive(address who) external view returns (bool);
}
interface ISC2 {
    function hasAccess(address hp, address patient) external view returns (bool);
}
interface ISC7 {
    function registerHash(bytes32 rxHash, address hp) external;
}

contract SC3_MedicalRecords {

    ISC1_v3 public sc1;
    ISC2    public sc2;
    ISC7    public sc7;

    // ── What one medical record looks like on-chain ───────────
    struct MedicalRecord {
        address hp;            // which doctor wrote this
        address patient;       // which patient it belongs to
        string  encryptedDataHash;  // IPFS hash of encrypted MBLOCK
                               // (actual medical data is off-chain,
                               //  encrypted with patient's public key)
        uint8   parsScore;     // priority 0-100 (PARS system)
                               // 90-100 = CRITICAL, 70-89 = HIGH
                               // 40-69 = MODERATE, 0-39 = LOW
        bytes32 rxHash;        // prescription hash (sent to SC-7)
        uint256 timestamp;     // when this record was written
    }

    // Auto-incrementing record ID
    uint256 public recordCount;

    // recordId → MedicalRecord
    mapping(uint256 => MedicalRecord) public records;

    // patient address → list of their record IDs
    mapping(address => uint256[]) public patientRecords;

    // ── Events ───────────────────────────────────────────────
    event RecordAdded(
        uint256 indexed recordId,
        address indexed hp,
        address indexed patient,
        bytes32 rxHash,
        uint8   parsScore
    );

    // ── Setup ─────────────────────────────────────────────────
    constructor(address sc1Addr, address sc2Addr, address sc7Addr) {
        sc1 = ISC1_v3(sc1Addr);
        sc2 = ISC2(sc2Addr);
        sc7 = ISC7(sc7Addr);
    }

    // ============================================================
    //  FUNCTION: addRecord
    //  Who calls it: HP (Healthcare Provider / Doctor)
    //
    //  Parameters:
    //  - patient          : the patient's wallet address
    //  - encryptedDataHash: IPFS hash of the encrypted medical data
    //  - parsScore        : urgency 0-100
    //  - rxHash           : a unique hash for this prescription
    //                       (HP generates this off-chain:
    //                        e.g. keccak256 of prescription content)
    //
    //  What it does:
    //  1. Checks HP is registered
    //  2. Checks HP has patient's consent
    //  3. Stores the record
    //  4. Registers rxHash in SC-7 for delivery pipeline
    // ============================================================
    function addRecord(
        address patient,
        string  memory encryptedDataHash,
        uint8   parsScore,
        bytes32 rxHash
    ) public {
        // Check 1: HP must be registered and active
        require(sc1.isActive(msg.sender), "HP not registered in SC-1");

        // Check 2: HP must have valid patient consent
        require(
            sc2.hasAccess(msg.sender, patient),
            "No patient consent - patient must call SC2.grantAccess first"
        );

        // Check 3: PARS score must be in valid range
        require(parsScore <= 100, "PARS score must be between 0 and 100");

        // Check 4: rxHash must not be empty
        require(rxHash != bytes32(0), "rxHash cannot be empty");

        // Store the record
        recordCount++;
        records[recordCount] = MedicalRecord({
            hp:                msg.sender,
            patient:           patient,
            encryptedDataHash: encryptedDataHash,
            parsScore:         parsScore,
            rxHash:            rxHash,
            timestamp:         block.timestamp
        });

        // Add to patient's record list
        patientRecords[patient].push(recordCount);

        // Automatically register the prescription hash in SC-7
        // so SC-5 can verify it later for delivery
        sc7.registerHash(rxHash, msg.sender);

        emit RecordAdded(recordCount, msg.sender, patient, rxHash, parsScore);
    }

    // ============================================================
    //  FUNCTION: getRecord
    //  Who calls it: Patient, HP, RA (Regulatory Auditor)
    //  What it does: Returns the on-chain data for a record.
    //  Note: The actual medical content is off-chain (IPFS).
    //  This only returns the IPFS hash pointing to it.
    // ============================================================
    function getRecord(uint256 recordId) public view returns (
        address hp,
        address patient,
        string memory encryptedDataHash,
        uint8   parsScore,
        bytes32 rxHash,
        uint256 timestamp
    ) {
        MedicalRecord memory r = records[recordId];
        require(r.timestamp != 0, "Record does not exist");
        return (r.hp, r.patient, r.encryptedDataHash, r.parsScore, r.rxHash, r.timestamp);
    }

    // ============================================================
    //  FUNCTION: getPatientRecordIds
    //  Who calls it: Patient or HP (to list all records)
    //  What it does: Returns all record IDs belonging to a patient
    // ============================================================
    function getPatientRecordIds(address patient) public view returns (uint256[] memory) {
        return patientRecords[patient];
    }

    // ============================================================
    //  HELPER: getParsLabel
    //  What it does: Converts a score to a human-readable label
    // ============================================================
    function getParsLabel(uint8 score) public pure returns (string memory) {
        if (score >= 90) return "CRITICAL";
        if (score >= 70) return "HIGH";
        if (score >= 40) return "MODERATE";
        return "LOW";
    }
}
