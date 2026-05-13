// ui-handlers.js
import { sendWS } from "./websocket.js";
import {
  appState,
  updateCollapsedClusters,
  updateCalendarCollapsed,
} from "./state.js";
import { renderJobsTable } from "./tree/tree-table.js";
import { openCronsModal } from "./modals.js";
import {
  updateRow,
  insertRow,
  removeRow,
  updateLiveTimings,
} from "./tree/tree-table.js";

import {
  formatDate,
  formatDuration,
  formatTplus,
  formatTminus,
  formatUptime,
  formatRelativeTime,
  buildTree,
  traverseTree,
  findClusterById,
  findJobById,
  getFullPath,
  removeJobById,
  debugDumpMonitorTree,
  removeClusterById
} from "./utils.js";

export function showLoading(containerId) {
  const loading = document.getElementById(containerId);
  if (loading) loading.style.display = "block";
}

export function hideLoading(containerId) {
  const loading = document.getElementById(containerId);
  if (loading) loading.style.display = "none";
}

export function showToast(message, type = "info") {
  let container = document.getElementById("toast-container");
  if (!container) {
    container = document.createElement("div");
    container.id = "toast-container";
    document.body.appendChild(container);
  }

  const toast = document.createElement("div");
  toast.className = `toast ${type} show`;
  toast.setAttribute("role", "alert");
  toast.setAttribute("aria-live", "polite");

  const iconClass =
    {
      success: "check-circle",
      info: "info-circle",
      warning: "exclamation-triangle",
      danger: "times-circle",
    }[type] || "info-circle";

  toast.innerHTML = `
    <i class="fas fa-${iconClass}"></i>
    <span>${message}</span>
    <button class="close-btn" aria-label="Close">×</button>
  `;

  container.appendChild(toast);

  // Auto-dismiss
  const duration = type === "danger" ? 8000 : type === "warning" ? 6000 : 4000;
  setTimeout(() => {
    toast.classList.remove("show");
    setTimeout(() => toast.remove(), 400); // fade-out duration
  }, duration);

  // Manual close
  toast.querySelector(".close-btn").onclick = () => {
    toast.classList.remove("show");
    setTimeout(() => toast.remove(), 400);
  };
}

export function updateFreshnessCell(row, server, now) {
  const updateTime =
    server.update_time != null ? Number(server.update_time) : null;
  const updatedAgo =
    updateTime != null && !isNaN(updateTime) ? now - updateTime : Infinity;

  let status = "Never Connected";
  let statusClass = "is-danger";
  let statusTooltip = "No stats received yet — server may still accept jobs";

  if (Number.isFinite(updatedAgo)) {
    if (updatedAgo < 30) {
      status = "Fresh";
      statusClass = "is-success";
    } else if (updatedAgo < 300) {
      status = "Stale";
      statusClass = "is-warning";
    } else {
      status = "Very Stale";
      statusClass = "is-danger";
    }
  }

  // Add zombie info to tooltip only
  if (server.zombie_processes > 0) {
    statusTooltip += `\nZombies detected: ${server.zombie_processes}`;
  }

  // Calculate current relative time (second-level precision)
  let relTime = "—";
  if (Number.isFinite(updatedAgo)) {
    relTime = formatRelativeTime(updatedAgo);
  }

  // Update tag
  const tag = row.querySelector("span.tag");
  if (tag) {
    tag.textContent = status;
    tag.className = `tag ${statusClass}`;
    tag.title = statusTooltip;
  }

  // Update inline time text
  const timeSpan = row.querySelector("td.time-text");
  if (timeSpan) {
    timeSpan.textContent = relTime;
  }

  // Stale row hint
  if (Number.isFinite(updatedAgo) && updatedAgo > 300) {
    row.classList.add("stale");
  } else {
    row.classList.remove("stale");
  }
}

export function renderServersTable() {
  const tbody = document.getElementById("servers-body");
  const table = document.getElementById("servers-table");
  const noServers = document.getElementById("no-servers");

  if (!tbody || !table || !noServers) return;

  if (!appState.serversData || appState.serversData.length === 0) {
    table.style.display = "none";
    noServers.style.display = "block";
    return;
  }

  table.style.display = "table";
  noServers.style.display = "none";
  tbody.innerHTML = "";

  const now = Math.floor(Date.now() / 1000);

  appState.serversData.forEach((server, index) => {
    const updateTime =
      server.update_time != null ? Number(server.update_time) : null;
    const updatedAgo =
      updateTime != null && !isNaN(updateTime) ? now - updateTime : Infinity;

    let relTime = "—";
    if (Number.isFinite(updatedAgo)) {
      relTime = formatRelativeTime(updatedAgo);
    }

    // Load Avg
    const load1 = server.load_1 != null ? server.load_1.toFixed(2) : "—";
    const coresText = server.cores != null ? ` (on ${server.cores} cores)` : "";
    const loadTooltip =
      server.load_1 != null
        ? `1-min: ${server.load_1.toFixed(2)}${coresText}\n5-min: ${server.load_5?.toFixed(2) ?? "—"}\n15-min: ${server.load_15?.toFixed(2) ?? "—"}`
        : "Load averages not available";

    // CPU %
    const cpu =
      server.cpu_percent != null ? `${server.cpu_percent.toFixed(1)}%` : "—";
    const cpuTooltip = "True CPU utilization (user + system) from top snapshot";

    // Memory + Swap
    let mem = "—";
    let memTooltip = "Memory usage not available";
    if (server.total_memory != null && server.total_memory > 0) {
      const usedBytes = server.used_memory != null ? server.used_memory : 0;
      const totalBytes = server.total_memory;
      let unit = "GB";
      let divisor = 1024 * 1024 * 1024;
      let precision = 1;
      if (totalBytes < 10 * 1024 * 1024 * 1024) {
        unit = "MB";
        divisor = 1024 * 1024;
        precision = 2;
      }
      const usedDisplay = (usedBytes / divisor).toFixed(precision);
      const totalDisplay = (totalBytes / divisor).toFixed(precision);
      const pct = (usedBytes / totalBytes) * 100;
      const memPct = isNaN(pct) ? "—" : pct.toFixed(1);
      mem = `${memPct}% (${usedDisplay}/${totalDisplay} ${unit})`;
      const swapPct =
        server.total_swap != null && server.total_swap > 0
          ? (((server.used_swap || 0) / server.total_swap) * 100).toFixed(1) +
            "%"
          : "—";
      memTooltip = `RAM: ${memPct}% (${usedDisplay}/${totalDisplay} ${unit})\nSwap: ${swapPct}`;
    }

    // Disk (server sends values in KB)
    let disk = "—";
    let diskTooltip = "Disk usage not available";
    if (server.total_disk != null && server.total_disk > 0) {
      const usedKB = Number(server.used_disk || 0);
      const totalKB = Number(server.total_disk);
      const usedGB = usedKB / 1024 / 1024;
      const totalGB = totalKB / 1024 / 1024;

      let unit = "GB";
      let precision = 2;
      if (totalGB >= 1000) {
        unit = "TB";
        precision = 2;
      } else if (totalGB < 1) {
        unit = "MB";
        precision = 0;
      }

      const usedDisplay = usedGB.toFixed(precision);
      const totalDisplay = totalGB.toFixed(precision);
      const pct = totalGB > 0 ? (usedGB / totalGB) * 100 : 0;
      const diskPct = pct.toFixed(1);

      disk = `${diskPct}% (${usedDisplay}/${totalDisplay} ${unit})`;

      let rootInfo = "";
      if (server.root_total_disk != null && server.root_total_disk > 0) {
        const rootPct = (
          ((server.root_used_disk || 0) / server.root_total_disk) *
          100
        ).toFixed(1);
        rootInfo = `\nRoot: ${rootPct}%`;
      }
      diskTooltip = `Aggregate: ${diskPct}% (${usedDisplay}/${totalDisplay} ${unit})${rootInfo}`;
    }

    // Uptime
    const uptime = server.uptime != null ? formatUptime(server.uptime) : "—";

    // Host tooltip
    const pingText =
      typeof server.ping === "number" && !isNaN(server.ping)
        ? server.ping.toFixed(3) + "s"
        : "—";
    const hostTooltip = [
      `Host: ${server.host || server.ip_address || "—"}`,
      `Port: ${server.port || "—"}`,
      `Ping: ${pingText}`,
      `OS: ${server.os || "—"}`,
      `CWD: ${server.cwd || "—"}`,
      `Home: ${server.home || "—"}`,
    ]
      .filter(Boolean)
      .join("\n");

    // Row creation
    const tr = document.createElement("tr");
    tr.dataset.updateTime = server.update_time || "";
    tr.innerHTML = `
      <td>${server.name || "—"}</td>
      <td title="${hostTooltip}">
        ${server.host || server.ip_address || "—"}
      </td>
      <td>
        <span class="tag is-danger" title="">Never Connected</span>
      </td>
      <td class="time-text text-grey">${relTime}</td>
      <td title="${loadTooltip}">${load1}</td>
      <td title="${cpuTooltip}">${cpu}</td>
      <td title="${memTooltip}">${mem}</td>
      <td title="${diskTooltip}">${disk}</td>
      <td title="Server uptime">${uptime}</td>
      <td>
        <div class="dropdown is-right">
          <div class="dropdown-trigger">
            <button class="btn btn-sm btn-ghost" aria-haspopup="menu" title="Actions">
              <i class="fas fa-ellipsis-v"></i>
            </button>
          </div>
          <div class="dropdown-menu" role="menu">
            <div class="dropdown-content">
              <a href="#" class="dropdown-item" data-action="edit-server" data-id="${server.id}">Edit</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item is-danger" data-action="delete-server" data-id="${server.id}">Delete</a>
            </div>
          </div>
        </div>
      </td>
    `;
    tbody.appendChild(tr);

    updateFreshnessCell(tr, server, now);
  });
}

