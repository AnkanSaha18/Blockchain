#!/usr/bin/env python3
"""
DCBA Fleet Simulator — Threading version
Measures pure DCS computation time without process startup overhead.
"""
import threading
import time
import json
import random
import hashlib

def compute_dcs_score(uav_id_str):
    h = int(hashlib.md5(uav_id_str.encode()).hexdigest(), 16)
    random.seed(h)
    speed   = random.randint(60, 100)
    payload = random.randint(50, 100)
    battery = random.randint(40, 100)
    cpu     = random.randint(50, 95)
    ram     = random.randint(50, 95)
    return (speed*30 + payload*25 + battery*20 + cpu*15 + ram*10) // 100

def run_fleet(n_uavs):
    print(f"\n{'='*55}")
    print(f"🚁 Fleet: {n_uavs} UAVs (threaded)")
    print(f"{'='*55}")

    scores = {}
    lock = threading.Lock()

    def uav_task(uav_id):
        score = compute_dcs_score(uav_id)
        with lock:
            scores[uav_id] = score

    t_start = time.time()

    threads = []
    for i in range(1, n_uavs + 1):
        t = threading.Thread(target=uav_task, args=(f"uav-{i:03d}",))
        threads.append(t)

    for t in threads:
        t.start()
    for t in threads:
        t.join()

    t_end = time.time()
    elapsed_ms = (t_end - t_start) * 1000

    winner = max(scores, key=scores.get)
    print(f"   Winner: {winner} | Score: {scores[winner]}")
    print(f"⏱  Round time: {elapsed_ms:.2f}ms")
    return elapsed_ms

if __name__ == "__main__":
    fleet_sizes = [10, 25, 50, 75, 100]
    results = {}

    for n in fleet_sizes:
        ms = run_fleet(n)
        results[n] = round(ms, 2)
        time.sleep(1)

    print(f"\n{'='*55}")
    print("📈 DCS Scalability Results:")
    print(f"{'='*55}")
    for n, ms in results.items():
        status = "✅" if ms < 140 else "⚠️"
        print(f"   {status} {n:3d} UAVs → {ms:.2f}ms")

    with open("simulation/scalability_results.json", "w") as f:
        json.dump(results, f, indent=2)
    print("\n💾 Saved to simulation/scalability_results.json")
