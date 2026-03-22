'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txCounter = 0;
        this.contractId = '';
        this.seededOrderIDs = [];
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.contractId = roundArguments.contractId;
        this.workerIndex = workerIndex;

        // Pre-seed some deliveries to query
        for (let i = 0; i < 5; i++) {
            const orderID     = `query-seed-${workerIndex}-${i}-${Date.now()}`;
            const uavID       = `uav-seed-${i}`;
            const patient     = `patient-seed-${i}`;
            const slaDeadline = String(Math.floor(Date.now() / 1000) + 7200);

            await this.sutAdapter.sendRequests({
                contractId: this.contractId,
                contractFunction: 'LifecycleContract:CreateDelivery',
                contractArguments: [orderID, uavID, patient, slaDeadline],
                invokerIdentity: 'Admin@org1',
                readOnly: false
            });

            this.seededOrderIDs.push(orderID);
        }
    }

    async submitTransaction() {
        this.txCounter++;
        const orderID = this.seededOrderIDs[this.txCounter % this.seededOrderIDs.length];

        await this.sutAdapter.sendRequests({
            contractId: this.contractId,
            contractFunction: 'LifecycleContract:GetDelivery',
            contractArguments: [orderID],
            invokerIdentity: 'Admin@org1',
            readOnly: true
        });
    }

    async cleanupWorkloadModule() {}
}

function createWorkloadModule() {
    return new QueryWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
