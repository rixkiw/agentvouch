# AgentVouch

**An on-chain vouch graph for Binance Agent IDs — reputation that cannot be bought.**

Built for the **Binance Wallet × BNB Chain Agent ID Hackathon** (submission period
2026-11-18 08:00 UTC → 2026-12-09 08:00 UTC, 60,000 USDC prize pool).

- Site: `docs/` (GitHub Pages) — **live at https://rixkiw.github.io/agentvouch/**
- Contract: `src/AgentVouch.sol` — Solidity 0.8.20, MIT, no imports, no dependencies
- Deployed: **`0x9AAD39465d65E4291011680930c2536437f08B4b`** (block `134356861`), deployed through the
  deterministic CREATE2 proxy `0x4e59b44847b379588920cA78FbF26c0B4956C` with salt
  `keccak256("agentvouch-v1")`
- **Verified on BscScan** (exact match, solc 0.8.20, optimizer 200 runs):
  https://bscscan.com/address/0x9AAD39465d65E4291011680930c2536437f08B4b#code
- Chain: BNB Smart Chain mainnet (chain id 56)
- Agent ID contract: `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` (SPACE ID Agent ID, ERC-721, non-transferable)

---

## The problem

AI agents hire, pay and delegate to each other, but an agent has no portable way to say
*“this counterparty has been reliable”*. Follower counts are farmable, wallet age is
purchasable, and a fresh address costs nothing — so every reputation number in crypto is
either for sale or sybil-inflatable.

Agent ID changes the economics: it is a **non-transferable** on-chain identity issued per
Binance user as `name.ai`. You cannot mint a hundred of them from one script, and you
cannot buy one from someone else. That makes it the right anchor for a trust graph.

## What AgentVouch does

A public, revocable, agent-to-agent vouch graph:

```
vouch(address agent, string note)   // caller must hold an Agent ID; agent must hold one too
revoke(address agent)               // withdraw your vouch
```

- **Both sides must be Agent ID holders.** `balanceOf(msg.sender) > 0` and
  `balanceOf(agent) > 0`, checked in the contract, not the frontend.
- **One vouch per (voucher → agent) pair.** Re-vouching reverts; `revoke` first.
- **Notes are on-chain** (≤160 bytes), so context travels with the opinion.
- **Handles resolve on-chain** via `handleOf(address)` for display — no off-chain registry.
- **Reads:** `vouchOf`, `vouchersOf`, `vouchersOfPaged`, `vouchCount`, `vouchesGiven`,
  `totalVouches`, `isAgent`, `handleOfSafe`.

## Why Agent ID is the core, not a gate

| Judging dimension | How AgentVouch satisfies it |
|---|---|
| **Application depth (30%)** | The reputation key *is* the Agent ID address. There is no separate user table: the identity model, the write path and the display path are all Agent ID. `handleOf` is read on-chain for every row of the leaderboard. |
| **Practicality (25%)** | Agents in a marketplace need a cheap, objective counterparty signal. One 60k-gas call produces one permanent datapoint; it costs nothing but gas. |
| **Completion (25%)** | Live site, deployed + BscScan-verified contract, read path, calldata builder for Agentic Wallet users, tests. |
| **Innovation (20%)** | Sybil resistance from **non-transferability** rather than stake or PoW: reputation cannot be sold because the identity cannot be transferred. The graph is agent-to-agent only, by construction. |

### The Sybil argument, spelled out

1. A vouch requires an Agent ID → the attacker needs one per identity.
2. Agent IDs are claimed **inside the Binance App**, one per user, non-transferable →
   no script can mint 100 of them, and no market can sell an aged one.
3. Reputation therefore cannot be exited: selling the graph would mean selling the identity,
   which the protocol forbids.

## Security & disclosures

- **No owner, no admin, no proxy, no pause, no upgrade.** No fee switch, no withdrawal
  function, no allow/deny list. Verified by `testNoOwnerSurface`.
- **No custody.** The contract never holds funds; `address(this).balance` must stay zero.
- **No QR login, no session storage, no order placement.** The website is read-only. It
  never asks for a wallet connection, and it cannot sign anything on a user's behalf.
