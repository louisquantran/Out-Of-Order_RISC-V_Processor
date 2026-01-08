# Out-Of-Order RISC-V RTL Project
A **1‑wide out‑of‑order (OoO) RISC‑V processor** implemented in **SystemVerilog** (UCLA ECE‑189, honors session of ECE‑M116C).

## Architecture Overview

### Pipeline Frontend: I-Cache → Fetch → Decode
- **I-Cache (BRAM)** supplies instructions to **Fetch**.
- **Skid buffers** provide elastic buffering between stages to hold and transfer values to next stages.
- **Decode** takes in the instruction memory read from I-Cache, then output meaningful signals for future stages' operations.

### Rename + Register Tracking: Map Table + Free List
- **Rename** maps architectural registers → physical registers using a **Map Table**.
- For instructions with a destination register, **Rename** allocates a new physical register from the **Free List** and updates the mapping.

### Dispatch + Scheduling: RS_ALU / RS_LSU / RS_Branch + ROB
- **Dispatch** routes renamed operations into specialized reservation stations:
  - `RS_ALU` for arithmetic / logical operations
  - `RS_LSU` for loads / stores operations (memory)
  - `RS_Branch` for control-flow operations
- The **ROB (Reorder Buffer)** tracks all in-flight instructions to ensure **precise architectural state** and **in-order commit**, even when execution happens out-of-order.

### Execute + Memory System: ALU / Branch / LSU / LSQ / Memory / PRF
- The **PRF (Physical Register File)** holds the true operand values; execution units read from PRF and write results back.
- **ALU** executes integer arithmetic / logical operations and writes results to PRF.
- **Branch unit** resolves control flow and triggers redirect/flush on mispredict.
- Memory operations flow through **LSU/Mem unit + LSQ** into **BRAM main memory**, coordinating load/store ordering while still allowing OoO scheduling where safe.

### Control-Flow Recovery: Checkpoints + Flush/Redirect
- A **checkpoint mechanism** snapshots rename-related state (e.g., map table + free list, and any additional tracked state as required by the design) when a control-flow instruction is in flight.
- On mispredict, the core **flushes younger work** (skid buffers, RS entries, ROB/LSQ contents as applicable), **restores** the checkpointed state, and **redirects** fetch to the correct PC to maintain precise state.

---

## Supported RISC-V Instructions (tested subset)

### Arithmetic / Logical
- **I-Type:** `ADDI`, `ORI`, `SLTIU`
- **R-Type:** `SRA`, `SUB`, `AND`

### Loads / Stores
- **Loads (I-Type):** `LBU`, `LW`
- **Stores (S-Type):** `SH`, `SW`

### Control Flow
- **Branch (B-Type):** `BNE`
- **Jump (I-Type):** `JALR`

### Upper Immediate
- **U-Type:** `LUI`
