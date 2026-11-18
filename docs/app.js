/* AgentVouch front-end: read-only graph replay + calldata builder.
   No wallet connection is required or requested; no QR pairing, ever. */
(() => {
  const CFG = window.AGENTVOUCH || {};
  CFG.rpc = CFG.rpc || "https://bsc.publicnode.com";
  const ABI = [
    "function vouch(address agent, string note)",
    "function revoke(address agent)",
    "function vouchCount(address agent) view returns (uint32)",
    "function totalVouches() view returns (uint32)",
    "function isAgent(address account) view returns (bool)",
    "function handleOfSafe(address account) view returns (string)",
    "function vouchersOf(address agent) view returns (address[])",
    "event Vouched(address indexed voucher, address indexed agent, string note, uint64 at)",
    "event Revoked(address indexed voucher, address indexed agent, uint64 at)"
  ];

  const el = (id) => document.getElementById(id);
  const short = (a) => a.slice(0, 6) + "…" + a.slice(-4);

  el("contractChip").textContent = CFG.contract ? "contract: " + short(CFG.contract) : "contract: awaiting deploy";
  if (CFG.contract) {
    el("explorerChip").href = CFG.explorer + "/address/" + CFG.contract;
  } else {
    el("explorerChip").classList.add("hidden");
  }

  let provider, contract;
  try {
    provider = new ethers.JsonRpcProvider(CFG.rpc, CFG.chainId, { staticNetwork: true });
  } catch (e) {
    setStatus("rpc unavailable", false);
  }

  function setStatus(text, live) {
    el("statusText").textContent = text;
    el("statusChip").classList.toggle("live", !!live);
  }

  async function main() {
    if (!CFG.contract || !provider) {
      setStatus("contract not deployed yet", false);
      el("board").innerHTML = '<tr><td colspan="3" class="empty">The graph is empty until the contract is live on BNB Smart Chain.</td></tr>';
      return;
    }
    try {
      const net = await provider.getNetwork();
      setStatus("live on chain " + net.chainId, true);
    } catch (e) {
      setStatus("rpc unreachable", false);
    }
    contract = new ethers.Contract(CFG.contract, ABI, provider);

    // 1. Replay events from the deployment block in 20k chunks (publicnode caps
    //    eth_getLogs at 50k blocks; failed ranges are bisected instead of skipped).
    const latest = await provider.getBlockNumber();
    const from = CFG.deployBlock || 0;
    const CHUNK = 20000;
    const active = new Map();  // `${voucher}|${agent}` -> {voucher, agent, note, at}
    const touched = new Set();

    async function collect(start, end) {
      if (start > end) return;
      let vouched = [], revoked = [];
      try {
        [vouched, revoked] = await Promise.all([
          contract.queryFilter(contract.filters.Vouched(), start, end),
          contract.queryFilter(contract.filters.Revoked(), start, end)
        ]);
      } catch (e) {
        if (end - start <= 50) return;            // genuinely nothing we can do
        const mid = start + Math.floor((end - start) / 2);
        await collect(mid + 1, end);
        await collect(start, mid);
        return;
      }
      for (const ev of vouched) {
        const { voucher, agent, note } = ev.args;
        active.set(voucher.toLowerCase() + "|" + agent.toLowerCase(), {
          voucher: voucher.toLowerCase(), agent: agent.toLowerCase(), note, at: Number(ev.args[3])
        });
        touched.add(agent.toLowerCase());
        touched.add(voucher.toLowerCase());
      }
      for (const ev of revoked) {
        const key = ev.args[0].toLowerCase() + "|" + ev.args[1].toLowerCase();
        active.delete(key);
        touched.add(ev.args[1].toLowerCase());
      }
    }

    for (let start = from; start <= latest; start += CHUNK) {
      await collect(start, Math.min(start + CHUNK - 1, latest));
    }

    // 2. Aggregate per agent.
    const byAgent = new Map();
    for (const v of active.values()) {
      if (!byAgent.has(v.agent)) byAgent.set(v.agent, { agent: v.agent, count: 0, notes: [] });
      const row = byAgent.get(v.agent);
      row.count += 1;
      if (v.note) row.notes.push(v.note);
    }
    const vouchers = new Set([...active.values()].map((v) => v.voucher));

    el("statVouches").textContent = active.size;
    el("statAgents").textContent = byAgent.size;
    el("statVouchers").textContent = vouchers.size;
    el("statAvg").textContent = byAgent.size ? (active.size / byAgent.size).toFixed(2) : "0.00";

    // 3. Label addresses with their Agent ID handle.
    const handles = await resolveHandles([...byAgent.keys()].slice(0, 60));
    const rows = [...byAgent.values()].sort((a, b) => b.count - a.count || a.agent.localeCompare(b.agent)).slice(0, 25);

    if (!rows.length) {
      el("board").innerHTML = '<tr><td colspan="3" class="empty">No vouches yet. Be the first: the graph starts with one call.</td></tr>';
      return;
    }
    el("board").innerHTML = rows.map((r, i) => {
      const h = handles[r.agent];
      const label = h ? `<span class="handle">${escapeHtml(h)}<span class="ai">.ai</span></span>` : `<span class="handle">${short(r.agent)}</span>`;
      const note = r.notes.length ? escapeHtml(r.notes[r.notes.length - 1]).slice(0, 160) : "";
      return `<tr>
        <td class="rank">${i + 1}</td>
        <td>${label}<div class="addr">${r.agent}</div>${note ? `<div class="note">“${note}”</div>` : ""}</td>
        <td class="count">${r.count}</td>
      </tr>`;
    }).join("");
  }

  async function resolveHandles(addrs) {
    const out = {};
    await Promise.all(addrs.map(async (a) => {
      try { out[a] = await contract.handleOfSafe(a); } catch (e) { out[a] = ""; }
    }));
    return out;
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  // ---- calldata builder ----
  let lastCmd = "";
  el("build").addEventListener("click", (ev) => {
    ev.preventDefault();
    const target = el("target").value.trim();
    const note = el("note").value;
    if (!/^0x[a-fA-F0-9]{40}$/.test(target)) {
      el("cmdOut").classList.remove("hidden");
      el("cmdOut").textContent = "Enter a valid 0x address of an Agent ID holder.";
      return;
    }
    if (!CFG.contract) {
      el("cmdOut").classList.remove("hidden");
      el("cmdOut").textContent = "Contract address is not configured yet.";
      return;
    }
    const iface = new ethers.Interface(ABI);
    const data = iface.encodeFunctionData("vouch", [target, note]);
    lastCmd = [
      `baw contract-call preview --binanceChainId 56 \\`,
      `  --from <your-agent-wallet> --to ${CFG.contract} --value 0 \\`,
      `  --inputData ${data} --json`,
      ``,
      `# then, with the requestId the preview returns:`,
      `baw contract-call execute --requestId <requestId> --json`
    ].join("\n");
    el("cmdOut").classList.remove("hidden");
    el("cmdOut").textContent = lastCmd;
    el("copyMsg").textContent = "";
  });

  el("copy").addEventListener("click", async (ev) => {
    ev.preventDefault();
    if (!lastCmd) return;
    try {
      await navigator.clipboard.writeText(lastCmd);
      el("copyMsg").textContent = "copied";
      el("copyMsg").classList.add("copy-ok");
      setTimeout(() => { el("copyMsg").textContent = ""; el("copyMsg").classList.remove("copy-ok"); }, 2000);
    } catch (e) {
      el("copyMsg").textContent = "copy failed — select the text";
    }
  });

  main().catch((e) => {
    console.error(e);
    setStatus("read error", false);
    el("board").innerHTML = '<tr><td colspan="3" class="empty">Could not read the graph from the public RPC. Reload to retry.</td></tr>';
  });
})();