// ==================== TIER LIMITS ====================
const tierLimits = {
  free:    { api: 1000,  servers: 3,  members: 2 },
  starter: { api: 50000, servers: 10, members: 5 },
  pro:     { api: 100000,servers: 30, members: 10 },
  custom:  { api: Infinity, servers: Infinity, members: Infinity }
};

// ==================== RENDER FUNCTIONS ====================

export function updateAccount(data) {
  if (data.command_reply === 'read_user') {
    appState.accountData = data;
    renderUserProfile(data);
  }
}

export function updateOrgAndTeam(data) {
  if (data.command_reply === 'read_org') {
    appState.orgData = data;
    renderOrgAndBilling(data);
    renderTeamMembers(data.members || []);
  }
}

function renderUserProfile(user) {
  document.getElementById('account-email').textContent = user.email || '—';
  document.getElementById('account-id').textContent = user.id || '—';
  document.getElementById('account-level').textContent = user.level || '—';
  document.getElementById('account-remote').textContent = user.remote_address || '—';

  const nameInput = document.getElementById('edit-name');
  if (nameInput) nameInput.value = user.name || '';

  const tokenInput = document.getElementById('account-token');
  if (tokenInput) tokenInput.value = user.token || '';
}

function renderOrgAndBilling(org) {
  document.getElementById('org-id').textContent = org.id || '—';

  const nameInput = document.getElementById('edit-org-name');
  if (nameInput) nameInput.value = org.name || '';

  const descInput = document.getElementById('edit-org-desc');
  if (descInput) descInput.value = org.description || '';

  // Tier
  const tierEl = document.getElementById('account-tier');
  if (tierEl) {
    tierEl.textContent = (org.tier || 'free').toUpperCase();
  }

  // Servers
  const serverCount = org.server_count !== undefined 
    ? org.server_count 
    : (appState.serversData ? appState.serversData.length : 0);
  document.getElementById('server-usage-text').textContent = `${serverCount} / 3`;

  // Team Members
  const memberCount = org.members ? org.members.length : 0;
  document.getElementById('team-usage-text').textContent = `${memberCount} / 2`;

  // API Usage
  const apiUsed = Number(org.api_calls_this_month) || 0;
  const apiMax = tierLimits[org.tier || 'free'].api || 1000;
  document.getElementById('api-usage-text').textContent = 
    `${apiUsed} / ${apiMax === Infinity ? '∞' : apiMax}`;

  const progress = document.getElementById('api-progress');
  if (progress) {
    progress.value = apiMax === Infinity ? 0 : Math.min(100, Math.round((apiUsed / apiMax) * 100));
  }

  document.getElementById('api-period').textContent = 
    `Current period: ${org.current_month_year || '—'}`;
}

function renderTeamMembers(members) {
  const tbody = document.getElementById('team-body');
  const noTeam = document.getElementById('no-team');
  if (!tbody) return;

  tbody.innerHTML = '';

  if (!members || members.length === 0) {
    noTeam.style.display = 'block';
    return;
  }

  noTeam.style.display = 'none';

  members.forEach(m => {
    const row = document.createElement('tr');
    row.innerHTML = `
      <td>${m.email || '—'}</td>
      <td>${m.id || '—'}</td>
      <td>${m.level === 1 ? 'Admin' : 'Member'}</td>
      <td>${m.creation_time ? new Date(m.creation_time * 1000).toLocaleDateString() : '—'}</td>
    `;
    tbody.appendChild(row);
  });
}

// ==================== ACTIONS ====================

export async function refreshSettings() {
  try {
    await Promise.all([
      sendWS({ command: 'read_user' }),
      sendWS({ command: 'read_org' }),
      sendWS({ command: 'find_monitor' })
    ]);
    console.log('[Settings] Data refreshed');
  } catch (e) {
    console.error('[Settings] Refresh failed', e);
  }
}

export async function saveAccount() {
  const userPayload = { 
    command: 'update_user',
    name: document.getElementById('edit-name').value.trim() 
  };

  const orgPayload = { 
    command: 'update_org',
    name: document.getElementById('edit-org-name').value.trim(),
    description: document.getElementById('edit-org-desc').value.trim()
  };

  try {
    if (userPayload.name) {
      await sendWS(userPayload);
    }
    await sendWS(orgPayload);

    showToast('Account saved successfully', 'success');
    await refreshSettings();
  } catch (e) {
    console.error(e);
    showToast('Failed to save account', 'danger');
  }
}

function copyToken() {
  const tokenField = document.getElementById('account-token');
  if (!tokenField?.value) return;

  const text = tokenField.value;

  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text)
      .then(() => showToast('Token copied to clipboard', 'success'))
      .catch(() => fallbackCopy(text));
  } else {
    fallbackCopy(text);
  }
}

function fallbackCopy(text) {
  const textarea = document.createElement('textarea');
  textarea.value = text;
  textarea.style.position = 'fixed';
  textarea.style.opacity = '0';
  document.body.appendChild(textarea);
  textarea.select();
  try {
    document.execCommand('copy');
    showToast('Token copied to clipboard', 'success');
  } catch (e) {
    showToast('Failed to copy token', 'danger');
  }
  document.body.removeChild(textarea);
}

export function updateLog(data) {
  const loading = document.getElementById("log-loading");
  const pre = document.getElementById("log-content");

  loading.style.display = "none";
  pre.style.display = "block";

  pre.textContent = data.out || "(no output captured)";
  pre.scrollTop = pre.scrollHeight;

  const jobName = data.job_name || "Unnamed Job";
  const jobId = data.job_id || "—";
  const runId = data.id || "latest"; // prefer log_id, fallback to id
  const serverName = data.server_name || "—";

  // Replace the current status calculation with this:

  let status = "Success";
  let statusClass = "success"; // for optional coloring later

  if (data.signal != null && data.signal !== 0) {
    status = `Terminated (signal ${data.signal})`;
    statusClass = "warning"; // or "danger" if you want red
  } else if (data.exit_code != null && data.exit_code !== 0) {
    status = `Failed (exit ${data.exit_code})`;
    statusClass = "danger";
  } else if (data.exit_code === 0) {
    status = "Success";
    statusClass = "success";
  } else {
    status = "—";
    statusClass = "unknown";
  }

  // Then in title:
  document.getElementById("log-modal-title").textContent =
    `Job: ${jobName} • ID: ${jobId} • Run: ${runId} (${status})`;

  // Optional: add a CSS class to the title for color
  document.getElementById("log-modal-title").className =
    `modal-title ${statusClass}`;

  // Two-line subtitle
  const startDate = data.started ? formatDate(data.started) : "—";
  const duration = formatDuration(data.started, data.ended);
  const pid = data.pid || "—";

  document.getElementById("log-modal-subtitle").innerHTML =
    `Path: ${data.job_path || "—"} • Server: ${serverName}<br>` +
    `Started: ${startDate} • Duration: ${duration} • PID: ${pid}`;
}

