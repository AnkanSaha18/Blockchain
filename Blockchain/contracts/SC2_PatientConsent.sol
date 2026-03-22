// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============================================================
//  SC-2 · Patient Consent Manager
//  DCBA — Dual-Chain Blockchain Architecture
// ============================================================
//
//  PURPOSE:
//  This contract protects patient data sovereignty.
//  A doctor (HP) can ONLY write a medical record if the
//  patient has explicitly given them permission first.
//
//  Think of it like a time-limited "access token":
//  - Patient grants: "Doctor X can write for the next 7 days"
//  - Patient revokes: "Doctor X access is cancelled NOW"
//  - SC-3 checks: "Does this doctor currently have access?"
//
//  FLOW:
//  1. Patient calls grantAccess(doctorAddress, durationInDays)
//  2. Doctor writes prescription to SC-3
//  3. SC-3 calls hasAccess(doctorAddress, patientAddress)
//     to check the token before allowing the write
//  4. Patient can call revokeAccess(doctorAddress) anytime
//     to immediately cancel — even mid-session
//
//  No fancy encryption here — this is pure access control logic.
// ============================================================

// We need SC-1 to check that both patient and HP are registered
interface ISC1 {
    function isActive(address who) external view returns (bool);
}

contract SC2_PatientConsent {

    ISC1 public sc1;  // reference to the Identity Registry

    // ── What a consent token looks like ──────────────────────
    struct ConsentToken {
        bool    active;      // is this grant currently valid?
        uint256 grantedAt;   // when the patient granted it
        uint256 expiresAt;   // when it automatically expires
        // 0 = never expires (patient revokes manually)
    }

    // Patient address → HP address → their consent token
    // Read as: "patient X has given consent to HP Y"
    mapping(address => mapping(address => ConsentToken)) public consents;

    // ── Events ───────────────────────────────────────────────
    event AccessGranted(address indexed patient, address indexed hp, uint256 expiresAt);
    event AccessRevoked(address indexed patient, address indexed hp);

    // ── Setup ─────────────────────────────────────────────────
    constructor(address sc1Address) {
        sc1 = ISC1(sc1Address);
    }

    // ============================================================
    //  FUNCTION: grantAccess
    //  Who calls it: Patient
    //  What it does: Creates a time-limited consent token
    //  durationDays = 0 means the token never auto-expires
    //  (patient must revoke manually)
    // ============================================================
    function grantAccess(address hp, uint256 durationDays) public {
        // Both patient and HP must be registered in SC-1
        require(sc1.isActive(msg.sender), "Patient not registered in SC-1");
        require(sc1.isActive(hp),         "HP not registered in SC-1");

        uint256 expiresAt = 0;  // 0 = no expiry
        if (durationDays > 0) {
            expiresAt = block.timestamp + (durationDays * 1 days);
        }

        consents[msg.sender][hp] = ConsentToken({
            active:    true,
            grantedAt: block.timestamp,
            expiresAt: expiresAt
        });

        emit AccessGranted(msg.sender, hp, expiresAt);
    }

    // ============================================================
    //  FUNCTION: revokeAccess
    //  Who calls it: Patient
    //  What it does: Immediately cancels the HP's permission.
    //  Works even if the token has not expired yet.
    //  After this, SC-3 will reject any writes from this HP
    //  for this patient.
    // ============================================================
    function revokeAccess(address hp) public {
        require(consents[msg.sender][hp].active, "No active consent to revoke");
        consents[msg.sender][hp].active = false;
        emit AccessRevoked(msg.sender, hp);
    }

    // ============================================================
    //  FUNCTION: hasAccess
    //  Who calls it: SC-3 (before allowing a record write)
    //  What it does: Returns true if HP has valid, non-expired
    //  consent from the patient right now.
    // ============================================================
    function hasAccess(address hp, address patient) public view returns (bool) {
        ConsentToken memory token = consents[patient][hp];

        // Check 1: Was consent ever granted and not revoked?
        if (!token.active) {
            return false;
        }

        // Check 2: Has the token expired?
        // (expiresAt == 0 means it never expires)
        if (token.expiresAt != 0 && block.timestamp > token.expiresAt) {
            return false;
        }

        return true;
    }

    // ============================================================
    //  FUNCTION: getConsentInfo
    //  Who calls it: Anyone (read-only, for inspection)
    //  What it does: Returns the full details of a consent token
    // ============================================================
    function getConsentInfo(
        address patient,
        address hp
    ) public view returns (bool active, uint256 grantedAt, uint256 expiresAt) {
        ConsentToken memory t = consents[patient][hp];
        return (t.active, t.grantedAt, t.expiresAt);
    }
}
