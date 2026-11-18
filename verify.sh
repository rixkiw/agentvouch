#!/usr/bin/env bash
# Verify AgentVouch source on BscScan (Etherscan V2 multichain endpoint) and
# fall back to Sourcify when no API key is available.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"

ADDR="${1:?usage: ./verify.sh 0xCONTRACT}"
RPC="${RPC:-https://bsc-dataseed.binance.org}"

echo "== flatten =="
forge flatten src/AgentVouch.sol > AgentVouch.flat.sol
wc -l AgentVouch.flat.sol

if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
  echo "== forge verify (etherscan v2, chainid 56) =="
  forge verify-contract "$ADDR" src/AgentVouch.sol:AgentVouch \
    --chain 56 \
    --verifier etherscan \
    --verifier-url "https://api.etherscan.io/v2/api?chainid=56" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    --num-of-optimizations 200 \
    --compiler-version 0.8.20 \
    --constructor-args "" || true
else
  echo "ETHERSCAN_API_KEY not set -> trying Sourcify"
  forge verify-contract "$ADDR" src/AgentVouch.sol:AgentVouch \
    --chain 56 --verifier sourcify --num-of-optimizations 200 || true
fi

echo
echo "manual fallback (BscScan UI, single file, MIT, optimizer 200 runs, solc 0.8.20):"
echo "  https://bscscan.com/verifyContract-solc?a=$ADDR"
echo "  file to paste: $(pwd)/AgentVouch.flat.sol"
echo "  constructor arguments: (none)"
