GasWise
==================

AI-Based Gas Fee Optimization Manager for Stacks
------------------------------------------------

**GasWise** is a high-performance, on-chain registry and heuristic engine designed to bridge the gap between off-chain AI network analysis and on-chain execution. By leveraging authorized AI agents to feed real-time network metrics into a circular buffer, GasWise provides smart-contract-native gas recommendations that adapt to historical trends, current congestion, and user-defined priority levels.

* * * * *

1\. Executive Summary
---------------------

In the Stacks ecosystem, transaction fee estimation is often static or relies on lagging indicators. I have designed **GasWise** to introduce a dynamic, AI-informed approach. This contract acts as a "Single Source of Truth" for gas metrics, allowing dApps and individual users to query optimized fees that are mathematically derived from:

-   **Current Base Fees**: Real-time reporting from off-chain monitors.

-   **Congestion Levels**: A 1-100 scale representing network saturation.

-   **Moving Averages**: A circular buffer tracking the last 5 blocks to identify rising or falling trends.

-   **Strategy Multipliers**: Admin-tunable variables that ensure recommendations remain competitive yet cost-effective.

* * * * *

2\. Technical Architecture
--------------------------

The contract operates as a data repository and calculation engine. Authorized AI agents (off-chain bots) analyze the Stacks mempool and block headers to call `update-network-metrics`. This minimizes the compute load on the Stacks VM while maintaining the security of decentralized verification.

### 2.1. Historical Circular Buffer

To avoid the high costs of iterating over massive maps, I implemented a fixed-size circular buffer using `recent-gas-fees`.

-   **Size**: 5 Slots (`history-buffer-size`).

-   **Mechanism**: Every update increments a `buffer-index`, overwriting the oldest data point.

-   **Trend Detection**: By comparing the `current-base-fee` against the `get-moving-average`, the contract can detect if the network is entering a "Surge" phase.

* * * * *

3\. Function Reference
----------------------

### 3.1. Private Functions (Internal Logic)

These functions are the "engine room" of the contract, handling internal validation and complex arithmetic that should not be directly exposed to external callers.

-   **`is-contract-owner`**: A standard security check to ensure that only the deployer (or designated admin) can modify sensitive multipliers or authorize agents.

-   **`is-authorized-agent (agent principal)`**: Performs a map lookup to verify if the caller is a registered AI agent.

-   **`check-active`**: A gatekeeper function that prevents non-owner interactions if the `contract-paused` state is true.

-   **`record-metric-history (fee uint)`**: Manages the circular buffer logic. It calculates the `next-idx` using a modulo operation to ensure the buffer never exceeds its 5-slot limit.

-   **`get-moving-average`**: Performs a manual summation and division of the `recent-gas-fees` map. This provides a "smoothed" view of gas prices over the last five blocks, essential for trend analysis.

### 3.2. Public Functions (State-Changing)

These functions require a transaction and gas to execute, as they modify the blockchain's state.

-   **`add-authorized-agent (agent principal)`**: Grants a principal the rights to push gas data. Essential for scaling the AI node network.

-   **`set-paused (state bool)`**: The emergency circuit breaker. If an AI model begins hallucinating or reporting incorrect data, the owner can freeze the contract.

-   **`update-network-metrics (new-base-fee uint, new-congestion uint)`**: The primary entry point for AI data. It updates the current global variables, saves a timestamped entry in `historical-gas-metrics`, and triggers the `record-metric-history` function.

-   **`set-conservative-config` / `set-balanced-config` / `set-aggressive-config`**: These functions allow the admin to fine-tune the multipliers (e.g., 1.2x vs 1.5x) based on real-world performance without redeploying the contract.

-   **`set-congestion-thresholds`**: Defines what the contract considers "moderate" or "high" congestion (defaulted to 50 and 80).

### 3.3. Read-Only Functions (External Query)

These functions are free to call and are intended for use by wallets, dApps, and frontend interfaces.

-   **`calculate-conservative-fee (base-fee uint)`**: Returns a fee with a minimal safety buffer, ideal for non-critical transactions.

-   **`calculate-balanced-fee (base-fee uint, congestion uint)`**: The most complex strategy. It checks the congestion against thresholds to pick one of three multipliers.

-   **`calculate-aggressive-fee (base-fee uint, congestion uint)`**: Designed for "next-block" inclusion. If congestion is high, it applies a "Surge" multiplier (default 3.0x).

-   **`get-strategy-comparison`**: Provides a single-call payload containing all three strategy results and the moving average.

-   **`calculate-dynamic-optimal-fee (priority-level uint)`**: The "Smart Router." I designed this to automatically apply a 5% "Trend Boost" if the current fee is higher than the moving average, protecting users from being outbid in a rising market.

* * * * *

4\. Security and Governance
---------------------------

I have implemented several layers of protection to ensure the integrity of the gas recommendations:

1.  **Authorization Guard**: Only verified AI agents can influence the data, preventing "gas griefing" attacks.

2.  **Input Validation**: Multipliers cannot be set below 100% (u100), ensuring the contract never recommends a fee lower than the network base.

3.  **Circuit Breaker**: The `set-paused` function allows the owner to freeze updates in the event of an AI model failure.

* * * * *

5\. Contribution Guidelines
---------------------------

I welcome contributions from the community to improve the GasWise logic.

1.  **Fork the repository.**

2.  **Create a feature branch** (`git checkout -b feature/OptimizationLogic`).

3.  **Commit changes** with detailed Clarity 2.0 explanations.

4.  **Open a Pull Request** for review by the maintainers.

* * * * *

6\. License
-----------

```
MIT License

Copyright (c) 2026 GasWise Project Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```

* * * * *

7\. Disclaimer
--------------

I provide this contract as-is. While the AI models aim for high accuracy, blockchain network conditions can shift faster than a block-time interval. Users should always verify large transactions manually.