export function updateLogHistory(data) {
  if (data.command_reply !== 'find_log') {
    console.debug("Skipping updateLogHistory — not a find_log message");
    return;
  }

  console.log('Received find_log message:', data); // keep for debug

  // Normalize job IDs (handle string/number, missing values)
  const msgJobId = Number(data.job_id || data.id || '') || null;

  // Get current viewed job ID (try state first, then DOM fallback)
  const currentJobId = Number(
    appState.currentJobId ||
    document.querySelector('#job-detail-panel [data-job-id]')?.dataset.jobId ||
    document.querySelector('[data-job-id]')?.dataset.jobId ||
    ''
  ) || null;

  console.debug(`Current job view: ${currentJobId ?? 'none'}, message job_id: ${msgJobId ?? 'none'}`);

  // Skip only if BOTH IDs exist and don't match
  if (currentJobId && msgJobId && msgJobId !== currentJobId) {
    console.debug(`Ignoring log update for job ${msgJobId} (current view: ${currentJobId})`);
    return;
  }

  // Fallback: if no current view, assume it's for the message's job (common for broadcasts)
  if (!currentJobId && msgJobId) {
    console.debug(`No current job view — assuming logs are for job ${msgJobId}`);
  }

  const tbody = document.getElementById("log-history-body");
  const noHistory = document.getElementById("no-history");

  if (!tbody) {
    console.debug("Log history table not in DOM — skipping update");
    return;
  }

  // Show loading state
  tbody.innerHTML = '<tr><td colspan="4" class="text-center text-grey">Loading logs...</td></tr>';

  // Guard: no logs or invalid data
  if (!data || !Array.isArray(data.logs) || data.logs.length === 0) {
    tbody.innerHTML = '';
    if (noHistory) noHistory.style.display = "block";
    return;
  }

  if (noHistory) noHistory.style.display = "none";

  // Efficient DOM update with fragment
  const fragment = document.createDocumentFragment();

  data.logs.forEach((log) => {
    const row = document.createElement("tr");
    row.style.cursor = "pointer";

    row.innerHTML = `
      <td>${escapeHtml(String(log.id || '—'))}</td>
      <td>${formatDate(log.started) || "—"}</td>
      <td>${formatDuration(log.started, log.ended) || "—"}</td>
      <td>${getStatusText(log.exit_code, log.signal)}</td>
    `;

    row.addEventListener("click", () => {
      const modal = document.getElementById("log-modal");
      if (!modal) {
        console.warn("Log modal not found");
        return;
      }

      const jobId = modal.dataset.jobId;
      if (!jobId) {
        console.warn("No jobId in modal dataset — cannot load log");
        return;
      }

      appState.ws.send(
        JSON.stringify({
          command: "read_log",
          id: jobId,
          log_id: log.id,
        })
      );

      const historyModal = document.getElementById("log-history-modal");
      if (historyModal) historyModal.classList.remove("active");
    });

    fragment.appendChild(row);
  });

  tbody.innerHTML = '';
  tbody.appendChild(fragment);
}

