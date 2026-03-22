'use strict';

import { WorkloadModuleBase } from '@hyperledger/caliper-core';

class GPSWorkload extends WorkloadModuleBase {
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
        // Unique orderId per transaction — eliminates MVCC conflicts
        const orderId   = `gps-${this.workerIndex}-${this.txCounter}-${Date.now()}`;
        const slaDeadline = String(Math.floor(Date.now() / 1000) + 3600);
        const ipfsHash  = `QmGPS${this.workerIndex}${this.txCounter}Dhaka238103904125`;

        await this.sutAdapter.sendRequests({
            contractId: 'dcba-uoc',
            contractFunction: 'LifecycleContract:CreateDelivery',
            contractArguments: [orderId, `uav-${this.workerIndex}`, `patient-${this.txCounter}`, slaDeadline],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });

        await this.sutAdapter.sendRequests({
            contractId: 'dcba-uoc',
            contractFunction: 'LifecycleContract:SetInFlight',
            contractArguments: [orderId],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });

        await this.sutAdapter.sendRequests({
            contractId: 'dcba-uoc',
            contractFunction: 'LifecycleContract:LogGPS',
            contractArguments: [orderId, ipfsHash],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });
    }
}

export function createWorkloadModule() {
    return new GPSWorkload();
}
