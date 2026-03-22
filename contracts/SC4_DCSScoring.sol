// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============================================================
//  SC-4 · DCS — Drone Capability Score
//  DCBA — Dual-Chain Blockchain Architecture
//  FIX: added sc6Address so SC6 contract can call updateReputation
// ============================================================

interface ISC1_v4 {
    function isActive(address who) external view returns (bool);
    function getRole(address who) external view returns (string memory);
}

contract SC4_DCSScoring {

    ISC1_v4 public sc1;

    // ── FIX: SC6 contract address authorized to call updateReputation ──
    address public sc6Address;

    struct UAVScore {
        address uavAddress;
        uint256 score;
        uint256 submittedAt;
        bool    verified;
    }

    struct ScoringRound {
        uint256   orderId;
        address   droneStation;
        bool      isOpen;
        address   winner;
        uint256   winnerScore;
        uint256   submissionCount;
    }

    mapping(uint256 => ScoringRound)                      public rounds;
    mapping(uint256 => mapping(address => UAVScore))       public submissions;
    mapping(uint256 => address[])                          public roundParticipants;
    mapping(address => int256)                             public reputationScore;

    uint256 public roundCount;

    event RoundOpened(uint256 indexed roundId, uint256 orderId, address droneStation);
    event ScoreSubmitted(uint256 indexed roundId, address indexed uav, uint256 score);
    event WinnerSelected(uint256 indexed roundId, address indexed winner, uint256 score);
    event ReputationUpdated(address indexed uav, int256 delta, int256 newScore);

    constructor(address sc1Addr) {
        sc1 = ISC1_v4(sc1Addr);
    }

    // ── FIX: TA calls this once after deploying SC6 ────────────────
    // This allows SC6's contract address to call updateReputation
    function linkSC6(address _sc6) public {
        require(sc6Address == address(0), "SC6 already linked");
        require(_sc6 != address(0), "Invalid address");
        sc6Address = _sc6;
    }

    function computeScore(
        uint256 speed,
        uint256 payload,
        uint256 battery,
        uint256 cpu,
        uint256 ram
    ) public pure returns (uint256) {
        require(speed <= 100 && payload <= 100 && battery <= 100, "Metrics must be 0-100");
        require(cpu <= 100 && ram <= 100, "Metrics must be 0-100");
        uint256 total = (speed * 30) + (payload * 25) + (battery * 20) + (cpu * 15) + (ram * 10);
        return total / 100;
    }

    function openRound(uint256 orderId) public returns (uint256 roundId) {
        require(sc1.isActive(msg.sender), "Caller not registered in SC-1");
        roundCount++;
        rounds[roundCount] = ScoringRound({
            orderId:         orderId,
            droneStation:    msg.sender,
            isOpen:          true,
            winner:          address(0),
            winnerScore:     0,
            submissionCount: 0
        });
        emit RoundOpened(roundCount, orderId, msg.sender);
        return roundCount;
    }

    function submitScore(uint256 roundId, uint256 score) public {
        require(sc1.isActive(msg.sender), "UAV not registered in SC-1");
        require(rounds[roundId].isOpen, "Round is closed");
        require(score <= 100, "Score must be 0-100");
        require(submissions[roundId][msg.sender].submittedAt == 0, "Already submitted");

        submissions[roundId][msg.sender] = UAVScore({
            uavAddress:  msg.sender,
            score:       score,
            submittedAt: block.timestamp,
            verified:    true
        });
        roundParticipants[roundId].push(msg.sender);
        rounds[roundId].submissionCount++;
        emit ScoreSubmitted(roundId, msg.sender, score);
    }

    function closeRound(uint256 roundId) public {
        ScoringRound storage round = rounds[roundId];
        require(msg.sender == round.droneStation, "Only the DS that opened this round");
        require(round.isOpen, "Round already closed");
        require(round.submissionCount > 0, "No scores submitted");

        address bestUAV   = address(0);
        uint256 bestScore = 0;
        address[] memory participants = roundParticipants[roundId];
        for (uint256 i = 0; i < participants.length; i++) {
            UAVScore memory s = submissions[roundId][participants[i]];
            if (s.score > bestScore) {
                bestScore = s.score;
                bestUAV   = participants[i];
            }
        }
        round.isOpen      = false;
        round.winner      = bestUAV;
        round.winnerScore = bestScore;
        emit WinnerSelected(roundId, bestUAV, bestScore);
    }

    function getWinner(uint256 roundId) public view returns (address winner, uint256 score) {
        require(!rounds[roundId].isOpen, "Round still open");
        return (rounds[roundId].winner, rounds[roundId].winnerScore);
    }

    // ── FIX: allow SC6 contract OR registered actor to call this ──
    function updateReputation(address uav, int256 delta) public {
        require(
            sc1.isActive(msg.sender) || msg.sender == sc6Address,
            "Caller not authorized (not in SC-1 and not SC6)"
        );
        reputationScore[uav] += delta;
        emit ReputationUpdated(uav, delta, reputationScore[uav]);
    }
}