// Helpers (add these at the bottom of ui-handlers.js if not already present)
function escapeHtml(unsafe) {
  return String(unsafe)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function getStatusText(exitCode, signal) {
  if (exitCode === 0) return "Success";
  if (exitCode != null) return `Failed (${exitCode})`;
  if (signal != null) return `Killed (signal ${signal})`;
  return "—";
}

export function updateJobsClusters(data) {
  hideLoading("monitor-loading");
  document.getElementById("monitor-content").style.display = "block";

  if (data.success) {
    appState.monitorData.tree = buildTree(data);
    debugDumpMonitorTree();        // ← Add this line

    // ────────────────────────────────────────────────
    // Clean up any collapsed IDs that no longer exist in the current tree
    const currentClusterIds = new Set();
    function collectClusterIds(nodes) {
      nodes.forEach((node) => {
        if (node.is_cluster) {
          currentClusterIds.add(String(node.id));
          if (node.children) collectClusterIds(node.children);
        }
      });
    }
    collectClusterIds(appState.monitorData.tree);

    let cleanedCount = 0;
    const before = [...appState.collapsedClusters];
    appState.collapsedClusters.forEach((id) => {
      if (!currentClusterIds.has(id)) {
        appState.collapsedClusters.delete(id);
        cleanedCount++;
      }
    });

    if (cleanedCount > 0) {
      updateCollapsedClusters(); // save cleaned set to localStorage
      console.log(
        `Cleaned ${cleanedCount} stale collapsed cluster ID(s):`,
        before.filter((id) => !currentClusterIds.has(id)),
      );
      // Optional: showToast(`View refreshed — removed collapsed state for ${cleanedCount} deleted cluster(s)`, "info");
    }
    // ────────────────────────────────────────────────

    renderJobsTable();
  }
}

export function updateCalendars(data) {
  hideLoading("calendars-loading");
  const content = document.getElementById("calendars-content");
  if (content) content.style.display = "block";

  if (data.success && Array.isArray(data.cals)) {
    appState.calendarsData = data.cals;
  } else {
    appState.calendarsData = [];
    console.log("No calendars found:", data.message || "empty response");
  }

  renderCalendarsTable();  // ensure this handles []
}

export function toggleCronsRow(calendarId) {
  const cronsRow = document.querySelector(
    `tr[data-cal-id="${calendarId}"].crons-row`,
  );
  if (!cronsRow) {
    return;
  }

  const wasHidden = cronsRow.classList.contains("hidden");
  cronsRow.classList.toggle("hidden");

  // Force visibility for table rows
  if (cronsRow.classList.contains("hidden")) {
    cronsRow.style.display = "none";
  } else {
    cronsRow.style.display = "table-row";
    cronsRow.style.minHeight = "200px"; // ← temporary test height
    cronsRow.style.background = "rgba(255, 0, 0, 0.3)"; // ← temporary red tint
  }

  const isNowHidden = cronsRow.classList.contains("hidden");

  const toggleBtn = document.querySelector(
    `.dropdown-item[data-action="view-crons"][data-id="${calendarId}"]`,
  );
  if (toggleBtn) {
    toggleBtn.textContent = isNowHidden ? "View Crons" : "Hide Crons";
  } else {
    console.warn("[DEBUG] Toggle button not found for calendarId:", calendarId);
  }
}

export function renderCalendarsTable() {
  const tbody = document.getElementById("calendars-body");
  const table = document.getElementById("calendars-table");
  const noCalendars = document.getElementById("no-calendars");

  // Guard: missing DOM elements
  if (!tbody || !table || !noCalendars) {
    console.warn("[renderCalendarsTable] Missing required DOM elements");
    return;
  }

  const calendars = appState.calendarsData || [];

  // Handle empty / no success case
  if (calendars.length === 0) {
    table.style.display = "none";
    noCalendars.style.display = "block";
    console.debug("[renderCalendarsTable] No calendars to display");
    return;
  }

  // Show table, hide empty state
  table.style.display = "table";
  noCalendars.style.display = "none";
  tbody.innerHTML = ""; // Clear previous rows

  calendars.forEach((cal) => {
    const hasCrons = Array.isArray(cal.crons) && cal.crons.length > 0;
    const isCollapsed = appState.collapsedCalendars.has(String(cal.id));

    // Calendar row
    const calRow = document.createElement("tr");
    calRow.className = `ordo-calendar-row ${isCollapsed ? "collapsed" : ""}`;
    calRow.dataset.id = cal.id;
    calRow.dataset.depth = "0";
    calRow.style.setProperty("--depth", "0");

    const toggleHtml = hasCrons
      ? `<span class="ordo-toggle"></span>`
      : `<span class="ordo-toggle empty"></span>`;

    calRow.innerHTML = `
      <td>${toggleHtml}<i class="fas fa-folder mr-2 has-text-info"></i>${cal.name || "Unnamed Calendar"}</td>
      <td>${cal.tz || "—"}</td>
      <td>${cal.description || "—"}</td>
      <td>${cal.crons?.length || 0}</td>
      <td>${cal.cluster_ids?.length || 0}</td>
      <td>—</td>
      <td>—</td>
      <td>—</td>
      <td>${generateCalendarActions(cal.id, hasCrons)}</td>
    `;
    tbody.appendChild(calRow);

    // Cron rows (if any)
    if (hasCrons) {
      cal.crons.forEach((cron, idx) => {
        const isLast = idx === cal.crons.length - 1;
        const cronRow = document.createElement("tr");
        cronRow.className = `ordo-cron-row ${isCollapsed ? "hidden" : ""}`;
        cronRow.dataset.id = `cron-${cal.id}-${cron.id}`;
        cronRow.dataset.depth = "1";
        cronRow.dataset.parent = cal.id;
        cronRow.dataset.lastChild = isLast ? "true" : "false";
        cronRow.style.setProperty("--depth", "1");

        const cronIcon = '<i class="fas fa-clock mr-2 has-text-cyan"></i>';
        cronRow.innerHTML = `
          <td>${cronIcon}${cron.name || cron.expression || "—"}</td>
          <td>${cron.english || "—"}</td>
          <td>${cron.description || "—"}</td>
          <td>—</td>
          <td>—</td>
          <td>${cron.begin ? formatDate(cron.begin) : "Immediate"}</td>
          <td>${cron.expire ? formatDate(cron.expire) : "Never"}</td>
          <td>${formatDate(cron.next_start) || "—"}</td>
          <td>${generateCronActions(cal.id, cron.id)}</td>
        `;
        tbody.appendChild(cronRow);
      });
    }
  });

  console.debug(`[renderCalendarsTable] Rendered ${calendars.length} calendars, ${calendars.reduce((sum, c) => sum + (c.crons?.length || 0), 0)} crons`);

  // Re-apply collapse states (in case of re-render)
  appState.collapsedCalendars.forEach(calId => {
    const row = document.querySelector(`tr[data-id="${calId}"]`);
    if (row) row.classList.add("collapsed");
  });
}

export function renderCalendarsTable2() {
  const tbody = document.getElementById("calendars-body");
  const table = document.getElementById("calendars-table");
  const noCalendars = document.getElementById("no-calendars");

  if (!tbody || !table || !noCalendars) return;

  const calendars = appState.calendarsData || [];

  if (calendars.length === 0) {
    table.style.display = "none";
    noCalendars.style.display = "block";
    return;
  }

  // Show table, hide empty state
  table.style.display = "table";
  noCalendars.style.display = "none";

  tbody.innerHTML = "";

  calendars.forEach((cal) => {
    const hasCrons = cal.crons && cal.crons.length > 0;
    const isCollapsed = appState.collapsedCalendars.has(String(cal.id));

    const calRow = document.createElement("tr");
    calRow.className = `ordo-calendar-row ${isCollapsed ? "collapsed" : ""}`;
    calRow.dataset.id = cal.id;
    calRow.dataset.depth = 0;
    calRow.style.setProperty("--depth", "0");

    const toggleHtml = hasCrons
      ? `<span class="ordo-toggle"></span>`
      : `<span class="ordo-toggle empty"></span>`;

    calRow.innerHTML = `
      <td>${toggleHtml}<i class="fas fa-folder mr-2 has-text-info"></i>${cal.name || "—"}</td>
      <td>${cal.tz || "—"}</td>
      <td>${cal.description || "—"}</td>
      <td>${cal.crons?.length || 0}</td>
      <td>${cal.cluster_ids?.length || 0}</td>
      <td>—</td>
      <td>—</td>
      <td>—</td>
      <td>${generateCalendarActions(cal.id, hasCrons)}</td>
    `;

    tbody.appendChild(calRow);

    if (hasCrons) {
      (cal.crons || []).forEach((cron, idx) => {
        const isLast = idx === cal.crons.length - 1;
        const cronRow = document.createElement("tr");
        cronRow.className = `ordo-cron-row ${isCollapsed ? "hidden" : ""}`;
        cronRow.dataset.id = `cron-${cal.id}-${cron.id}`;
        cronRow.dataset.depth = 1;
        cronRow.dataset.parent = cal.id;
        cronRow.dataset.lastChild = isLast ? "true" : "false";
        cronRow.style.setProperty("--depth", "1");

        const cronIcon = '<i class="fas fa-clock mr-2 has-text-cyan"></i>';

        cronRow.innerHTML = `
          <td>${cronIcon}${cron.name || "—"}</td>
          <td>${cron.english || "—"}</td>
          <td>${cron.description || "—"}</td>
          <td>—</td>
          <td>—</td>
          <td>${cron.begin ? formatDate(cron.begin) : "Immediate"}</td>
          <td>${cron.expire ? formatDate(cron.expire) : "Never"}</td>
          <td>${formatDate(cron.next_start) || "—"}</td>
          <td>${generateCronActions(cal.id, cron.id)}</td>
        `;

        tbody.appendChild(cronRow);
      });
    }
  });
}

// Helper: calendar dropdown actions
function generateCalendarActions(calId, hasCrons) {
  return `
    <div class="dropdown is-right">
      <div class="dropdown-trigger">
        <button class="btn btn-sm btn-ghost" aria-haspopup="menu">
          <i class="fas fa-ellipsis-v"></i>
        </button>
      </div>
      <div class="dropdown-menu" role="menu">
        <div class="dropdown-content">
          <a href="#" class="dropdown-item" data-action="edit-calendar" data-id="${calId}">Edit</a>
          <a href="#" class="dropdown-item" data-action="add-cron" data-cal-id="${calId}">Add Cron</a>
          <hr class="dropdown-divider">
          <a href="#" class="dropdown-item is-danger" data-action="delete-calendar" data-id="${calId}">Delete</a>
        </div>
      </div>
    </div>
  `;
}

// Helper: cron dropdown actions
function generateCronActions(calId, cronId) {
  return `
    <div class="dropdown is-right">
      <div class="dropdown-trigger">
        <button class="btn btn-sm btn-ghost" aria-haspopup="menu">
          <i class="fas fa-ellipsis-v"></i>
        </button>
      </div>
      <div class="dropdown-menu" role="menu">
        <div class="dropdown-content">
          <a href="#" class="dropdown-item" data-action="edit-cron" data-cal-id="${calId}" data-cron-id="${cronId}">Edit</a>
          <hr class="dropdown-divider">
          <a href="#" class="dropdown-item is-danger" data-action="delete-cron" data-cron-id="${cronId}">Delete</a>
        </div>
      </div>
    </div>
  `;
}

export function updateServers(data) {
  hideLoading("servers-loading");
  const content = document.getElementById("servers-content");
  if (content) content.style.display = "block";

  // Handle both success cases
  if (data.success && Array.isArray(data.servers)) {
    appState.serversData = data.servers;
  } else {
    appState.serversData = [];  // empty = no crash
    console.log("No servers found:", data.message || "empty response");
  }

  renderServersTable();  // your render must handle empty array gracefully
}

export function applyServerBroadcast(data) {
  // Ensure the array exists
  if (!appState.serversData) {
    appState.serversData = [];
  }

  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);

      const idx = appState.serversData.findIndex((s) => Number(s.id) === id);

      if (idx !== -1) {
        // Update existing
        appState.serversData[idx] = { ...appState.serversData[idx], ...update };
      } else {
        // Add new
        appState.serversData.push(update);
      }
    });
  }

  if (data.deletes) {
    const deleteIds = data.deletes.map((d) => Number(d.id || d));
    appState.serversData = appState.serversData.filter(
      (s) => !deleteIds.includes(Number(s.id)),
    );
  }

  renderServersTable(); // ← your server render function
}

