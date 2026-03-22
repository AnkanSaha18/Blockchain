'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class DcsScoringWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.roundCounter = 0;
        this.contractId = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.contractId = roundArguments.contractId;
        this.workerIndex = workerIndex;
    }

    async submitTransaction() {
        this.roundCounter++;
        const roundID = `round-${this.workerIndex}-${this.roundCounter}-${Date.now()}`;
        const orderID = `order-${this.workerIndex}-${this.roundCounter}`;

        // Step 1: Open a scoring round
        await this.sutAdapter.sendRequests({
            contractId: this.contractId,
            contractFunction: 'DCSContract:OpenRound',
            contractArguments: [roundID, orderID],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });

        // Step 2: Submit scores from 3 UAVs
        const uavs = [
            { id: `uav-alpha-${this.roundCounter}`, score: String(Math.floor(Math.random() * 40) + 60) },
            { id: `uav-beta-${this.roundCounter}`,  score: String(Math.floor(Math.random() * 40) + 40) },
            { id: `uav-gamma-${this.roundCounter}`, score: String(Math.floor(Math.random() * 40) + 20) }
        ];

        for (const uav of uavs) {
            await this.sutAdapter.sendRequests({
                contractId: this.contractId,
                contractFunction: 'DCSContract:SubmitScore',
                contractArguments: [roundID, uav.id, uav.score],
                invokerIdentity: 'Admin@org1',
                readOnly: false
            });
        }

        // Step 3: Close the round
        await this.sutAdapter.sendRequests({
            contractId: this.contractId,
            contractFunction: 'DCSContract:CloseRound',
            contractArguments: [roundID],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });
    }

    async cleanupWorkloadModule() {}
}

function createWorkloadModule() {
    return new DcsScoringWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