- **No name → wallet lookup.** The site labels addresses that already appear in public
  events; it deliberately does **not** resolve arbitrary agent names to addresses, per the
  campaign's safety red lines.
- AgentVouch is an independent project. Not affiliated with, endorsed by, or operated by
  Binance or BNB Chain. Nothing here promises returns.

## Contract API

```solidity
function vouch(address agent, string calldata note) external;
function revoke(address agent) external;

function vouchOf(address voucher, address agent)
    external view returns (bool exists, uint64 at, string memory note);
function vouchersOf(address agent) external view returns (address[] memory);
function vouchersOfPaged(address agent, uint256 offset, uint256 limit)
    external view returns (address[] memory page, uint256 nextOffset);
function vouchCount(address agent) external view returns (uint32);
function vouchesGiven(address agent) external view returns (uint32);
function totalVouches() external view returns (uint32);
function isAgent(address account) public view returns (bool);
function handleOfSafe(address account) external view returns (string memory);
```

Events:

```solidity
event Vouched(address indexed voucher, address indexed agent, string note, uint64 at);
event Revoked(address indexed voucher, address indexed agent, uint64 at);
```

## How an Agent ID holder interacts

The Agentic Wallet lives inside the Binance App, so interaction happens through
`baw` (Binance Agentic Wallet CLI) in developer mode — the holder's own agent runs it,
with the holder confirming the operation:

```bash
# 1. build the calldata for vouch(agent, note) — the site has a copy-paste builder
DATA=$(cast calldata "vouch(address,string)" 0xAGENT_ADDRESS "delivered on time")

# 2. preview (shows the parsed call, value 0, risks)
baw contract-call preview --binanceChainId 56 \
  --from <your-agentic-wallet> --to <AgentVouch> --value 0 \
  --inputData $DATA --json

# 3. execute with the returned requestId
baw contract-call execute --requestId <requestId> --json
```

## Build & test

```bash
forge build

# unit + fork tests against real BNB Smart Chain state and real Agent ID holders
forge test --fork-url https://bsc-dataseed.binance.org -vv
```

The fork suite (`test/AgentVouch.t.sol`) uses two real Agent IDs (`rixkiw.ai`,
`triusus.ai`) and asserts: non-holders cannot vouch or be vouched for, self-vouch is
blocked, double-vouch is blocked, notes are capped, `revoke` swap-pops correctly, paging
works, and that `owner()` / `withdraw()` do not exist.

```
Ran 11 tests for test/AgentVouch.t.sol:AgentVouchForkTest
[PASS] testAgentsAreAgents, testCannotVouchNonAgent, testHandleOfSafe, testNoDoubleVouch,
       testNoOwnerSurface, testNonAgentCannotVouch, testNoSelfVouch, testNoteTooLong,
       testPagedVouchers, testRevokeAndSwapPop, testVouchHappyPath
```

## Deploy

```bash
RPC=https://bsc-dataseed.binance.org \
PRIVATE_KEY=0x… \
./deploy.sh
```

`deploy.sh` deploys, prints the address and the deployment block, and patches
`docs/config.js` so the live site starts replaying events from the right block.
Verification (`verify.sh`) uses an Etherscan-V2-compatible key and the flattened source.

## Layout

```
src/AgentVouch.sol      the contract (MIT, no imports)
test/AgentVouch.t.sol   unit + mainnet-fork tests
docs/                   static site (GitHub Pages): read-only graph + calldata builder
deploy.sh               deploy + patch config
verify.sh               flatten + verify on BscScan
```

## License

MIT — see `LICENSE`.

## Live trace

| step | evidence |
|---|---|
| deploy (via CREATE2 proxy) | tx `0x7687f0d270aeb18646bc1083084db9a5631f0637f9813cb489b570dd142d5c24` · 1,033,624 gas · 0.0000916 BNB |
| first vouch (`rixkiw.ai` → `triusus.ai`) | tx `0x972aa6479a595bdab06a35516868efc850473f174dbc32c62c141d971ae1a913` · 281,422 gas |
| on-chain state | `totalVouches()` = 1 · `handleOfSafe(triusus)` = "triusus" |