export function applyClusterBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);
      const isCluster = true; // this broadcast is always for clusters

      // 1. Update the in-memory tree (this is the key fix)
      const clusterInTree = findClusterById(appState.monitorData.tree, id);
      if (clusterInTree) {
        Object.assign(clusterInTree, update); // update next_start + everything else
      }

      // 2. Update the DOM row
      const rowId = `row-cluster-${id}`;
      const existingRow = document.getElementById(rowId);
      if (existingRow) {
        updateRow(existingRow, { ...update, is_cluster: true });
      } else {
        const parentId = update.parent_id || null;
        insertRow({ ...update, is_cluster: true }, parentId);
      }

      // 3. Handle jobs inside this cluster (if any)
      if (update.jobs && Array.isArray(update.jobs)) {
        update.jobs.forEach((jobUpdate) => {
          const jobId = Number(jobUpdate.id);

          // Update job in tree
          const jobInTree = findJobById(appState.monitorData.tree, jobId);
          if (jobInTree) {
            Object.assign(jobInTree, jobUpdate);
          }

          // Update job DOM row
          const jobRowId = `row-job-${jobId}`;
          const jobRow = document.getElementById(jobRowId);
          if (jobRow) {
            updateRow(jobRow, { ...jobUpdate, is_cluster: false });
          } else {
            insertRow({ ...jobUpdate, is_cluster: false }, id);
          }
        });
      }
    });
  }

  if (data.deletes) {
    const uniqueDeletes = [
      ...new Set(data.deletes.map((d) => Number(d.id || d))),
    ];
    uniqueDeletes.forEach((id) => {
      removeClusterById(appState.monitorData.tree, id);
      const row = document.getElementById(`row-cluster-${id}`);
      if (row) row.remove();
    });
  }

  // Refresh live timings (now sees fresh data)
  updateLiveTimings();
}

// ==================== DASHBOARD CORE ====================
export function renderDashboard() {
  const tree = appState.monitorData?.tree || [];
  const servers = appState.serversData || [];

  console.log('[Dashboard] Rendering from current state');

  // Longest Running
  document.getElementById('dash-running-list').innerHTML = getLongestRunningJobsHTML(tree, 5);
  document.getElementById('dash-running-count').textContent = countRunningJobs(tree);

  // Recently Failed
  document.getElementById('dash-failed-list').innerHTML = getRecentlyFailedListHTML(tree, 5);
  document.getElementById('dash-failed-count').textContent = countRecentFailedJobs(tree);

  // Next Scheduled
  updateNextScheduledClusters();
  updateNextScheduledCount();

  // Overdue
  document.getElementById('dash-overdue-count').textContent = countOverdueClusters(tree);
  document.getElementById('dash-overdue-list').innerHTML = getOverdueClustersListHTML(tree);

  // Recent Activity
  renderRecentActivityTable(tree);

  console.log(`[Dashboard] Counts → Running: ${countRunningJobs(tree)}, Failed: ${countRecentFailedJobs(tree)}`);
}

export function updateDashboardLiveCards() {
  const tree = appState.monitorData?.tree || [];
  const now = Math.floor(Date.now() / 1000);

  // Longest Running
  const runningList = document.getElementById('dash-running-list');
  if (runningList) runningList.innerHTML = getLongestRunningJobsHTML(tree, 5);

  // Recently Failed
  const failedList = document.getElementById('dash-failed-list');
  if (failedList) failedList.innerHTML = getRecentlyFailedListHTML(tree, 5);

  // Next Scheduled & Overdue
  updateNextScheduledClusters();
  updateNextScheduledCount();

  // Recent Activity "ago" times
  document.querySelectorAll('#dash-recent-body td[data-timestamp]').forEach(td => {
    const ts = parseInt(td.dataset.timestamp);
    if (ts) td.textContent = formatRelativeTime(now - ts);
  });
}

// ==================== SAFE BROADCAST HANDLER ====================
export function applyJobBroadcast(data) {
  if (!data.updates || !Array.isArray(data.updates)) return;

  console.log(`[ApplyJobBroadcast] Processing ${data.updates.length} updates`);

  data.updates.forEach((update) => {
    const id = Number(update.id);
    if (!id) return;

    if (update.is_cluster || update.is_cluster === true) return;

    const newState = String(update.jobstate || '').toLowerCase().trim();
    const newStarted = update.started || update.start;

    let jobInTree = findJobById(appState.monitorData.tree, id);

    if (jobInTree) {
      // === NORMAL UPDATE PATH ===
      if (newStarted !== undefined && newStarted !== null) {
        const old = Number(jobInTree.started || 0);
        const fresh = Number(newStarted);
        if (fresh > old) {
          console.log(`[ApplyJobBroadcast] 🔄 Job ${update.name} (id=${id}) started refreshed ${old} → ${fresh}`);
          jobInTree.started = fresh;
        }
      }

      if (["complete", "failed", "killed", "zombie"].includes(newState)) {
        console.log(`[ApplyJobBroadcast] Job ${update.name} (id=${id}) → ${newState} (clearing started)`);
        jobInTree.started = null;
      }

      Object.assign(jobInTree, update);
      console.log(`[ApplyJobBroadcast] Updated existing job ${update.name} (id=${id})`);
    } 
    else {
      // === SUSPICIOUS CASE ===
      console.warn(`🚨 [ApplyJobBroadcast] Job ${update.name} (id=${id}) not found in tree! This should not happen on updates.`);

      const parentId = Number(update.cluster_id || update.parent_id);
      if (parentId) {
        console.log(`[ApplyJobBroadcast] Falling back to insert for job ${update.name} (id=${id})`);
        insertRow({ ...update, is_cluster: false }, parentId);
      } else {
        console.error(`[ApplyJobBroadcast] Cannot insert job ${update.name} (id=${id}) - no parent cluster found`);
      }
    }

    // Update main table row
    const row = document.getElementById(`row-job-${id}`);
    if (row) updateRow(row, { ...update, is_cluster: false });
  });

  updateLiveTimings();

  if (document.getElementById('dashboard')?.classList.contains('active')) {
    renderDashboard();
  }
}

export function applyCalBroadcast(data) {
  if (!data.updates && !data.deletes) {
    console.warn('[applyCalBroadcast] Received empty payload');
    return;
  }

  console.log(`[applyCalBroadcast] Processing ${data.updates?.length || 0} updates, ${data.deletes?.length || 0} deletes`);

  // Handle updates
  if (data.updates && Array.isArray(data.updates)) {
    data.updates.forEach((cal) => {
      const calId = Number(cal.id);
      if (!calId) return;

      const existingCal = findCalendarById(appState.calendarsData, calId);

      if (existingCal) {
        console.log(`[applyCalBroadcast] Updating calendar "${cal.name || 'unknown'}" (id=${calId})`);
        Object.assign(existingCal, cal);
      } else {
        console.log(`[applyCalBroadcast] Inserting new calendar "${cal.name || 'unknown'}" (id=${calId})`);
        appState.calendarsData.push(cal);
      }
    });
  }

  // Handle deletes
  if (data.deletes && Array.isArray(data.deletes)) {
    data.deletes.forEach((del) => {
      const calId = Number(del.id || del);
      if (!calId) return;

      console.log(`[applyCalBroadcast] Deleting calendar id=${calId}`);

      // Remove from appState
      appState.calendarsData = appState.calendarsData.filter(c => Number(c.id) !== calId);

      // Remove from DOM if rendered
      const row = document.getElementById(`row-cal-${calId}`);
      if (row) row.remove();
    });
  }

  // Refresh calendars UI if the tab is active
  if (document.getElementById('calendars')?.classList.contains('active')) {
    renderCalendarsTable();
  }

  console.log(`[applyCalBroadcast] Finished. Total calendars in memory: ${appState.calendarsData.length}`);
}

function findCalendarById(calendars, calId) {
  return calendars.find(c => Number(c.id) === Number(calId));
}

export function loadDoc(file) {
  const content = document.getElementById("docs-content");
  content.innerHTML =
    '<p class="has-text-centered"><i class="fas fa-spinner fa-spin"></i> Loading...</p>';
  fetch(`/docs/${file}`)
    .then((response) => {
      if (!response.ok) throw new Error(`Failed to load ${file}`);
      return response.text();
    })
    .then((md) => {
      const html = marked.parse(md);
      document.getElementById("docs-content").innerHTML = html;

      // Safe highlight — hljs should now be defined
      if (typeof hljs !== "undefined") {
        hljs.highlightAll();
      } else {
        console.warn(
          "highlight.js failed to load — code blocks will not be highlighted",
        );
      }

      // Update active TOC link
      document
        .querySelectorAll("#docs-toc a")
        .forEach((a) => a.classList.remove("active"));
      const activeLink = document.querySelector(
        `#docs-toc a[data-file="${file}"]`,
      );
      if (activeLink) activeLink.classList.add("active");
    })
    .catch((err) => {
      document.getElementById("docs-content").innerHTML =
        `<p class="has-text-danger has-text-centered">Error: ${err.message}</p>`;
    });
}

