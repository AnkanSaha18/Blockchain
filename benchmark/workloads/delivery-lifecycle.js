'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class DeliveryLifecycleWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txCounter = 0;
        this.contractId = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.contractId = roundArguments.contractId;
        this.workerIndex = workerIndex;
    }

    async submitTransaction() {
        this.txCounter++;
        const orderID  = `del-${this.workerIndex}-${this.txCounter}-${Date.now()}`;
        const uavID    = `uav-${this.workerIndex}-${this.txCounter}`;
        const patient  = `patient-${this.txCounter}`;
        const slaDeadline = String(Math.floor(Date.now() / 1000) + 3600); // 1 hour from now

        // Step 1: Create delivery
        await this.sutAdapter.sendRequests({
            contractId: this.contractId,
            contractFunction: 'LifecycleContract:CreateDelivery',
            contractArguments: [orderID, uavID, patient, slaDeadline],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });

        // Step 2: Set in-flight
        await this.sutAdapter.sendRequests({
            contractId: this.contractId,
            contractFunction: 'LifecycleContract:SetInFlight',
            contractArguments: [orderID],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });

        // Step 3: Log GPS update
        const ipfsHash = `Qm${Buffer.from(orderID).toString('hex').slice(0, 44)}`;
        await this.sutAdapter.sendRequests({
            contractId: this.contractId,
            contractFunction: 'LifecycleContract:LogGPS',
            contractArguments: [orderID, ipfsHash],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });

        // Step 4: Confirm delivery
        await this.sutAdapter.sendRequests({
            contractId: this.contractId,
            contractFunction: 'LifecycleContract:ConfirmDelivery',
            contractArguments: [orderID],
            invokerIdentity: 'Admin@org1',
            readOnly: false
        });
    }

    async cleanupWorkloadModule() {}
}

function createWorkloadModule() {
    return new DeliveryLifecycleWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
