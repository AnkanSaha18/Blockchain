'use strict';

import { WorkloadModuleBase } from '@hyperledger/caliper-core';

class DCSWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txCounter = 0;
        this.workerIndex = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.workerIndex = workerIndex;
    }

    async submitTransaction() {
        this.txCounter++;
        // Unique key per transaction — eliminates MVCC conflicts
        const roundId = `r-${this.workerIndex}-${this.txCounter}-${Date.now()}`;
        const orderId = `o-${this.workerIndex}-${this.txCounter}`;

        await this.sutAdapter.sendRequests({
            contractId: 'dcba-uoc',
            contractFunction: 'DCSContract:OpenRound',
            contractArguments: [roundId, orderId],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });

        await this.sutAdapter.sendRequests({
            contractId: 'dcba-uoc',
            contractFunction: 'DCSContract:SubmitScore',
            contractArguments: [roundId, `uav-a-${this.txCounter}`, String(Math.floor(Math.random() * 40) + 60)],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });

        await this.sutAdapter.sendRequests({
            contractId: 'dcba-uoc',
            contractFunction: 'DCSContract:CloseRound',
            contractArguments: [roundId],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });
    }
}

export function createWorkloadModule() {
    return new DCSWorkload();
}