document.getElementById("refresh-usage")?.addEventListener("click", () => {
  appState.ws.send(JSON.stringify({ command: "read_org" }));
  showToast("Refreshing usage...", "info");
});

// Internal tabs in Settings
document.addEventListener('click', (e) => {
  const tabBtn = e.target.closest('.internal-tab');
  if (!tabBtn) return;

  const tabId = tabBtn.dataset.tab;
  const container = tabBtn.closest('#settings-content');
  if (!container) return;

  // Remove active from all buttons and contents
  container.querySelectorAll('.internal-tab').forEach(b => b.classList.remove('active'));
  container.querySelectorAll('.internal-tab-content').forEach(c => c.style.display = 'none');

  // Activate clicked
  tabBtn.classList.add('active');
  const content = container.querySelector(`#tab-${tabId}`);
  if (content) content.style.display = 'block';
});

// Mobile TOC toggle
document.getElementById("docs-toc-toggle")?.addEventListener("click", () => {
  document.getElementById("docs-toc").classList.toggle("is-open");
});

// TOC click handler
// Inside your TOC click handler
document.getElementById("docs-toc").addEventListener("click", (e) => {
  const link = e.target.closest("a");
  if (link && link.dataset.file) {
    e.preventDefault();
    loadDoc(link.dataset.file);

    const contentContainer = document.querySelector(".docs-content-container");
    if (contentContainer) {
      contentContainer.focus();
      contentContainer.scrollTop = 0; // Optional: scroll to top on new page
    }
  }
});

export function attachCalendarsTreeListeners() {
  const tbody = document.getElementById("calendars-body");
  if (!tbody) return;

  tbody.addEventListener("click", (e) => {
    const toggle = e.target.closest(".ordo-toggle");
    if (!toggle || toggle.classList.contains("empty")) return;


    const row = toggle.closest("tr");
    if (!row || !row.dataset.id) return;

    const calId = String(row.dataset.id);

    // Toggle collapsed state (same logic as main tree)
    const isNowCollapsed = !appState.collapsedCalendars.has(calId);

    if (isNowCollapsed) {
      appState.collapsedCalendars.add(calId);
    } else {
      appState.collapsedCalendars.delete(calId);
    }

    // Re-render the whole table (simplest and most reliable)
    renderCalendarsTable();

    // Save to localStorage
    if (typeof updateCalendarCollapsed === "function") {
      updateCalendarCollapsed();
    }
  });
}

// ==================== LOGIN MODAL ====================

export function showLoginModal(redirectContext = '') {
  const modal = document.getElementById('login-modal');
  if (!modal) return;

  modal.dataset.redirectContext = redirectContext;

  document.getElementById('login-form-container').style.display = 'block';
  document.getElementById('login-success').style.display = 'none';
  document.getElementById('login-email').value = '';

  modal.classList.add('active');
  document.getElementById('login-email').focus();
}

function initLoginModalListeners() {
  const modal = document.getElementById('login-modal');
  if (!modal) return;

  // Close button
  modal.querySelector('.close-btn')?.addEventListener('click', () => {
    modal.classList.remove('active');
  });

  // Form submit
  const form = document.getElementById('login-form');
  if (form) {
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const email = document.getElementById('login-email').value.trim();
      if (!email) return;

      const btn = document.getElementById('send-magic-link-btn');
      btn.disabled = true;
      btn.textContent = 'Sending...';

      try {
        await fetch('/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ email: email })
        });

        document.getElementById('login-form-container').style.display = 'none';
        document.getElementById('login-success').style.display = 'block';
      } catch (err) {
        showToast('Failed to send magic link', 'danger');
      } finally {
        btn.disabled = false;
        btn.textContent = 'Send Magic Link';
      }
    });
  }
}

// ==================== PRICING MODAL ====================
export function showPricingModal() {
  const modal = document.getElementById('pricing-modal');
  if (!modal) return;

  const isLoggedIn = document.body.classList.contains('is-logged-in');

  // Highlight current plan only if logged in
  if (isLoggedIn && appState.orgData?.tier) {
    const currentTier = appState.orgData.tier.toLowerCase();
    document.querySelectorAll('#pricing-modal .card-simple').forEach(card => {
      card.style.borderColor = '';
      card.style.boxShadow = '';
      if (card.id === `plan-${currentTier}`) {
        card.style.borderColor = 'var(--glow-cyan)';
        card.style.boxShadow = '0 0 25px rgba(0, 255, 255, 0.4)';
      }
    });
  }

  modal.classList.add('active');
}

function initPricingModalListeners() {
  const modal = document.getElementById('pricing-modal');
  if (!modal) return;

  modal.addEventListener('click', (e) => {
    const upgradeBtn = e.target.closest('button[data-plan]');
    if (upgradeBtn) {
      const plan = upgradeBtn.dataset.plan;
      modal.classList.remove('active');

      const isLoggedIn = document.body.classList.contains('is-logged-in');

      if (!isLoggedIn) {
        showLoginModal('pricing');   // Ask to log in first
      } else {
        sendWS({ command: 'create_checkout_session', plan: plan });
        showToast(`Redirecting to ${plan} checkout...`, 'info');
      }
      return;
    }

    if (e.target.id === 'contact-sales-btn') {
      modal.classList.remove('active');
      window.location.href = "mailto:ordoscheduler@proton.me?subject=Enterprise%20Inquiry";
    }

    if (e.target.classList.contains('close-btn')) {
      modal.classList.remove('active');
    }
  });
}

function debugDumpTreeContext() {
  const tree = appState.monitorData?.tree || [];
  console.groupCollapsed(`[Tree Debug] ${new Date().toLocaleTimeString()} - ${tree.length} top-level items`);

  let runningCount = 0;
  let staleRunning = [];

  traverseTree(tree, (item) => {
    if (item.is_cluster) return;
    if ((item.jobstate || '').toLowerCase() === 'running') {
      runningCount++;
      const age = item.started 
        ? Math.floor(Date.now()/1000) - Number(item.started) 
        : 0;
      if (age > 30) {  // suspiciously old
        staleRunning.push({
          id: item.id,
          name: item.name,
          started: item.started,
          ageSeconds: age,
          state: item.jobstate
        });
      }
    }
  });

  console.log(`Running jobs found: ${runningCount}`);
  if (staleRunning.length > 0) {
    console.warn(`⚠️  Suspiciously old running jobs:`, staleRunning);
  } else {
    console.log("✅ No suspiciously stale running jobs");
  }

  console.groupEnd();
}

// ==================== DASHBOARD ====================

// KPI Bar Updater
export function updateKPIBar(stats = {}) {
  console.log('[updateKPIBar] Updating with:', stats);

  const successEl = document.getElementById('kpi-success-rate');
  if (successEl) {
    let rate = 100;
    if (typeof stats.success_rate === 'number') rate = stats.success_rate;
    else if (stats.runs_today > 0) {
      const failed = stats.failed_runs_today || 0;
      rate = Math.round(100 * (stats.runs_today - failed) / stats.runs_today);
    }
    successEl.textContent = rate + '%';
  }

  const runsEl = document.getElementById('kpi-runs-today');
  if (runsEl) runsEl.textContent = stats.runs_today || 0;

  const failedEl = document.getElementById('kpi-failed-today');
  if (failedEl) failedEl.textContent = stats.failed_runs_today || 0;
}

// Broadcast-driven updates
export function updateDashboardFromBroadcast(data) {
  if (!data) return;

  // Handle find_stats reply
  if (data.command_reply === 'find_stats') {
    console.log('[find_stats] Reply received:', data);
    appState.dashboardStats = data;
    if (document.getElementById('dashboard')?.classList.contains('active')) {
      updateKPIBar(data);
    }
    return;
  }

  // Handle jobs_changed incremental counter (only once)
  if (data.broadcast === "jobs_changed" && data.updates?.length) {
    updateDashboardCountersFromBroadcast(data.updates);
  }

  // Light UI refresh if dashboard is visible
  if (document.getElementById('dashboard')?.classList.contains('active')) {
    renderDashboard();
  }
}

