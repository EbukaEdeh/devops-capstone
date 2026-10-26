(() => {
  "use strict";

  const totalEl = document.getElementById("total");
  const statusEl = document.getElementById("connection-status");
  const statusTextEl = document.getElementById("status-text");
  const updatedEl = document.getElementById("updated-at");
  const rows = new Map(
    [...document.querySelectorAll(".result-row")].map((row) => [row.dataset.choice, row])
  );

  const formatNumber = new Intl.NumberFormat("en-US").format;

  function relativeTime(isoString) {
    if (!isoString) return "just now";
    const seconds = Math.max(0, Math.round((Date.now() - new Date(isoString).getTime()) / 1000));
    if (seconds < 5) return "just now";
    if (seconds < 60) return `${seconds}s ago`;
    return `${Math.floor(seconds / 60)}m ago`;
  }

  function render(data) {
    totalEl.textContent = formatNumber(data.total);
    updatedEl.textContent = relativeTime(data.updated_at);

    for (const choice of data.choices) {
      const row = rows.get(choice.id);
      if (!row) continue;
      row.querySelector(".count").textContent = formatNumber(choice.count);
      row.querySelector(".percent").textContent = `${choice.percent.toFixed(1)}%`;
      row.querySelector(".bar-fill").style.width = `${Math.min(choice.percent, 100)}%`;
    }

    statusEl.classList.remove("offline");
    statusTextEl.textContent = "Live from PostgreSQL";
  }

  function markOffline() {
    statusEl.classList.add("offline");
    statusTextEl.textContent = "Reconnecting to the database";
  }

  async function refresh() {
    try {
      const response = await fetch("/api/results", { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      render(await response.json());
    } catch (error) {
      console.warn("result refresh failed", error);
      markOffline();
    }
  }

  if (window.__INITIAL_RESULTS__) {
    render(window.__INITIAL_RESULTS__);
  }

  setInterval(refresh, 2000);
})();
