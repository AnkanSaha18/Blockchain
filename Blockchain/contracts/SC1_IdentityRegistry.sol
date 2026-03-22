// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============================================================
//  SC-1 · Identity Registry
//  DCBA — Dual-Chain Blockchain Architecture
// ============================================================
//
//  PURPOSE:
//  This is the "who is who" contract for the whole system.
//  Before any actor (patient, doctor, UAV, warehouse, etc.)
//  can do anything, they must be registered here by the TA
//  (Trusted Authority). Think of it like an ID card issuer.
//
//  ACTORS WHO USE THIS:
//  - TA (Trusted Authority) → registers and revokes everyone
//  - All other contracts    → call isActive() to check IDs
//
//  DEPLOY FIRST. All other contracts depend on this one.
// ============================================================

contract SC1_IdentityRegistry {

    // ── Role labels (just for readability) ──────────────────
    // We store these as plain strings so anyone reading the
    // blockchain can understand who is who.
    // Examples: "patient", "hp", "uav", "warehouse",
    //           "dronestation", "auditor", "miner"

    // ── What we store for each registered actor ──────────────
    struct Actor {
        string  role;           // e.g. "patient" or "uav"
        string  publicKeyHash;  // hash of their public key (DID)
        bool    isActive;       // true = valid, false = revoked
        uint256 registeredAt;   // when they were registered
    }

    // ── Storage ──────────────────────────────────────────────
    address public trustedAuthority;  // the TA who runs this contract

    // address → their Actor info
    mapping(address => Actor) public actors;

    // ── Events (logged on blockchain, useful for debugging) ──
    event ActorRegistered(address indexed who, string role, string publicKeyHash);
    event ActorRevoked(address indexed who, string reason);

    // ── Setup ─────────────────────────────────────────────────
    // The person who deploys this contract becomes the TA.
    constructor() {
        trustedAuthority = msg.sender;
    }

    // ── Modifier: only the TA can call certain functions ─────
    modifier onlyTA() {
        require(msg.sender == trustedAuthority, "Only TA can do this");
        _;
    }

    // ============================================================
    //  FUNCTION: register
    //  Who calls it: TA
    //  What it does: Adds a new actor to the system
    // ============================================================
    function register(
        address who,           // the actor's wallet address
        string memory role,    // their role: "patient", "hp", etc.
        string memory pubKeyHash  // hash of their public key
    ) public onlyTA {
        require(who != address(0), "Invalid address");
        require(!actors[who].isActive, "Already registered and active");

        actors[who] = Actor({
            role:          role,
            publicKeyHash: pubKeyHash,
            isActive:      true,
            registeredAt:  block.timestamp
        });

        emit ActorRegistered(who, role, pubKeyHash);
    }

    // ============================================================
    //  FUNCTION: revoke
    //  Who calls it: TA
    //  What it does: Instantly blocks an actor from the system.
    //  After revocation, isActive() returns false, so all other
    //  contracts will reject that actor's transactions.
    // ============================================================
    function revoke(
        address who,
        string memory reason
    ) public onlyTA {
        require(actors[who].isActive, "Actor not active");
        actors[who].isActive = false;
        emit ActorRevoked(who, reason);
    }

    // ============================================================
    //  FUNCTION: isActive
    //  Who calls it: SC-2, SC-3, SC-4, SC-5, SC-6 (all contracts)
    //  What it does: Simple yes/no check — is this address valid?
    //  This is the most called function in the whole system.
    // ============================================================
    function isActive(address who) public view returns (bool) {
        return actors[who].isActive;
    }

    // ============================================================
    //  FUNCTION: getRole
    //  Who calls it: Anyone, for information
    //  What it does: Returns the role string of an address
    // ============================================================
    function getRole(address who) public view returns (string memory) {
        return actors[who].role;
    }

    // ============================================================
    //  FUNCTION: transferTA
    //  Who calls it: Current TA only
    //  What it does: Passes TA authority to a new address
    //  (e.g. for key rotation or organisational handover)
    // ============================================================
    function transferTA(address newTA) public onlyTA {
        require(newTA != address(0), "Invalid address");
        trustedAuthority = newTA;
    }
}