// Global deduplication tracker (outside any function)
let lastProcessedJobUpdate = new Map();   // job_id → timestamp

export function updateDashboardCountersFromBroadcast(updates = []) {
  if (!appState.dashboardStats || !Array.isArray(updates) || updates.length === 0) {
    return;
  }

  let newRuns = 0;
  let newFailed = 0;
  const now = Date.now();

  updates.forEach(item => {
    if (!item || item.is_cluster || !item.jobstate || typeof item.jobstate !== 'string') {
      return;
    }

    const jobId = Number(item.id);
    if (!jobId) return;

    // === DEDUPLICATION: Ignore same job update within 800ms ===
    const lastTime = lastProcessedJobUpdate.get(jobId) || 0;
    if (now - lastTime < 800) {
      console.log(`[Counter] Ignored duplicate update for job ${jobId}`);
      return;
    }
    lastProcessedJobUpdate.set(jobId, now);

    const state = item.jobstate.toLowerCase().trim();

    if (state === 'complete' || state === 'completed') {
      newRuns++;
    } else if (state === 'failed' || state === 'killed' || state === 'zombie') {
      newRuns++;
      newFailed++;
    }
  });

  if (newRuns > 0 || newFailed > 0) {
    appState.dashboardStats.runs_today = (appState.dashboardStats.runs_today || 0) + newRuns;
    appState.dashboardStats.failed_runs_today = (appState.dashboardStats.failed_runs_today || 0) + newFailed;

    console.log(`[Counter] +${newRuns} runs, +${newFailed} failed → Total runs: ${appState.dashboardStats.runs_today}`);

    if (document.getElementById('dashboard')?.classList.contains('active')) {
      updateKPIBar(appState.dashboardStats);
    }
  }
}


export function getNextScheduledListHTML(tree) {
  console.log('[NextScheduled] Scanning for upcoming clusters...');

  const upcoming = collectNextScheduledClusters(tree);

  console.log(`[NextScheduled] Found ${upcoming.length} upcoming clusters`);

  if (upcoming.length === 0) {
    return `<div class="empty-state">No upcoming scheduled clusters</div>`;
  }

  return upcoming.map(cluster => {
    const tminus = formatTminus(cluster.next_start) || '—';

    return `
      <div class="mini-item">
        <div class="mini-item-name">${cluster.name}</div>
        <div class="mini-item-time">${tminus}</div>
      </div>
    `;
  }).join('');
}

// Initial stats load - called once after login or when dashboard tab is first activated
export function loadDashboardStats() {
  const since = getStartOfTodayUnix();
  
  console.log(`[find_stats] Requesting initial stats (since: ${since})`);

  sendWS({
    command: "find_stats",
    since: since
  });
}

// Resync Button
export function initResyncButton() {
  const btn = document.getElementById('resync-all-btn');
  if (!btn) return;

  btn.addEventListener('click', () => {
    if (btn.disabled) return;
    const originalHTML = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Resyncing...';

    sendWS({ command: 'sync' });
    sendWS({ command: 'find_stats', since: getStartOfTodayUnix() });
    sendWS({ command: 'find_cluster', name: 'root' });

    setTimeout(() => {
      if (btn.disabled) {
        btn.disabled = false;
        btn.innerHTML = originalHTML;
      }
    }, 15000);
  });
}

function getStartOfTodayUnix() {
  const now = new Date();
  const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.floor(startOfDay.getTime() / 1000);
}


export function getRecentlyFailedListHTML(tree, max = 5) {
  //console.log('[FailedJobs] === SCAN START ===');

  const jobMap = new Map();   // jobId → most recent failure

  traverseTree(tree, (item) => {
    if (item.is_cluster || !item.jobstate) return;

    const state = (item.jobstate || '').toLowerCase().trim();
    if (!['failed', 'killed', 'zombie'].includes(state) || !item.ended) return;

    const jobId = Number(item.id);
    const endedTs = Number(item.ended);
    const agoSeconds = Math.floor(Date.now() / 1000) - endedTs;
    const agoDisplay = formatRelativeTime(agoSeconds) || 'just now';

    const existing = jobMap.get(jobId);

    // Keep only the most recently failed version for this job ID
    if (!existing || endedTs > Number(existing.ended || 0)) {
      jobMap.set(jobId, {
        ...item,
        agoSeconds: agoSeconds,
        agoDisplay: agoDisplay
      });
    }

    //console.log(`[FailedJobs] Found "${item.name}" (id=${jobId}) | ended=${item.ended} | ${agoDisplay}`);
  });

  const failedJobs = Array.from(jobMap.values());
  
  // Sort by most recent failure first
  failedJobs.sort((a, b) => a.agoSeconds - b.agoSeconds);

  //console.log(`[FailedJobs] Final unique list: ${failedJobs.length} jobs`);

  if (failedJobs.length === 0) {
    return `<div class="empty-state">No recent failures</div>`;
  }

  return failedJobs.slice(0, max).map(job => `
    <div class="mini-item">
      <div class="mini-item-name">${job.name || 'Unnamed Job'}</div>
      <div class="mini-item-time">${job.agoDisplay}</div>
    </div>
  `).join('');
}

export function getLongestRunningJobsHTML(tree, max = 5) {
  console.log('[LongestRunning] === SCAN START ===');

  const jobMap = new Map();
  const now = Math.floor(Date.now() / 1000);

  traverseTree(tree, (item) => {
    if (item.is_cluster || !item.jobstate) return;

    const state = String(item.jobstate).toLowerCase().trim();
    if (state !== 'running') return;

    const jobId = Number(item.id);
    if (!jobId) return;

    let startedTs = Number(item.started || 0);
    if (startedTs < 1000000000) return;

    // Ignore jobs that appear to have started before the page load (stale)
    if (startedTs < (now - 3600)) {   // older than 1 hour
      console.log(`[LongestRunning] Ignoring stale job ${item.name} (id=${jobId}) started=${startedTs}`);
      return;
    }

    const runtimeSeconds = now - startedTs;
    const runtimeDisplay = formatTplus(startedTs) || '—';

    const existing = jobMap.get(jobId);

    console.log(`[LongestRunning] Job "${item.name}" (id=${jobId}) | started=${startedTs} | runtime=${runtimeSeconds}s`);

    if (!existing || startedTs > Number(existing.started || 0)) {
      jobMap.set(jobId, {
        name: item.name || 'Unnamed',
        started: startedTs,
        runtimeSeconds,
        runtimeDisplay
      });
      console.log(`[LongestRunning] → KEPT NEWER (started=${startedTs})`);
    } else {
      console.log(`[LongestRunning] → IGNORED older (started=${startedTs})`);
    }
  });

  const runningJobs = Array.from(jobMap.values())
    .sort((a, b) => b.runtimeSeconds - a.runtimeSeconds);

  console.log(`[LongestRunning] FINAL unique list: ${runningJobs.length} jobs`);

  if (runningJobs.length === 0) {
    return `<div class="empty-state">No jobs currently running</div>`;
  }

  return runningJobs.slice(0, max).map(job => `
    <div class="mini-item">
      <div class="mini-item-name">${job.name}</div>
      <div class="mini-item-time">${job.runtimeDisplay}</div>
    </div>
  `).join('');
}

function getOverdueClustersListHTML(tree) {
  const now = Math.floor(Date.now() / 1000);
  let html = '';
  let count = 0;

  traverseTree(tree, item => {
    if (item.is_cluster && item.next_start && item.next_start < now && item.jobstate !== 'running') {
      const overdueBy = formatRelativeTime(now - item.next_start);
      html += `
        <div class="flex justify-between items-center py-1 border-b border-dark last:border-none">
          <span class="truncate">${item.name}</span>
          <span class="text-orange text-xs">overdue ${overdueBy}</span>
        </div>`;
      count++;
    }
  });

  return count === 0 
    ? '<div class="text-grey text-sm py-8 text-center">No overdue clusters ✓</div>' 
    : html;
}

function countOverdueClusters(tree) {
  let count = 0;
  const now = Math.floor(Date.now() / 1000);
  traverseTree(tree, item => {
    if (item.is_cluster && 
        item.next_start && 
        item.next_start < now && 
        item.jobstate !== 'running') {
      count++;
    }
  });
  return count;
}

