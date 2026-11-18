#!/usr/bin/env bash
# Deploy AgentVouch to BNB Smart Chain and patch the site config.
set -euo pipefail
cd "$(dirname "$0")"

RPC="${RPC:-https://bsc-dataseed.binance.org}"
export PATH="$HOME/.foundry/bin:$PATH"

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "PRIVATE_KEY not set" >&2
  exit 1
fi

echo "== gas price =="
cast gas-price --rpc-url "$RPC"

echo "== deploy =="
OUT=$(forge create src/AgentVouch.sol:AgentVouch \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY" \
  --broadcast --json)

ADDR=$(echo "$OUT" | python3 -c "import sys,json;print(json.load(sys.stdin)['deployedTo'])")
TX=$(echo "$OUT" | python3 -c "import sys,json;print(json.load(sys.stdin)['transactionHash'])")
echo "contract: $ADDR"
echo "tx:       $TX"

echo "== receipt =="
cast receipt "$TX" --rpc-url "$RPC" --json | python3 -c "
import sys,json
r=json.load(sys.stdin)
print('status',r['status'],'block',int(r['blockNumber'],16),
      'gasUsed',int(r['gasUsed'],16),
      'effGasPrice',int(r['effectiveGasPrice'],16))
"

BLOCK=$(cast receipt "$TX" --rpc-url "$RPC" --json | python3 -c "import sys,json;print(int(json.load(sys.stdin)['blockNumber'],16))")

python3 - "$ADDR" "$BLOCK" <<'PY'
import re, sys
addr, block = sys.argv[1], sys.argv[2]
p = "docs/config.js"
s = open(p).read()
s = re.sub(r'contract: "[^"]*"', f'contract: "{addr}"', s)
s = re.sub(r'deployBlock: \d+', f'deployBlock: {block}', s)
open(p, "w").write(s)
print("patched", p)
PY

echo
echo "next: ./verify.sh $ADDR"
