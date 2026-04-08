# LUB-V Greaser — PLC Control Protocol Documentation

## Overview

The LUB-V is an automatic single-line lubrication pump. This document describes the digital I/O communication protocol between a Siemens S7-series PLC and the LUB-V unit.

---

## Wiring / Pin Assignment

| PIN | Direction | Signal | Description |
|-----|-----------|--------|-------------|
| PIN 2 | LUB-V → PLC | Ready | HIGH when device is ready to accept a command |
| PIN 3 | PLC → LUB-V | Control | PLC issues commands by asserting specific pulse widths |
| PIN 4 | LUB-V → PLC | Feedback | LUB-V sends pulse train to report result |

---

## Ready Signal Qualification (PIN 2)

- The LUB-V asserts PIN 2 HIGH to indicate that it is ready for a command.
- The PLC **must** confirm that PIN 2 has been continuously HIGH for **more than 500 ms** before treating the device as qualified/ready.
- Recommended qualification hold time: **600 ms** (adds 20 % margin).

---

## Control Signal — Command Encoding (PIN 3)

Commands are issued by the PLC asserting PIN 3 HIGH for a precisely timed pulse duration. After the pulse, PIN 3 must return to LOW.

| Pulse Width | Command |
|-------------|---------|
| 100 ms | Short trigger / acknowledge |
| 900 ms | Medium command A |
| 1 000 ms | Trigger single lubrication stroke |
| 1 600 ms | Trigger extended / multi-stroke lubrication |
| 1 700 ms | Full cycle command |

> **Note:** Pulse widths must be accurate to within ±50 ms. Use a PLC timer with millisecond resolution.

---

## Feedback Signal — Response Encoding (PIN 4)

After executing a command, the LUB-V sends a pulse train on PIN 4.

- **Signal frequency:** 5 Hz (200 ms period — 100 ms HIGH, 100 ms LOW per pulse)
- **Evaluation method:** Count **rising edges** (low-to-high transitions only)
- **End of transmission:** Silence on PIN 4 for **≥ 500 ms** indicates the pulse train is complete

### Response Code Table

| Rising-Edge Count | Meaning |
|:-----------------:|---------|
| 1 | Lubrication stroke started |
| 2 | Past lubrication stroke OK — no fault |
| 3 | Low-level warning (reservoir below minimum) |
| 4 | Overpressure fault (E2) at outlet 1 |
| 5 | Overpressure fault (E2) at outlet 2 |
| 6 | General device fault |
| 7 | Device not ready |

> **Critical:** Counting both rising and falling edges (i.e. using `<>` comparison instead of `AND NOT`) will double the count, causing response codes to be misinterpreted.

---

## Timing Requirements

| Parameter | Minimum | Recommended |
|-----------|---------|-------------|
| Ready qualification hold time | 500 ms | 600 ms |
| Overall response timeout (PLC must receive feedback) | — | **30 s** |
| Post-response inter-command gap | 500 ms | 600 ms |
| Feedback silence window (end-of-train detection) | 500 ms | 500 ms |

> The LUB-V **guarantees** to send its response within **30 seconds** of receiving the control signal. The PLC timeout must therefore be set to at least 30 s.

---

## State Machine Summary

The recommended PLC implementation uses the following states:

```
qState machine (qualification):
  qState 0  → PIN 2 LOW  : device not ready, reset qualify timer
  qState 10 → PIN 2 HIGH : start 600 ms qualify timer
  qState 20 → Timer done  : deviceQualified = TRUE

Main state machine:
  State  0  → Idle, wait for trigger and deviceQualified = TRUE
  State 10  → Assert PIN 3 HIGH, start pulse timer
  State 20  → Pulse complete, PIN 3 LOW, reset & start tLubeTimeout (30 s)
  State 30  → Count rising edges on PIN 4 until 500 ms silence
  State 40  → Decode edgeCount → set outputs (LubeOK / FaultCode)
  State 50  → Wait 600 ms inter-command gap, return to State 0
```

---

## Fault Handling

- If `tLubeTimeout` (30 s) expires before the feedback is received, set `o_Fault = TRUE` and `o_FaultCode = 99` (timeout fault).
- The function block should latch faults until an external reset input is asserted.

---

## Revision History

| Version | Date | Notes |
|---------|------|-------|
| 0.33 | — | Initial release; see `FB_LUB_V_Greaser_V033_Fixed.scl.st` for corrected version |