function updateNextScheduledCount() {
  const nextClusters = collectNextScheduledClusters(appState.monitorData?.tree || []);
  const countEl = document.getElementById('dash-next-count');
  if (countEl) {
    countEl.textContent = nextClusters.length;
  }
}

export function updateNextScheduledClusters() {
  const container = document.getElementById('dash-next-5');
  if (!container) return;

  const upcoming = collectNextScheduledClusters(appState.monitorData?.tree || [], 6);

  if (upcoming.length === 0) {
    container.innerHTML = `<div class="text-grey text-sm py-8 text-center">No upcoming scheduled clusters</div>`;
    return;
  }

  container.innerHTML = upcoming.map(item => `
    <div class="flex justify-between items-center text-sm py-1">
      <span class="text-cyan font-medium">${formatTminus(item.next_start)}</span>
      <span class="truncate">${item.name}</span>
    </div>
  `).join('');
}

export function getRunningJobsListHTML(tree, max = 8) {
  let html = '';
  let shown = 0;

  traverseTree(tree, item => {
    if ((item.jobstate === 'running' || item.state === 'running') && shown < max) {
      const duration = item.started ? formatTplus(item.started) : 'just started';
      html += `
        <div class="flex justify-between items-center py-1">
          <span class="truncate">${item.name || 'Unnamed'}</span>
          <span class="text-xs">${duration}</span>
        </div>`;
      shown++;
    }
  });

  if (shown === 0) {
    html = '<div class="text-grey text-sm py-6 text-center">No jobs currently running</div>';
  }

  return html;
}

// ==================== RECENT ACTIVITY ====================

export function renderRecentActivityTable(tree) {
  const tbody = document.getElementById('dash-recent-body');
  if (!tbody) return;

  tbody.innerHTML = '';

  const activities = collectRecentActivity(tree, 12);

  if (activities.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="4" class="text-center text-grey py-12">
          No recent activity
        </td>
      </tr>`;
    return;
  }

  activities.forEach(item => {
    const row = document.createElement('tr');
    const stateClassName = (item.jobstate || 'unknown').toLowerCase();

    row.innerHTML = `
      <td data-timestamp="${item.timestamp}">
        ${item.timeAgo}
      </td>
      <td class="font-medium">${item.name || 'Unnamed'}</td>
      <td>
        <span class="state-badge ${stateClassName}">
          ${item.action}
        </span>
      </td>
      <td class="text-grey">${item.server || '—'}</td>
    `;

    tbody.appendChild(row);
  });
}

// ==================== HELPER ====================

function collectRecentActivity(tree, max = 12) {
  const activities = [];
  const now = Math.floor(Date.now() / 1000);

  traverseTree(tree, item => {
    // === SKIP ROOT CLUSTER ===
    if (!item || 
        item.name === 'root' || 
        item.parent_id === null && item.name?.toLowerCase() === 'root') {
      return;
    }

    const timestamp = item.ended || item.last_update || item.started || item.creation_time || 0;
    if (!timestamp) return;

    let action = '—';
    const js = (item.jobstate || '').toLowerCase();

    if (js === 'failed' || js === 'killed') action = 'Failed';
    else if (js === 'complete' || js === 'completed') action = 'Completed';
    else if (js === 'running' || js === 'starting') action = 'Started';
    else if (js === 'hold') action = 'Held';
    else if (js === 'ice') action = 'Iced';

    activities.push({
      name: item.name || 'Unnamed',
      action: action,
      server: item.server_name || item.server || '—',
      timestamp: timestamp,
      timeAgo: formatRelativeTime(now - timestamp),
      jobstate: item.jobstate || 'unknown'
    });
  });

  // Most recent first
  activities.sort((a, b) => b.timestamp - a.timestamp);
  return activities.slice(0, max);
}

// ==================== CLICK HANDLER ====================
window.viewDashboardItem = (id, isCluster) => {
  if (isCluster) {
    // Open Dependency Graph
    document.getElementById('graph-title').textContent = `Cluster #${id}`;
    document.getElementById('graph-modal').classList.add('active');
    // You can expand this later to send a graph command
  } else {
    // Open latest log for job
    sendWS({ command: 'read_log', id });
  }
};

function countRunningJobs(tree) {
  let count = 0;
  traverseTree(tree, item => {
    if (item.jobstate === 'running' || item.state === 'running') count++;
  });
  return count;
}

function countRecentFailedJobs(tree) {
  let count = 0;
  traverseTree(tree, item => {
    if (item.jobstate === 'failed' || item.state === 'failed') count++;
  });
  return Math.min(count, 5); // cap for display
}


function calculate24hStats(tree) {
  const now = Math.floor(Date.now() / 1000);
  const dayAgo = now - 86400;
  let success = 0, failed = 0, runsToday = 0, held = 0, zombies = 0;

  traverseTree(tree, item => {
    if (item.ended && item.ended > dayAgo) {
      runsToday++;
      if (item.jobstate === 'complete' || item.exit_code === 0) success++;
      else if (item.jobstate === 'failed' || item.exit_code !== 0) failed++;
    }
    if (item.jobstate === 'hold') held++;
    if (item.zombie_processes) zombies += item.zombie_processes;
  });

  const total = success + failed;
  const successRate = total ? Math.round((success / total) * 100) : 100;

  return { successRate, runsToday, held, zombies };
}

function collectNextScheduledClusters(tree, limit = 6) {
  let list = [];
  traverseTree(tree, item => {
    if (item.is_cluster && item.cal_name && item.next_start && item.next_start > Date.now()/1000) {
      list.push(item);
    }
  });
  list.sort((a, b) => (a.next_start || 0) - (b.next_start || 0));
  return list.slice(0, limit);
}

function getActivityAction(item) {
  const s = (item.jobstate || item.state || '').toLowerCase();
  if (s.includes('fail') || s === 'killed') return { text: 'Failed', class: 'failed' };
  if (s === 'complete' || s === 'completed') return { text: 'Completed', class: 'complete' };
  if (s === 'running') return { text: 'Started', class: 'running' };
  if (s === 'starting') return { text: 'Starting', class: 'starting' };
  if (s === 'hold') return { text: 'Held', class: 'hold' };
  if (s === 'ice') return { text: 'Iced', class: 'ice' };
  return { text: s ? s.charAt(0).toUpperCase() + s.slice(1) : 'Updated', class: 'unknown' };
}

function renderMiniServersList(servers) {
  const container = document.getElementById('dash-servers-list');
  if (!container) return;
  if (servers.length === 0) {
    container.innerHTML = `<div class="text-grey">No servers connected</div>`;
    return;
  }
  container.innerHTML = servers.slice(0, 3).map(s => `
    <div class="flex justify-between text-sm">
      <span>${s.name}</span>
      <span class="text-cyan">${s.load_1?.toFixed(2) || '—'}</span>
    </div>
  `).join('');
}

// ==================== DEDICATED DASHBOARD TIMER ====================
let dashboardLiveInterval = null;

export function startDashboardLiveTimer() {
  if (dashboardLiveInterval) return;

  dashboardLiveInterval = setInterval(() => {
    if (document.getElementById('dashboard')?.classList.contains('active')) {
      updateDashboardLiveCards();
    }
  }, 1000);
}

export function stopDashboardLiveTimer() {
  if (dashboardLiveInterval) {
    clearInterval(dashboardLiveInterval);
    dashboardLiveInterval = null;
  }
}

// ==================== INITIALIZE ALL ====================

export function initModals() {
  initSettingsListeners();
  initLoginModalListeners();
  initPricingModalListeners();
  initResyncButton();

  // Logged-out "Log in" tab
  document.getElementById('logged-out-login-tab')?.addEventListener('click', (e) => {
    e.preventDefault();
    showLoginModal('');
  });
}

export function initSettingsListeners() {
  document.getElementById('refresh-settings')?.addEventListener('click', refreshSettings);
  document.getElementById('save-account')?.addEventListener('click', saveAccount);
  document.getElementById('copy-token')?.addEventListener('click', copyToken);
  document.getElementById('view-plans-btn')?.addEventListener('click', showPricingModal);
  document.getElementById('footer-pricing-link')?.addEventListener('click', (e) => {
    e.preventDefault();
    showPricingModal();
  });
}
