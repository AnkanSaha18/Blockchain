#!/usr/bin/env python3
"""
DCBA UAV Agent
Each instance simulates one UAV computing and submitting DCS scores.
Usage: python3 uav_agent.py --uav-id 1 --round-id round-sim-001
"""
import argparse
import json
import time
import random
import hashlib
import sys
from web3 import Web3

parser = argparse.ArgumentParser()
parser.add_argument("--uav-id",   type=str, default="uav-001")
parser.add_argument("--round-id", type=str, default="round-sim-001")
parser.add_argument("--rpc",      type=str, default="http://127.0.0.1:8545")
parser.add_argument("--key",      type=str, default=None)
parser.add_argument("--score",    type=int, default=None)
args = parser.parse_args()

w3 = Web3(Web3.HTTPProvider(args.rpc))
print(f"[UAV-{args.uav_id}] Connected to PDC: {w3.is_connected()}")

def compute_dcs_score(uav_id_str, seed=42):
    """Mirrors SC4.computeScore() weighted formula"""
    h = int(hashlib.md5(f"{uav_id_str}{seed}".encode()).hexdigest(), 16)
    random.seed(h)
    speed   = random.randint(60, 100)
    payload = random.randint(50, 100)
    battery = random.randint(40, 100)
    cpu     = random.randint(50, 95)
    ram     = random.randint(50, 95)
    score = (speed*30 + payload*25 + battery*20 + cpu*15 + ram*10) // 100
    return score, {"speed": speed, "payload": payload,
                   "battery": battery, "cpu": cpu, "ram": ram}

def simulate_gps(uav_id, step):
    data = f"UAV-{uav_id}-step-{step}-lat-23.8{step:03d}-lon-90.4{step:03d}"
    return "Qm" + hashlib.sha256(data.encode()).hexdigest()[:44]

score, sensors = compute_dcs_score(args.uav_id)
if args.score:
    score = args.score

print(f"[UAV-{args.uav_id}] Sensors: {sensors}")
print(f"[UAV-{args.uav_id}] DCS Score computed: {score}")
print(f"[UAV-{args.uav_id}] GPS hash: {simulate_gps(args.uav_id, 1)}")
print(f"[UAV-{args.uav_id}] Ready to submit to round: {args.round_id}")
