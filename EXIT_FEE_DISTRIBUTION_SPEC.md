# Exit Fee Distribution Service Specification

## 1. Overview

When a vKAT holder exits their lock via the Voting Escrow, a percentage-based exit fee (in KAT) is collected by the `ExitQueue` contract. This KAT is distributed proportionally to **all addresses whose voting power was actively used in gauge voting** during that epoch's voting window — including both voters and their delegators.

The distribution uses the [Capital Distributor plugin](https://github.com/aragon/osx-capital-distributor/tree/feat/katana-locks-distrib) with its `MerkleDistributorStrategy` for on-chain claiming.

### Core Rule

Rewards are attributed to the **original token owner**, not the address that cast the vote.

- If A (100 VP) delegates to B (50 VP self-delegated), and B votes with 150 VP total → rewards: A gets 100/150 (66.7%), B gets 50/150 (33.3%).
- If A self-delegates and votes with 100 VP → A gets 100%.
- If A has tokens but never delegated them → A gets nothing (undelegated tokens = zero VP).

---

## 2. Delegation Model

Delegation is **NFT-based, not amount-based**. Each lock creates an NFT (token ID) with voting power derived from its locked KAT amount and lock duration. Key constraints:

- **Single delegatee per account**: `delegates(account)` returns one address. All delegated tokens from that account go to the same delegatee.
- **Per-NFT delegation**: You choose which of your NFTs to delegate via `delegate(uint256[] tokenIds)`. Non-delegated NFTs contribute **zero** voting power to anyone.
- **No partial voting**: `vote()` always uses 100% of `getVotes(account)`, distributed across gauges by weight.
- **Voting power source**: `getVotes(account)` returns the total VP of all tokens delegated **TO** that account (from self and from others).

### Scenarios
A has 500 VP and B has 300 VP. The following cases then entail:

| Setup | A's getVotes() | B's getVotes() | Can A vote? | Can B vote? |
|-------|---------------|---------------|-------------|-------------|
| A (500 VP) self-delegates all, B (300 VP) self-delegates all | 500 | 300 | Yes | Yes |
| A sets delegatee=B, delegates NFTs worth 100 to B | 0 | 400 (300+100) | No | Yes |
| A self-delegates 3 of 5 NFTs (300 VP), 2 idle | 300 | 300 | Yes (300) | Yes (300) |

---

## 3. Epoch Timing & Snapshot Window

### 3.1 Epoch Structure (from `Clock.sol`)

| Constant             | Value      |
|----------------------|------------|
| `EPOCH_DURATION`     | 2 weeks (1,209,600s) |
| `VOTE_DURATION`      | 1 week (604,800s)    |
| `VOTE_WINDOW_BUFFER` | 1 hour (3,600s)      |
| `CHECKPOINT_INTERVAL`| 1 week (604,800s)    |

`epoch_id = unix_timestamp / EPOCH_DURATION`

```
|--1hr--|-------- Voting Window (6d 22h) --------|--1hr--|------- Non-Voting (1 week) -------|
0       1hr                                 1w-1hr  1w                                      2w
        ^                                  ^
        Voting opens                       Voting closes
```

### 3.2 Safe Snapshot Timestamp

The backend takes its snapshot in the 1-hour gap after voting closes:

```
Safe window: [epochStart + 6d23h, epochStart + 7d)
Recommended: epochStart + 6d23h + 5min (margin for block finality)
```

For epoch N: `snapshot_ts = (N * 1_209_600) + 601_200 + 300`

No new `Voted` events can be emitted after this point. All vote state is final.

---

## 4. Events to Index

### From `AddressGaugeVoter`

```solidity
event Voted(
    address indexed voter, address indexed gauge, uint256 indexed epoch,
    uint256 votingPowerCastForGauge, uint256 totalVotingPowerInGauge,
    uint256 totalVotingPowerInContract, uint256 timestamp
);
event Reset(
    address indexed voter, address indexed gauge, uint256 indexed epoch,
    uint256 votingPowerRemovedFromGauge, uint256 totalVotingPowerInGauge,
    uint256 totalVotingPowerInContract, uint256 timestamp
);
```

### From `EscrowIVotesAdapter`

```solidity
event TokensDelegated(address indexed sender, address indexed delegatee, uint256[] tokenIds);
event TokensUndelegated(address indexed sender, address indexed delegatee, uint256[] tokenIds);
event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
```

### From `Lock` (ERC721)

```solidity
event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
```

---

## 5. Reward Computation Algorithm

Each step has a verifiable invariant that **must hold** before proceeding to the next step. If an invariant fails, halt and investigate.

### Step 1: Determine Active Voters

Index all `Voted` and `Reset` events for epoch N. For each address, process events chronologically — a `Voted` event sets them active, a `Reset` sets them inactive. `vote()` auto-resets before re-casting, so if the last event batch is `Voted`, the voter is active.

For each active voter, compute their total used VP:
```
usedVP[voter] = SUM(votingPowerCastForGauge) across all gauges in their latest vote batch
```

**INVARIANT 1**: `SUM(usedVP[v] for all active voters v) == epochTotalVotingPowerCast[epoch]`

Verify by reading `epochTotalVotingPowerCast[epoch]` on-chain, or by using the `totalVotingPowerInContract` value from the chronologically last `Voted` or `Reset` event in the epoch.

---

### Step 2: Resolve Delegation Sources Per Voter

For each active voter V, determine which token IDs are currently delegated to V at the snapshot block. Build this from:

1. All `TokensDelegated(sender, delegatee=V, tokenIds)` events up to snapshot
2. Minus all `TokensUndelegated(sender, delegatee=V, tokenIds)` events up to snapshot

Result: `delegated_tokens[V]` = set of tokenIds currently delegated to V.

For each token, determine the owner from the latest `Transfer` event on the Lock NFT.

Result: `delegation_map[V]` = `{ owner_address: [tokenId, ...], ... }`

**INVARIANT 2 (per voter)**: `SUM(votingPowerAt(tokenId, snapshot_ts) for all tokenIds in delegated_tokens[V]) == usedVP[V]`

Verify by calling `VotingEscrowIncreasing.votingPowerAt(tokenId, snapshot_ts)` via RPC for each token.

> **Note on VP computation**: Use `votingPowerAt(tokenId, snapshot_ts)` RPC calls for accuracy, since the escrow curve (`bias = constant * amount + linear * amount * elapsed`) makes VP depend on both locked amount and lock age. Using raw `locked(tokenId).amount` would be inaccurate when tokens have different ages.

---

### Step 3: Attribute VP to Original Token Owners

For each token in `delegation_map[V]`, credit the token's VP to its **owner** (not to V).

```python
credit = {}  # owner_address => total VP credited
for voter in active_voters:
    for owner, token_ids in delegation_map[voter].items():
        for token_id in token_ids:
            vp = voting_power_at(token_id, snapshot_ts)
            credit[owner] = credit.get(owner, 0) + vp
```

**INVARIANT 3**: `SUM(credit[owner] for all owners) == epochTotalVotingPowerCast[epoch]`

This must equal Invariant 1's value. Every unit of VP that was used in voting is now attributed to exactly one token owner.

---

### Step 4: Compute Proportional Rewards

```python
total_fees = get_exit_fees_for_epoch(epoch_N)
total_credit = sum(credit.values())

rewards = {}
for owner, vp in credit.items():
    rewards[owner] = (vp * total_fees) // total_credit
```

**INVARIANT 4**: `SUM(rewards[owner]) <= total_fees` and `total_fees - SUM(rewards[owner]) < len(rewards)` (dust is bounded by number of recipients)

Carry rounding dust to the next epoch or add to the largest recipient.

---

### Worked Example

Setup: Smit has 2 NFTs (tokens #1: 60 VP, #2: 40 VP), self-delegates both. Jordan has 1 NFT (token #3: 50 VP), delegates to Smit. Smit votes. Exit fees for epoch = 150 KAT.

| Step | Computation | Invariant Check |
|------|-------------|-----------------|
| 1 | Active voters: {Smit}. `usedVP[Smit] = 150` | 150 == `epochTotalVotingPowerCast` |
| 2 | `delegated_tokens[Smit] = {#1, #2, #3}`. Owners: Smit→{#1,#2}, Jordan→{#3} | VP(#1)+VP(#2)+VP(#3) = 60+40+50 = 150 == usedVP[Smit] |
| 3 | `credit[Smit] = 100`, `credit[Jordan] = 50` | 100+50 = 150 == epochTotalVotingPowerCast |
| 4 | `reward[Smit] = 100/150 * 150 = 100 KAT`, `reward[Jordan] = 50/150 * 150 = 50 KAT` | 100+50 = 150 == total_fees |

---

## 6. Exit Fee Tracking Per Epoch

Fees accumulate in the `ExitQueue` contract when users call `VotingEscrowIncreasing.withdraw()`:
```solidity
uint256 fee = IExitQueue(queue).exit(_tokenId);
if (fee > 0) { IERC20(token).safeTransfer(address(queue), fee); }
```

Track fees per epoch by indexing KAT `Transfer` events where `to == ExitQueue_address`, bucketed by epoch based on block timestamp.

Before distribution, the DAO (via `WITHDRAW_ROLE`) calls `ExitQueue.withdraw(amount)` to transfer accumulated KAT to the DAO treasury, which the Capital Distributor pays out from.

---

## 7. Multi-Epoch Reward Accumulation

### New Campaign Per Epoch with Cumulative Merkle Tree

A **new Capital Distributor campaign** is created each epoch. Its Merkle tree contains **cumulative** reward amounts — the sum of all rewards earned across all epochs, minus what the user has already claimed from previous campaigns.

```
leaf = keccak256(abi.encodePacked(address, adjusted_cumulative_amount))
```

Where: `adjusted_cumulative_amount = cumulative_rewards_all_epochs - total_claimed_from_past_campaigns`

This lets users claim all unclaimed rewards across all past epochs in a **single `claimCampaignPayout()` call** on the latest campaign.

### Per-Epoch Flow

```python
def publish_epoch(epoch_id, epoch_rewards):
    # 1. End the previous campaign (freezes its claim state)
    if prev_campaign_id := get_previous_campaign_id():
        capital_distributor.endCampaign(prev_campaign_id)

    # 2. Update cumulative rewards
    for addr, amount in epoch_rewards.items():
        cumulative[addr] = cumulative.get(addr, 0) + amount

    # 3. Read total already claimed per user across ALL past campaigns
    #    (from indexed PayoutClaimed events)
    total_claimed = get_total_claimed_all_campaigns()

    # 4. Build adjusted tree: what each user is still owed
    leaves = {}
    for addr, cum in cumulative.items():
        owed = cum - total_claimed.get(addr, 0)
        if owed > 0:
            leaves[addr] = owed

    # 5. Create new campaign with adjusted cumulative tree
    tree = build_merkle_tree(leaves)
    create_epoch_campaign(epoch_id, tree.root)
```

**Why end the previous campaign first**: Ending freezes claim state, so no user can claim from the old campaign after the backend reads `total_claimed`. This prevents a race where a claim between reading state and creating the new campaign would cause double-payment.

There is a brief unavailability window between ending the old campaign and creating the new one. Keep this to seconds.

### Handling Unclaimed Epochs

| Case | Handling |
|------|----------|
| User misses several epochs | Claim once from the latest campaign — leaf contains all accumulated owed rewards. |
| User voted epoch 5, not epoch 6 | Epoch 5 reward included in cumulative. Epoch 6 adds 0. Latest campaign leaf reflects total. |
| Zero exit fees in an epoch | Still create campaign (cumulative may have unclaimed amounts from prior epochs). Skip only if no user has any unclaimed amount. |
| User claims mid-epoch | Gets everything owed up to the last published campaign. Current epoch not yet included. |
| User claimed from campaign N-1, now campaign N exists | Campaign N's leaf already subtracts what was claimed from N-1. User claims the remainder. |

---

## 8. Capital Distributor Integration

Using the [Capital Distributor](https://github.com/aragon/osx-capital-distributor/tree/feat/katana-locks-distrib) with `MerkleDistributorStrategy`.

### 8.1 Per-Epoch: Create Campaign

Each epoch, the backend ends the previous campaign and creates a new one with an adjusted cumulative Merkle tree (see Section 7):

```python
def create_epoch_campaign(epoch_id, merkle_root):
    strategy_config = {
        "strategyId": MERKLE_DISTRIBUTOR_STRATEGY_ID,
        "strategyParams": b"",
        "initData": encode(["bytes32"], [merkle_root])
    }

    payout_config = {
        "token": KAT_TOKEN_ADDRESS,
        "actionEncoderId": bytes32(0),      # simple KAT transfer
        "actionEncoderInitData": b""
    }

    settings = {
        "startTime": 0,   # claimable immediately
        "endTime": 0       # no expiry
    }

    campaign_id = capital_distributor.createCampaign(
        epoch_metadata_uri, strategy_config, payout_config, settings
    )
    return campaign_id
```

The DAO treasury must hold sufficient KAT. The plugin executes payouts through `dao().execute()`.

The backend must store the mapping of `epoch_id → campaign_id` for the frontend to resolve the latest active campaign.

### 8.2 Merkle Tree Construction

Leaf format matches `MerkleDistributorStrategy`:
```
leaf = keccak256(abi.encodePacked(address account, uint256 adjusted_cumulative_amount))
```
Where `abi.encodePacked` produces 52 bytes (20 address + 32 uint256), and `adjusted_cumulative_amount = cumulative_rewards - total_claimed_from_past_campaigns`.

Sort leaves by address for deterministic tree generation.

### 8.3 User Claiming

Users only need to claim from the **latest active campaign**. One call covers all unclaimed rewards across all past epochs:

```solidity
claimCampaignPayout(
    latestCampaignId,
    recipient,
    abi.encode(merkleProof, adjustedCumulativeAmount),  // strategyAuxData
    bytes("")                                           // encoderAuxData
)
```

### 8.4 API Endpoints (for frontend)

```
GET /api/rewards/:address
  → { campaignId, claimable, adjustedCumulativeAmount, merkleProof[] }

GET /api/rewards/:address/history
  → [{ epoch, credited_vp, reward_amount }]

GET /api/epochs/:epoch_id/summary
  → { campaignId, total_fees, total_vp, num_recipients, merkle_root }
```

---

## 9. Backend Service Architecture

### 9.1 Components

```
┌───────────────────────────────────────────────────────────┐
│              Exit Fee Distribution Service                 │
│                                                           │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ Event Indexer │→ │  Snapshot    │→ │ Merkle Tree    │  │
│  │              │  │  Calculator  │  │ Generator      │  │
│  └──────────────┘  └──────────────┘  └────────────────┘  │
│         │                                    │            │
│         v                                    v            │
│  ┌──────────────┐                  ┌────────────────────┐ │
│  │   Database   │                  │ Capital Distributor│ │
│  │  (events +   │                  │ Publisher          │ │
│  │  snapshots)  │                  │ (endCampaign →     │ │
│  └──────────────┘                  │  createCampaign)   │ │
│                                    └────────────────────┘ │
└───────────────────────────────────────────────────────────┘
```

### 9.2 Event Indexer

Indexes continuously from deployment block:
- `Voted`, `Reset` from AddressGaugeVoter
- `TokensDelegated`, `TokensUndelegated`, `DelegateChanged` from EscrowIVotesAdapter
- `Transfer` from Lock NFT
- KAT `Transfer` to ExitQueue (fee tracking)
- `PayoutClaimed` from CapitalDistributorPlugin (to track total claimed per user across all campaigns)

**Performance optimization**: Store latest snapshot state at each epoch boundary. Subsequent epochs only need to crawl events after the last snapshot.

### 9.3 Database Schema

```sql
CREATE TABLE epoch_votes (
    epoch         BIGINT,
    voter         TEXT,
    gauge         TEXT,
    voting_power  NUMERIC,  -- votingPowerCastForGauge
    event_type    TEXT,      -- 'voted' or 'reset'
    timestamp     BIGINT,
    block_number  BIGINT,
    tx_hash       TEXT
);

CREATE TABLE token_ownership (
    token_id      BIGINT PRIMARY KEY,
    owner         TEXT,
    block_number  BIGINT
);

CREATE TABLE token_delegation (
    token_id      BIGINT PRIMARY KEY,
    owner         TEXT,       -- who owns the NFT
    delegatee     TEXT,       -- who it's delegated to
    is_delegated  BOOLEAN,
    block_number  BIGINT
);

CREATE TABLE exit_fees (
    epoch         BIGINT,
    amount        NUMERIC,
    tx_hash       TEXT,
    block_number  BIGINT
);

CREATE TABLE epoch_rewards (
    epoch         BIGINT,
    recipient     TEXT,       -- token owner (not necessarily voter)
    credited_vp   NUMERIC,
    reward_amount NUMERIC,
    cumulative    NUMERIC     -- running total across all epochs
);

CREATE TABLE user_claims (
    recipient     TEXT,
    campaign_id   BIGINT,
    amount        NUMERIC,    -- amount paid out
    block_number  BIGINT,
    PRIMARY KEY (recipient, campaign_id)
);

CREATE TABLE epoch_campaigns (
    epoch         BIGINT PRIMARY KEY,
    campaign_id   BIGINT,     -- Capital Distributor campaign ID
    merkle_root   TEXT,
    total_fees    NUMERIC,
    total_vp      NUMERIC,
    computed_at   BIGINT
);
```

### 9.4 RPC Calls Required

| Call | Contract | Purpose |
|------|----------|---------|
| `votingPowerAt(tokenId, ts)` | VotingEscrowIncreasing | VP per token at snapshot |
| `epochTotalVotingPowerCast(epoch)` | AddressGaugeVoter | Invariant verification |
| `getClaimedAmount(campaignId, addr)` | CapitalDistributorPlugin | Verify indexed claim totals |

All other state is reconstructed from indexed events. RPC calls at snapshot block are used for VP computation and invariant checks.

---

## 10. Operational Runbook

### Epoch Lifecycle

```
T+0h        Epoch N starts
T+1h        Voting window opens
T+6d23h     Voting closes                    ← SNAPSHOT TRIGGER
T+6d23h05m  Snapshot: run Steps 1-4, verify invariants
T+6d23h15m  Generate Merkle tree
T+7d        DAO withdraws fees from ExitQueue to treasury
T+7d+       Publish: endCampaign(prev) → createCampaign with cumulative Merkle root
T+14d       Epoch N+1 starts
```

### Recovery

- **Missed snapshot**: Re-compute from archived node at deterministic block height.
- **Bad Merkle root**: End the faulty campaign (`endCampaign`), create a corrected one. Users who already claimed from the faulty campaign have `alreadyClaimed` recorded — the corrected campaign must account for this (or use a fresh campaign and reconcile off-chain).
- **Invariant failure**: Halt, investigate root cause (re-org, missed event, RPC error), re-index if needed.

---

## 11. Security Considerations

1. **Snapshot timing**: Always after voting closes. The 5-minute buffer ensures finality.
2. **Delegation gaming**: Rewards go to original token owners. Receiving delegations doesn't inflate your reward share — the delegator gets credit for their own VP.
3. **Vote-then-reset**: Correctly excluded at Step 1 (no active votes at snapshot).
4. **Merkle replay**: Each campaign has its own `alreadyClaimed` tracking. A user can only claim their adjusted cumulative amount once per campaign.
5. **Claim race condition**: The previous campaign MUST be ended before reading `total_claimed` and building the new tree. This prevents a user from claiming on the old campaign after the backend has already factored in their unclaimed balance.
6. **Brief unavailability**: There is a short window between `endCampaign(prev)` and `createCampaign(new)` where no campaign is active. Keep this to seconds.

---

## 12. Summary

| Aspect | Decision |
|--------|----------|
| **Reward basis** | Voting power (curve-adjusted) attributed to original token owner |
| **Delegation handling** | Delegator gets rewards for their own VP, even if someone else voted with it |
| **Undelegated tokens** | Zero VP, zero rewards |
| **Partial voting** | Not possible — `vote()` uses 100% of `getVotes()` |
| **Snapshot timing** | `epochStart + 6d23h + 5min` |
| **Multi-epoch claims** | New campaign per epoch with cumulative Merkle tree — single `claimCampaignPayout()` on latest campaign |
| **Distribution contract** | Capital Distributor + MerkleDistributorStrategy |
| **Fee source** | ExitQueue → DAO treasury → Capital Distributor payout |
| **Invariants** | 4 checkpoints, each verified before proceeding |
