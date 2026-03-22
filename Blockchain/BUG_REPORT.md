# DCBA Smart Contract Bug Report

## Bug 1 — CRITICAL: SC4.updateReputation fails when called from SC6
**File:** SC4_DCSScoring.sol, line 213  
**Problem:**  
```solidity
function updateReputation(address uav, int256 delta) public {
    require(sc1.isActive(msg.sender), "Caller not in SC-1");  // ← BUG
```
SC6 calls this function from its `flagDeviation()` and `confirmDelivery()`.  
When a contract (SC6) calls another contract (SC4), `msg.sender` = SC6's **contract address**.  
SC6's contract address is NOT registered in SC1 → `isActive()` returns `false` → **always reverts**.  

**Effect:** `confirmDelivery()` and `flagDeviation()` in SC6 **always fail**.  

**Fix applied:**
```solidity
// Added in SC4:
address public sc6Address;

function linkSC6(address _sc6) public {
    require(sc6Address == address(0), "SC6 already linked");
    sc6Address = _sc6;
}

function updateReputation(address uav, int256 delta) public {
    require(
        sc1.isActive(msg.sender) || msg.sender == sc6Address,
        "Caller not authorized"
    );
    ...
}
```
**After deploying SC6, TA must call: `SC4.linkSC6(SC6_address)`**

---

## Bug 2 — CRITICAL: SC7.registerHash fails (missing setSC3Address step)
**File:** SC7_OracleBridge.sol, line 81  
**Problem:**  
```solidity
require(msg.sender == sc3Address, "Only SC-3 can register");
```
`sc3Address` is `address(0)` at deployment.  
If TA forgets to call `SC7.setSC3Address(SC3_address)` after deploying SC3,  
every call to `SC3.addRecord()` will revert (because SC3 calls SC7.registerHash internally).  

**Fix:** Not a code bug — it's a deployment procedure step.  
**After deploying SC3, TA must call: `SC7.setSC3Address(SC3_address)`**

---

## Bug 3 — MINOR: SC6 has unused ISC5 interface (dead code)
**File:** SC6_DeliveryLifecycle.sol  
**Problem:** `interface ISC5` is declared but never instantiated or used anywhere in SC6.  
**Fix:** Removed the ISC5 interface block.

---

## Correct Deployment Order

| Step | Action |
|------|--------|
| 1 | Deploy SC1 (no constructor args) |
| 2 | Deploy SC7 (no constructor args) |
| 3 | Deploy SC2 (SC1 address) |
| 4 | Deploy SC3 (SC1, SC2, SC7 addresses) |
| 5 | **Call SC7.setSC3Address(SC3 address)** ← don't skip! |
| 6 | Deploy SC4 (SC1 address) |
| 7 | Deploy SC5 (SC1, SC7 addresses) |
| 8 | Deploy SC6 (SC1, SC4 addresses) |
| 9 | **Call SC4.linkSC6(SC6 address)** ← new fix, don't skip! |
