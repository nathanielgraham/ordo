// ==================== DEBUG GUARD - MUST BE LINE 1-15 ====================
console.log("[ui-handlers] >>> FILE START EXECUTING <<<");

if (window.__uiHandlersLoaded) {
  console.log("[ui-handlers] ⚠️ Duplicate load blocked");
} else {
  window.__uiHandlersLoaded = true;
  console.log("[ui-handlers] ✅ FIRST AND ONLY INITIALIZATION");
}
// =====================================================================

import { openConfirmModal } from "./modals.js";
import { sendWS, checkLoginAndConnect } from "./websocket.js";
import {
  appState,
  updateCollapsedClusters,
  updateCalendarCollapsed,
} from "./state.js";
import { renderJobsTable } from "./tree/tree-table.js";
import { openCronsModal } from "./modals.js";
import {
  //updateRow,
  //insertRow,
  insertJob,
  insertCluster,
  updateJobRow,
  updateClusterRow,
  removeJobRow,
  removeClusterRow,
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
  populateMapsFromClusters,
  buildTreeFromMaps,
  removeClusterById,
} from "./utils.js";

// HELPERS

// Helper to keep state and tree in sync
function syncItemToState(item, isCluster) {
  const id = Number(item.id);
  if (!id) return null;

  const map = isCluster ? appState.clustersMap : appState.jobsMap;
  const findFn = isCluster ? findClusterById : findJobById;

  let existing = map.get(id);
  if (existing) {
    Object.assign(existing, item);
  } else {
    existing = { ...item, is_cluster: isCluster };
    map.set(id, existing);
  }

  // Sync to main tree
  const treeItem = findFn(appState.monitorData.tree, id);
  if (treeItem) {
    Object.assign(treeItem, item);
  }

  return existing;
}

export function initModalTomSelect(selectId, config = {}) {
  const el = document.getElementById(selectId);
  if (!el) return null;

  // Create once if it doesn't exist
  if (!el.tomselect) {
    const defaults = {
      dropdownParent: "body",
      plugins: ["remove_button"],
      placeholder: "Select...",
      searchField: ["text", "value"],
      zIndex: 4100,
      ...config,
    };

    el.tomselect = new TomSelect(el, defaults);
  }

  const ts = el.tomselect;

  // Update options if provided
  if (config.options && Array.isArray(config.options)) {
    ts.clearOptions();
    ts.addOptions(config.options);
  }

  // Clear selection unless preserveValue is true
  if (!config.preserveValue) {
    ts.clear();
  }

  return ts;
}

// ====================== CENTRAL COMMAND REPLY ROUTER ======================
export function handleCommandReply(data) {
  if (!data || !data.command_reply) return;

  switch (data.command_reply) {
    case "login_user":
      // Login success is handled directly in websocket.js for initial loads
      // We keep it outside for now to preserve existing flow
      break;

    case "read_user":
      updateAccount(data);
      break;

    case "read_org":
      updateOrgAndTeam(data);
      break;

    case "read_log":
      updateLog(data);
      break;

    case "find_log":
      updateLogHistory(data);
      break;

    case "find_cluster":
      updateJobsClusters(data);
      break;

    case "find_cal":
      updateCalendars(data);
      break;

    case "find_monitor":
      updateServers(data);
      break;

    case "find_stats":
      console.log("[find_stats] Reply received:", data);
      appState.dashboardStats = data;
      if (document.getElementById("dashboard")?.classList.contains("active")) {
        updateKPIBar(data);
        renderDashboard();
      }
      break;

    case "sync":
      const btn = document.getElementById("resync-all-btn");
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-sync-alt"></i> Resync Servers';
      }
      if (data.zombie_count !== undefined) {
        const zombiesEl = document.getElementById("kpi-zombies");
        if (zombiesEl) zombiesEl.textContent = data.zombie_count;
      }
      break;

    case "new_token":
      if (data.success && data.token) {
        // Update visible token field
        const tokenField = document.getElementById("account-token");
        if (tokenField) {
          tokenField.value = data.token;
        }

        // Update browser cookie
        document.cookie = `ordo_token=${data.token}; path=/; SameSite=Lax; max-age=${60 * 60 * 24 * 365 * 10}`;

        // Reconnect WebSocket with new token
        // if (appState.ws) {
        //  appState.ws.close();
        // }
        checkLoginAndConnect();

        // setTimeout(() => {
        //  checkLoginAndConnect(); // This will pick up the new cookie
        // }, 300);
      } else {
        showToast(data.message || "Failed to generate new token", "error");
      }
      break;

    case "rotate_execution_token":
      if (data.success && data.execution_token) {
        // Update visible token field
        const tokenField = document.getElementById("execution-token");
        if (tokenField) {
          tokenField.value = data.execution_token;
        }
      } else {
        showToast(data.message || "Failed to rotate exec token", "error");
      }
      break;

    case "delete_me":
      if (data.success) {

        // Clear cookie
        document.cookie =
          "ordo_token=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;";

        // Optional: clear localStorage too
        localStorage.clear();

        // Redirect to home after short delay
        setTimeout(() => {
          window.location.href = "/";
        }, 1800);
      } else {
        showToast(data.message || "Failed to delete account", "danger");
      }
      break;

    default:
      console.debug(
        `[handleCommandReply] Unhandled command_reply: ${data.command_reply}`,
      );
  }
}

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

  let status = "New";
  let statusClass = "is-danger";
  let statusTooltip = "";

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
  console.log("[DEBUG Servers] renderServersTable started");

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

  const now = Math.floor(Date.now() / 1000);

  // Preserve all existing rows (important for open menus)
  const existingRows = new Map();
  document.querySelectorAll("#servers-body tr").forEach((row) => {
    const id = row.dataset.serverId;
    if (id) existingRows.set(id, row);
  });

  // Sort for consistent order
  const sortedServers = [...appState.serversData].sort(
    (a, b) =>
      (a.name || "").localeCompare(b.name || "") || Number(a.id) - Number(b.id),
  );

  // Update or create rows WITHOUT clearing tbody first
  const processedIds = new Set();

  sortedServers.forEach((server) => {
    const serverId = String(server.id);
    processedIds.add(serverId);

    let row = existingRows.get(serverId);

    if (row) {
      console.log(`[DEBUG Servers] Surgical update for ${server.name}`);
      updateServerRow(row, server, now);
      // Re-order if necessary (move to correct position)
      // For simplicity we can leave order as-is for now, or implement move logic
    } else {
      console.log(`[DEBUG Servers] Creating new row for ${server.name}`);
      row = createServerRow(server, now);
      tbody.appendChild(row);
    }
  });

  // Remove deleted servers
  existingRows.forEach((row, id) => {
    if (!processedIds.has(id)) {
      console.log(`[DEBUG Servers] Removing deleted server ${id}`);
      row.remove();
    }
  });

  console.log("[DEBUG Servers] renderServersTable finished");
}

function createServerRow(server, now) {
  const tr = document.createElement("tr");
  tr.dataset.serverId = String(server.id);
  tr.dataset.updateTime = server.update_time || "";

  tr.innerHTML = `
    <td>${escapeHtml(server.name || "—")}</td>
    <td title="${getHostTooltip(server)}">${escapeHtml(server.host || server.ip_address || "—")}</td>
    <td><span class="tag is-danger">Never Connected</span></td>
    <td class="time-text text-grey">—</td>
    <td>—</td>
    <td>—</td>
    <td>—</td>
    <td>—</td>
    <td>—</td>
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

  updateServerRow(tr, server, now);
  return tr;
}

function getLoadTooltip(server) {
  const cores = server.cores != null ? ` (${server.cores} cores)` : "";
  return server.load_1 != null
    ? `1-min: ${server.load_1.toFixed(2)}${cores}\n5-min: ${server.load_5?.toFixed(2) ?? "—"}\n15-min: ${server.load_15?.toFixed(2) ?? "—"}`
    : "Load averages not available";
}

function formatMemory(server) {
  if (!server.total_memory || server.total_memory <= 0) {
    return { mem: "—", tooltip: "Memory data unavailable" };
  }
  const used = server.used_memory || 0;
  const total = server.total_memory;
  const pct = (used / total) * 100;
  const usedGB = (used / 1024 ** 3).toFixed(1);
  const totalGB = (total / 1024 ** 3).toFixed(1);
  const mem = `${pct.toFixed(1)}% (${usedGB}/${totalGB} GB)`;

  const swapPct =
    server.total_swap && server.total_swap > 0
      ? (((server.used_swap || 0) / server.total_swap) * 100).toFixed(1) + "%"
      : "—";

  const tooltip = `RAM: ${pct.toFixed(1)}% (${usedGB}/${totalGB} GB)\nSwap: ${swapPct}`;
  return { mem, tooltip };
}

function formatDisk(server) {
  if (!server.total_disk || server.total_disk <= 0) {
    return { display: "—", tooltip: "Disk data unavailable" };
  }
  const usedGB = (Number(server.used_disk || 0) / 1024 ** 2).toFixed(1);
  const totalGB = (Number(server.total_disk) / 1024 ** 2).toFixed(1);
  const pct = (Number(server.used_disk || 0) / Number(server.total_disk)) * 100;
  const display = `${pct.toFixed(1)}%`;

  let tooltip = `Disk: ${pct.toFixed(1)}% (${usedGB}/${totalGB} GB)`;
  if (server.root_total_disk) {
    const rootPct =
      (Number(server.root_used_disk || 0) / Number(server.root_total_disk)) *
      100;
    tooltip += `\nRoot: ${rootPct.toFixed(1)}%`;
  }
  return { display, tooltip };
}

function getHostTooltip(server) {
  const pingText =
    typeof server.ping === "number" && !isNaN(server.ping)
      ? server.ping.toFixed(3) + "s"
      : "—";
  return [
    `Host: ${server.host || server.ip_address || "—"}`,
    `Port: ${server.port || "—"}`,
    `Ping: ${pingText}`,
    `OS: ${server.os || "—"}`,
    `CWD: ${server.cwd || "—"}`,
    `Home: ${server.home || "—"}`,
  ]
    .filter(Boolean)
    .join("\n");
}

// ==================== TIER LIMITS ====================
const tierLimits = {
  free: { api: 1000, servers: 3, members: 2 },
  starter: { api: 50000, servers: 10, members: 5 },
  pro: { api: 100000, servers: 30, members: 10 },
  custom: { api: Infinity, servers: Infinity, members: Infinity },
};

// ==================== RENDER FUNCTIONS ====================

export function updateAccount(data) {
  if (data.command_reply === "read_user") {
    appState.accountData = data;
    renderUserProfile(data);
  }
}

export function updateOrgAndTeam(data) {
  if (!data || data.command_reply !== "read_org" || !data.success) {
    console.warn(
      "[updateOrgAndTeam] Invalid or failed read_org response",
      data,
    );
    return;
  }

  // Store normalized org data in appState
  appState.orgData = {
    id: data.id,
    name: data.name,
    description: data.description,
    tier: (data.tier || "free").toLowerCase(),
    api_calls_this_month: Number(data.api_calls_this_month || 0),
    monthly_call_limit: Number(data.monthly_call_limit || 1000),
    api_calls_reset_date: Number(data.api_calls_reset_date || 0),
    current_month_year: data.current_month_year,
    server_count: Number(data.server_count || 0),
    server_limit: Number(data.server_limit || 1), // ← new
    member_limit: Number(data.member_limit || 1), // ← new
    members: Array.isArray(data.members) ? data.members : [],
    rate_limit_org_per_minute: Number(data.rate_limit_org_per_minute || 500),
    rate_limit_user_per_minute: Number(data.rate_limit_user_per_minute || 100),
  };

  console.log("[updateOrgAndTeam] Org data updated:", appState.orgData);

  renderBillingAndOrg();
  renderTeamMembers(appState.orgData.members || []);
}

export function updateOrgAndTeam2(data) {
  if (data.command_reply === "read_org") {
    appState.orgData = data;
    renderOrgAndBilling(data);
    renderTeamMembers(data.members || []);
  }
}

function renderUserProfile(user) {
  document.getElementById("account-email").textContent = user.email || "—";
  document.getElementById("account-id").textContent = user.id || "—";
  document.getElementById("account-level").textContent = user.level || "—";
  document.getElementById("account-remote").textContent =
    user.remote_address || "—";

  const nameInput = document.getElementById("edit-name");
  if (nameInput) nameInput.value = user.name || "";

  const tokenInput = document.getElementById("account-token");
  if (tokenInput) tokenInput.value = user.token || "";

  const execTokenInput = document.getElementById("execution-token");
  if (execTokenInput) execTokenInput.value = user.execution_token || "";
}

export function renderBillingAndOrg() {
  const org = appState.orgData;
  if (!org) {
    console.warn("[renderBillingAndOrg] No orgData available");
    return;
  }

  document.getElementById("org-id").textContent = org.id || "—";

  const nameInput = document.getElementById("edit-org-name");
  if (nameInput) nameInput.value = org.name || "";

  const descInput = document.getElementById("edit-org-desc");
  if (descInput) descInput.value = org.description || "";

  // Tier
  const tierEl = document.getElementById("account-tier");
  if (tierEl) tierEl.textContent = org.tier.toUpperCase();

  // API Usage
  const used = org.api_calls_this_month;
  const limit = org.monthly_call_limit;
  const percent =
    limit > 0 ? Math.min(100, Math.round((used / limit) * 100)) : 0;

  const progressEl = document.getElementById("api-progress");
  if (progressEl) progressEl.value = percent;

  const usageText = document.getElementById("api-usage-text");
  if (usageText) {
    usageText.textContent = `${used.toLocaleString()} / ${limit.toLocaleString()} calls this month`;
    usageText.className =
      percent >= 90 ? "text-red" : percent >= 75 ? "text-orange" : "text-grey";
  }

  // Reset date
  const periodEl = document.getElementById("api-period");
  if (periodEl && org.api_calls_reset_date) {
    const resetDate = new Date(org.api_calls_reset_date * 1000);
    periodEl.textContent = `${resetDate.toLocaleDateString()}`;
  }

  // Server & Team usage — now dynamic from DB
  document.getElementById("server-usage-text").textContent =
    `${org.server_count} / ${org.server_limit || 1}`;

  document.getElementById("team-usage-text").textContent =
    `${org.members.length} / ${org.member_limit || 1}`;
}

function renderTeamMembers(members) {
  const tbody = document.getElementById("team-body");
  const noTeam = document.getElementById("no-team");
  if (!tbody) return;

  tbody.innerHTML = "";

  if (!members || members.length === 0) {
    noTeam.style.display = "block";
    return;
  }

  noTeam.style.display = "none";

  members.forEach((m) => {
    const row = document.createElement("tr");
    row.innerHTML = `
      <td>${m.email || "—"}</td>
      <td>${m.id || "—"}</td>
      <td>${m.level === 1 ? "Admin" : "Member"}</td>
      <td>${m.creation_time ? new Date(m.creation_time * 1000).toLocaleDateString() : "—"}</td>
    `;
    tbody.appendChild(row);
  });
}

// ==================== ACTIONS ====================

export async function refreshSettings() {
  sendWS({ command: "read_user" });
  sendWS({ command: "read_org" });
}

export async function saveAccount() {
  const userPayload = {
    command: "update_user",
    name: document.getElementById("edit-name").value.trim(),
  };

  const orgPayload = {
    command: "update_org",
    name: document.getElementById("edit-org-name").value.trim(),
    description: document.getElementById("edit-org-desc").value.trim(),
  };

  try {
    if (userPayload.name) {
      await sendWS(userPayload);
    }
    await sendWS(orgPayload);

    showToast("Account saved successfully", "success");
    await refreshSettings();
  } catch (e) {
    console.error(e);
    showToast("Failed to save account", "danger");
  }
}

function copyToken() {
  const tokenField = document.getElementById("account-token");
  if (!tokenField?.value) return;

  const text = tokenField.value;

  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard
      .writeText(text)
      .then(() => showToast("Token copied to clipboard", "success"))
      .catch(() => fallbackCopy(text));
  } else {
    fallbackCopy(text);
  }
}

function fallbackCopy(text) {
  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  document.body.appendChild(textarea);
  textarea.select();
  try {
    document.execCommand("copy");
    showToast("Token copied to clipboard", "success");
  } catch (e) {
    showToast("Failed to copy token", "danger");
  }
  document.body.removeChild(textarea);
}

export function updateLog(data) {
  if (data.command_reply !== "read_log") return;

  const modal = document.getElementById("log-modal");
  if (!modal) {
    console.warn("[updateLog] Log modal not found");
    return;
  }

  modal.classList.add("active");
  modal.dataset.jobId = data.job_id || data.id;

  const loading = document.getElementById("log-loading");
  const pre = document.getElementById("log-content");

  if (loading) loading.style.display = "none";
  if (pre) {
    pre.style.display = "block";
    pre.textContent = data.out || data.output || "(no output captured)";
    pre.scrollTop = pre.scrollHeight;
  }

  const jobName = data.job_name || "Unnamed Job";
  const jobId = data.job_id || "—";
  const runId = data.id || data.log_id || "latest";
  const serverName = data.server_name || "—";

  // Status calculation
  let status = "Success";
  let statusClass = "success";
  if (data.signal != null && data.signal !== 0) {
    status = `Terminated (signal ${data.signal})`;
    statusClass = "warning";
  } else if (data.exit_code != null && data.exit_code !== 0) {
    status = `Failed (exit ${data.exit_code})`;
    statusClass = "danger";
  }

  // Update title
  const titleEl = document.getElementById("log-modal-title");
  if (titleEl) {
    titleEl.textContent = `Job: ${jobName} • ID: ${jobId} • Run: ${runId} (${status})`;
    titleEl.className = `modal-title ${statusClass}`;
  }

  // Subtitle
  const startDate = data.started ? formatDate(data.started) : "—";
  const duration = formatDuration(data.started, data.ended) || "—";
  const pid = data.pid || "—";

  const subtitleEl = document.getElementById("log-modal-subtitle");
  if (subtitleEl) {
    subtitleEl.innerHTML = `
      Path: ${data.job_path || "—"} • Server: ${serverName}<br>
      Started: ${startDate} • Duration: ${duration} • PID: ${pid}
    `;
  }
}

export function showLogHistoryModal(jobId) {
  console.log("[showLogHistoryModal] Opening for job", jobId);

  const modalBody = document.querySelector("#log-history-modal .modal-body");
  console.log(
    "[showLogHistoryModal] modal-body children count before:",
    modalBody?.children.length || 0,
  );

  const modal = document.getElementById("log-history-modal");
  if (!modal) return console.warn("[showLogHistoryModal] Modal not found");

  modal.classList.add("active");
  modal.dataset.jobId = jobId;

  // ONLY clear the tbody — protect everything else
  const tbody = document.getElementById("log-history-body");
  const noHistory = document.getElementById("no-history");

  if (tbody) {
    tbody.innerHTML =
      '<tr><td colspan="4" class="text-center text-grey">Loading logs...</td></tr>';
  }
  if (noHistory) noHistory.style.display = "none";

  sendWS({
    command: "find_log",
    id: jobId,
  });
}

export function updateLogHistory(data) {
  if (data.command_reply !== "find_log") return;

  console.log(
    "[updateLogHistory] Called — modal-body innerHTML length before:",
    document.querySelector("#log-history-modal .modal-body")?.innerHTML
      .length || 0,
  );

  const tbody = document.getElementById("log-history-body");
  const noHistory = document.getElementById("no-history");
  const modal = document.getElementById("log-history-modal");

  if (!tbody) {
    console.warn("[updateLogHistory] tbody not found");
    return;
  }

  if (modal) modal.classList.add("active");

  // Critical: Only clear tbody, never the table or modal-body
  tbody.innerHTML = "";

  if (!data.logs || !Array.isArray(data.logs) || data.logs.length === 0) {
    if (noHistory) noHistory.style.display = "block";
    return;
  }

  if (noHistory) noHistory.style.display = "none";

  const fragment = document.createDocumentFragment();

  data.logs.forEach((log) => {
    const row = document.createElement("tr");
    row.style.cursor = "pointer";

    row.innerHTML = `
      <td>${escapeHtml(String(log.id || "—"))}</td>
      <td>${formatDate(log.started) || "—"}</td>
      <td>${formatDuration(log.started, log.ended) || "—"}</td>
      <td>${getStatusText(log.exit_code, log.signal)}</td>
    `;

    row.addEventListener("click", () => {
      if (modal) modal.classList.remove("active");
      sendWS({
        command: "read_log",
        id: data.job_id || data.id,
        log_id: log.id,
      });
    });

    fragment.appendChild(row);
  });

  tbody.appendChild(fragment);
}

export function renderCalendarsTable() {
  const tbody = document.getElementById("calendars-body");
  const table = document.getElementById("calendars-table");
  const noCalendars = document.getElementById("no-calendars");
  if (!tbody || !table || !noCalendars) return;

  const calendars = appState.calendarsData || [];
  const now = Math.floor(Date.now() / 1000);

  if (calendars.length === 0) {
    table.style.display = "none";
    noCalendars.style.display = "block";
    return;
  }

  table.style.display = "table";
  noCalendars.style.display = "none";
  tbody.innerHTML = "";

  calendars.forEach((cal) => {
    const calId = String(cal.id);
    const isCollapsed = appState.collapsedCalendars.has(calId);
    const hasCrons = Array.isArray(cal.crons) && cal.crons.length > 0;

    // Next Start Logic
    const calNextStart = Number(cal.next_start || 0);
    const hasValidNext = cal.cluster_ids?.length > 0 && calNextStart > now;
    const nextStartHtml = hasValidNext
      ? formatTminus(calNextStart) || "—"
      : "—";

    // Calendar Row
    const calRow = document.createElement("tr");
    calRow.className = `ordo-calendar-row ${isCollapsed ? "collapsed" : ""}`;
    calRow.dataset.id = calId;
    calRow.dataset.depth = "0";
    calRow.style.setProperty("--depth", "0");

    calRow.innerHTML = `
      <td>
        ${hasCrons ? `<span class="ordo-toggle"></span>` : `<span class="ordo-toggle empty"></span>`}
        <i class="fas fa-folder mr-2"></i>
        ${escapeHtml(cal.name || "Unnamed Calendar")}
      </td>
      <td>${escapeHtml(cal.tz || "—")}</td>
      <td>${escapeHtml(cal.description || "—")}</td>
      <td>${cal.crons?.length || 0}</td>
      <td>${cal.cluster_ids?.length || 0}</td>
      <td>—</td>
      <td>—</td>
      <td data-next-start="${hasValidNext ? calNextStart : ""}">${nextStartHtml}</td>
      <td>${generateCalendarActions(cal.id, hasCrons)}</td>
    `;

    tbody.appendChild(calRow);

    // Render Cron Rows
    if (hasCrons) {
      cal.crons.forEach((cron) => {
        const cronRow = document.createElement("tr");
        cronRow.className = `ordo-cron-row ${isCollapsed ? "hidden" : ""}`;
        cronRow.dataset.id = `cron-${calId}-${cron.id}`;
        cronRow.dataset.depth = "1";
        cronRow.dataset.parent = calId;
        cronRow.style.setProperty("--depth", "1");

        cronRow.innerHTML = `
          <td>
            <i class="fas fa-clock mr-2 has-text-cyan"></i>
            ${escapeHtml(cron.name || cron.expression || "—")}
          </td>
          <td>${escapeHtml(cron.english || "—")}</td>
          <td>${escapeHtml(cron.description || "—")}</td>
          <td>—</td>
          <td>—</td>
          <td>${cron.begin ? formatDate(cron.begin) : "Immediate"}</td>
          <td>${cron.expire ? formatDate(cron.expire) : "Never"}</td>
          <td>—</td>
          <td>${generateCronActions(cal.id, cron.id)}</td>
        `;

        tbody.appendChild(cronRow);
      });
    }
  });
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

  const monitorContent = document.getElementById("monitor-content");
  if (monitorContent) {
    monitorContent.style.display = "block";
  }

  if (!data.success || !data.clusters) {
    console.warn(
      "[updateJobsClusters] Received unsuccessful or empty response",
    );
    return;
  }

  console.log(
    `[updateJobsClusters] Processing ${data.clusters.length} clusters`,
  );

  // === 1. Populate authoritative Maps ===
  populateMapsFromClusters(data.clusters);

  // === 2. Build tree ===
  appState.monitorData.tree = buildTreeFromMaps();

  // === 3. Clean stale collapsed IDs ===
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
  appState.collapsedClusters.forEach((id) => {
    if (!currentClusterIds.has(id)) {
      appState.collapsedClusters.delete(id);
      cleanedCount++;
    }
  });

  if (cleanedCount > 0) {
    updateCollapsedClusters();
    console.log(`Cleaned ${cleanedCount} stale collapsed cluster ID(s)`);
  }

  // === 4. Render (with safety) ===
  renderJobsTable();

  // === 5. Dashboard sync ===
  if (document.getElementById("dashboard")?.classList.contains("active")) {
    console.log("[updateJobsClusters] Dashboard active → rendering");
    renderDashboard();
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

  renderCalendarsTable(); // ensure this handles []
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
    appState.serversData = []; // empty = no crash
    console.log("No servers found:", data.message || "empty response");
  }

  renderServersTable(); // your render must handle empty array gracefully
}

// ==================== DASHBOARD CORE ====================

function ensureClusterInState(update) {
  const id = Number(update.id);
  if (!id) return null;

  let cluster = appState.clustersMap.get(id);
  if (cluster) {
    Object.assign(cluster, update);
  } else {
    cluster = { ...update, is_cluster: true };
    appState.clustersMap.set(id, cluster);
    console.log(`[State Sync] Added new cluster ${id} to clustersMap`);
  }

  // Sync to main tree
  if (appState.monitorData?.tree) {
    const treeCluster = findClusterById(appState.monitorData.tree, id);
    if (treeCluster) {
      Object.assign(treeCluster, update);
    }
  }

  return cluster;
}

export function updateServerRow(row, server, now) {
  console.log(
    `[DEBUG Servers] updateServerRow called for ${server?.name} (actions cell: ${!!row?.cells?.[9]})`,
  );

  if (!row || !server) return;
  const cells = row.cells;
  if (!cells || cells.length < 10) return;

  if (server.update_time != null) {
    row.dataset.updateTime = server.update_time;
  }

  // 0: Name
  if (cells[0]) cells[0].textContent = server.name || "—";

  // 1: Host
  if (cells[1]) {
    cells[1].innerHTML = `<span title="${getHostTooltip(server)}">${escapeHtml(server.host || server.ip_address || "—")}</span>`;
  }

  // Status + freshness (column 2 + 3)
  updateFreshnessCell(row, server, now);

  // 4: Load Avg + tooltip
  if (cells[4]) {
    const load1 = server.load_1 != null ? server.load_1.toFixed(2) : "—";
    cells[4].textContent = load1;
    cells[4].title = getLoadTooltip(server);
  }

  // 5: CPU
  if (cells[5]) {
    const cpu =
      server.cpu_percent != null ? `${server.cpu_percent.toFixed(1)}%` : "—";
    cells[5].textContent = cpu;
  }

  // 6: Memory + tooltip
  if (cells[6]) {
    const { mem, tooltip } = formatMemory(server);
    cells[6].textContent = mem;
    cells[6].title = tooltip;
  }

  // 7: Disk (simple for now)
  if (cells[7]) {
    const disk = formatDisk(server);
    cells[7].textContent = disk.display;
    cells[7].title = disk.tooltip;
  }

  // 8: Uptime
  if (cells[8]) {
    const uptime = server.uptime != null ? formatUptime(server.uptime) : "—";
    cells[8].textContent = uptime;
  }

  // === COLUMN 9: ACTIONS — EXTREMELY CONSERVATIVE ===
  if (cells[9]) {
    const current = cells[9].innerHTML.trim();
    const newActions = `... your actions HTML ...`;

    // Only replace if the structure is different (e.g. new server id or something structural)
    if (!current.includes(`data-id="${server.id}"`)) {
      cells[9].innerHTML = newActions;
      console.log(`[DEBUG Servers] Replaced actions HTML for ${server.name}`);
    }
  }
}

export function applyServerBroadcast(data) {
  console.log("[DEBUG Servers] applyServerBroadcast received", data);
  if (!appState.serversData) appState.serversData = [];

  let changed = false;

  if (data.updates) {
    data.updates.forEach((update) => {
      console.log(`[DEBUG Servers] Updating server ${update.id}`);
      const id = Number(update.id);
      const idx = appState.serversData.findIndex((s) => Number(s.id) === id);
      if (idx !== -1) {
        appState.serversData[idx] = { ...appState.serversData[idx], ...update };
      } else {
        appState.serversData.push(update);
      }
      changed = true;
    });
  }

  if (data.deletes) {
    console.log("[DEBUG Servers] Deletes:", data.deletes);
    const deleteIds = data.deletes.map((d) => Number(d.id || d));
    appState.serversData = appState.serversData.filter(
      (s) => !deleteIds.includes(Number(s.id)),
    );
    //changed = true;
  }

  //if (
  //  changed &&
  //  document.getElementById("servers")?.classList.contains("active")
  //) {
    console.log("[DEBUG Servers] Calling renderServersTable");
    renderServersTable();
  //}
}

export function applyClusterBroadcast(data) {
  if (!data) return;
  console.log(
    `[applyClusterBroadcast] updates:${data.updates?.length || 0} deletes:${data.deletes?.length || 0}`,
  );

  let shouldRefreshCalendars = false;

  // === DELETES ===
  if (data.deletes && Array.isArray(data.deletes)) {
    data.deletes.forEach((del) => {
      const id = Number(del.id || del);
      if (!id) return;
      removeClusterRow(id, true);
      appState.clustersMap.delete(id);
      // Remove child jobs
      const jobsToRemove = [];
      appState.jobsMap.forEach((job, jobId) => {
        if (Number(job.cluster_id) === id) jobsToRemove.push(jobId);
      });
      jobsToRemove.forEach((jobId) => {
        removeJobRow(jobId, false);
        appState.jobsMap.delete(jobId);
      });
      if (appState.monitorData?.tree) {
        removeClusterById(appState.monitorData.tree, id);
      }
    });
  }

  // === UPDATES / NEW CLUSTERS ===
  if (data.updates && Array.isArray(data.updates)) {
    data.updates.forEach((update) => {
      const id = Number(update.id);
      if (!id) return;
      update.is_cluster = true;

      // Calendar sync — but don't force full render on every next_start tick
      if (update.cal_id !== undefined || update.next_start !== undefined) {
        shouldRefreshCalendars = true; // still mark it, but we'll be smarter below

        if (update.next_start !== undefined) {
          const calId = Number(update.cal_id);
          const calendar = appState.calendarsData.find(
            (c) => Number(c.id) === calId,
          );
          if (calendar) {
            calendar.next_start = Number(update.next_start);
            // === SURGICAL CALENDAR UPDATE INSTEAD OF FULL RENDER ===
            const calRow = document.querySelector(
              `tr.ordo-calendar-row[data-id="${calId}"]`,
            );
            if (calRow) {
              updateCalendarRow(calRow, calendar);
            }
          }
        }
      }

      // === ENSURE STATE IS UPDATED ===
      const cluster = ensureClusterInState(update);

      // Update DOM
      let row = document.getElementById(`row-cluster-${id}`);
      if (row) {
        updateClusterRow(row, cluster);
      } else {
        const parentId = Number(update.parent_id);
        insertCluster(cluster, parentId);
      }
    });
  }

  // === ONLY full render calendars if we really need it (new calendar, delete, etc.) ===
  if (
    shouldRefreshCalendars &&
    document.getElementById("calendars")?.classList.contains("active")
  ) {
    // Prefer surgical updates when possible
    // Only fall back to full render if there were structural changes
    console.log(
      "[applyClusterBroadcast] Calendars refreshed surgically where possible",
    );
    // renderCalendarsTable();   // ← Comment this out or make it conditional
  }

  refreshDashboardCards("clusters_changed");
}

// Simple, fast counters using Maps
export function countRunningJobs() {
  let count = 0;
  appState.jobsMap.forEach((job) => {
    const state = String(job.jobstate || "")
      .toLowerCase()
      .trim();
    if (state === "running" || state === "starting") count++;
  });
  return count;
}

export function countRecentFailedJobs() {
  let count = 0;
  appState.jobsMap.forEach((job) => {
    const state = String(job.jobstate || "")
      .toLowerCase()
      .trim();
    if (["failed", "killed", "zombie"].includes(state)) count++;
  });
  return count;
}

// In public/js/ui-handlers.js

export function updateNextScheduledCount() {
  const count = collectNextScheduledClusters().length;
  const countEl = document.getElementById("dash-next-count");
  if (countEl) countEl.textContent = count;
}

export function countOverdueClusters() {
  const now = Math.floor(Date.now() / 1000);
  let count = 0;

  appState.clustersMap.forEach((cluster) => {
    if (
      cluster.next_start &&
      Number(cluster.next_start) < now &&
      String(cluster.jobstate || "").toLowerCase() !== "running"
    ) {
      count++;
    }
  });

  return count;
}

export function applyJobBroadcast(data) {
  if (!data) return;
  console.log(
    `[applyJobBroadcast] updates:${data.updates?.length || 0} deletes:${data.deletes?.length || 0}`,
  );

  // === DELETES ===
  if (data.deletes && Array.isArray(data.deletes)) {
    data.deletes.forEach((del) => {
      const id = Number(del.id || del);
      if (!id) return;

      removeJobRow(id, false);
      appState.jobsMap.delete(id);

      if (appState.monitorData?.tree) {
        removeJobById(appState.monitorData.tree, id);
      }
    });
  }

  // === UPDATES / NEW JOBS ===
  if (data.updates && Array.isArray(data.updates)) {
    data.updates.forEach((update) => {
      if (update.is_cluster === true) return; // safety

      const id = Number(update.id);
      if (!id) return;

      update.is_cluster = false;

      // === SYNC STATE FIRST ===
      const job = syncItemToState(update, false);

      // Update DOM
      let row = document.getElementById(`row-job-${id}`);
      if (row) {
        updateJobRow(row, job);
      } else {
        const parentId = Number(update.cluster_id || update.parent_id);
        insertJob(job, parentId);
      }
    });
  }

  refreshDashboardCards("jobs_changed");
}

/**
 * Surgical update for a calendar row — NEVER destroys open dropdowns
 */
export function updateCalendarRow(row, cal) {
  if (!row || !cal) return;
  const cells = row.cells;
  if (!cells || cells.length < 9) return;

  const now = Math.floor(Date.now() / 1000);
  const hasValidNext =
    Array.isArray(cal.cluster_ids) &&
    cal.cluster_ids.length > 0 &&
    Number(cal.next_start) > now;

  // Column 0: Name + toggle (preserve collapsed)
  if (cells[0]) {
    const nameCell = cells[0];
    const toggle = nameCell.querySelector(".ordo-toggle");
    const isCollapsed = toggle?.classList.contains("collapsed") || false;
    const toggleHtml = toggle
      ? `<span class="ordo-toggle ${isCollapsed ? "collapsed" : ""}"></span>`
      : "";
    const newNameHTML = `${toggleHtml}<i class="fas fa-folder mr-2 has-text-info"></i>${escapeHtml(cal.name || "Unnamed Calendar")}`;

    if (nameCell.innerHTML !== newNameHTML) {
      nameCell.innerHTML = newNameHTML;
    }
  }

  // Columns 1-6: Safe text updates
  if (cells[1]) cells[1].textContent = cal.tz || "—";
  if (cells[2]) cells[2].textContent = cal.description || "—";
  if (cells[3])
    cells[3].textContent = Array.isArray(cal.crons) ? cal.crons.length : 0;
  if (cells[4])
    cells[4].textContent = Array.isArray(cal.cluster_ids)
      ? cal.cluster_ids.length
      : 0;
  if (cells[5])
    cells[5].textContent = cal.begin ? formatDate(cal.begin) : "Immediate";
  if (cells[6])
    cells[6].textContent = cal.expire ? formatDate(cal.expire) : "Never";

  // Column 7: Next Start (the frequent changer)
  if (cells[7]) {
    const newText = hasValidNext ? formatTminus(cal.next_start) || "—" : "—";
    if (cells[7].textContent !== newText) {
      cells[7].textContent = newText;
      cells[7].dataset.nextStart = hasValidNext ? String(cal.next_start) : "";
    }
  }

  // === ACTIONS COLUMN: DO NOT TOUCH AT ALL DURING LIVE UPDATES ===
  // We only update actions on full render or when crons actually change structurally
  console.log(
    `[updateCalendarRow] Updated calendar ${cal.id} (actions preserved)`,
  );
}

/**
 * Surgical update for a cron row - more robust
 */
export function updateCronRow(row, cron) {
  if (!row || !cron) return;
  const cells = row.cells;
  if (!cells || cells.length < 8) return;

  // Column 0: Expression / Name
  if (cells[0]) {
    cells[0].innerHTML = `<i class="fas fa-clock mr-2 has-text-cyan"></i>${escapeHtml(cron.name || cron.expression || "—")}`;
  }

  // Column 1: English
  if (cells[1]) cells[1].textContent = cron.english || "—";

  // Column 2: Description
  if (cells[2]) cells[2].textContent = cron.description || "—";

  // Column 5: Begin
  if (cells[5])
    cells[5].textContent = cron.begin ? formatDate(cron.begin) : "Immediate";

  // Column 6: Expire
  if (cells[6])
    cells[6].textContent = cron.expire ? formatDate(cron.expire) : "Never";

  console.log(`[updateCronRow] Updated cron ${cron.id}`);
}

function createCronRowElement(calId, cron) {
  const row = document.createElement("tr");
  row.className = `ordo-cron-row`;
  row.dataset.id = `cron-${calId}-${cron.id}`;
  row.dataset.parent = calId;
  row.dataset.depth = "1";

  row.innerHTML = `
    <td>
      <i class="fas fa-clock mr-2 has-text-cyan"></i>
      ${escapeHtml(cron.name || cron.expression || "—")}
    </td>
    <td>${escapeHtml(cron.english || "—")}</td>
    <td>${escapeHtml(cron.description || "—")}</td>
    <td>—</td>
    <td>—</td>
    <td>${cron.begin ? formatDate(cron.begin) : "Immediate"}</td>
    <td>${cron.expire ? formatDate(cron.expire) : "Never"}</td>
    <td>—</td>
    <td>${generateCronActions(calId, cron.id)}</td>
  `;

  return row;
}

export function applyCalBroadcast(data) {
  if (!data || data.broadcast !== "cals_changed") return;

  console.log(
    `[applyCalBroadcast] updates:${data.updates?.length || 0}, deletes:${data.deletes?.length || 0}`,
  );

  let needsFullRender = false;

  // === HANDLE DELETES ===
  if (data.deletes && Array.isArray(data.deletes)) {
    data.deletes.forEach((del) => {
      const id = Number(del.id || del);
      if (!id) return;

      // Remove calendar if it's a calendar delete
      const calRow = document.querySelector(
        `tr.ordo-calendar-row[data-id="${id}"]`,
      );
      if (calRow) {
        calRow.remove();
        // Also remove all its crons
        document
          .querySelectorAll(`tr.ordo-cron-row[data-parent="${id}"]`)
          .forEach((r) => r.remove());
        appState.calendarsData = appState.calendarsData.filter(
          (c) => Number(c.id) !== id,
        );
        return;
      }

      // If it's a cron delete (data-parent + cron id)
      const cronRow = document.querySelector(
        `tr.ordo-cron-row[data-id="${id}"]`,
      );
      if (cronRow) {
        cronRow.remove();
      }
    });
  }

  // === HANDLE UPDATES ===
  if (data.updates && Array.isArray(data.updates)) {
    data.updates.forEach((calUpdate) => {
      const calId = Number(calUpdate.id);
      if (!calId) return;

      const existingIndex = appState.calendarsData.findIndex(
        (c) => Number(c.id) === calId,
      );

      if (existingIndex !== -1) {
        // Update calendar data
        appState.calendarsData[existingIndex] = {
          ...appState.calendarsData[existingIndex],
          ...calUpdate,
          next_start:
            calUpdate.next_start !== undefined
              ? Number(calUpdate.next_start)
              : appState.calendarsData[existingIndex].next_start,
        };

        // Update calendar row
        const calRow = document.querySelector(
          `tr.ordo-calendar-row[data-id="${calId}"]`,
        );
        if (calRow) {
          updateCalendarRow(calRow, appState.calendarsData[existingIndex]);
        }

        // === CRON LEVEL SURGICAL UPDATES + DELETE + INSERT ===
        if (Array.isArray(calUpdate.crons)) {
          const currentCronRows = new Map();
          document
            .querySelectorAll(`tr.ordo-cron-row[data-parent="${calId}"]`)
            .forEach((row) => {
              const key = row.dataset.id.replace(`cron-${calId}-`, "");
              currentCronRows.set(key, row);
            });

          const newCronIds = new Set(calUpdate.crons.map((c) => String(c.id)));

          // Remove crons that no longer exist
          currentCronRows.forEach((row, cronId) => {
            if (!newCronIds.has(cronId)) {
              row.remove();
            }
          });

          // Update or insert crons
          calUpdate.crons.forEach((cron) => {
            const cronKey = String(cron.id);
            const existingRow = currentCronRows.get(cronKey);

            if (existingRow) {
              updateCronRow(existingRow, cron);
            } else {
              // Insert new cron row
              const newRow = createCronRowElement(calId, cron);
              const targetCalRow = document.querySelector(
                `tr.ordo-calendar-row[data-id="${calId}"]`,
              );
              if (targetCalRow) {
                targetCalRow.after(newRow);
              }
            }
          });
        }
      } else {
        // New calendar
        appState.calendarsData.push({ ...calUpdate });
        needsFullRender = true;
      }
    });
  }

  if (
    needsFullRender &&
    document.getElementById("calendars")?.classList.contains("active")
  ) {
    renderCalendarsTable();
  }
}

function findCalendarById(calendars, calId) {
  return calendars.find((c) => Number(c.id) === Number(calId));
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

      if (typeof hljs !== "undefined") {
        hljs.highlightAll();
      }

      // Update active TOC link
      document
        .querySelectorAll("#docs-toc a")
        .forEach((a) => a.classList.remove("active"));
      const activeLink = document.querySelector(
        `#docs-toc a[data-file="${file}"]`,
      );
      if (activeLink) activeLink.classList.add("active");

      // === FOCUS THE CONTENT AREA FOR IMMEDIATE KEYBOARD SCROLLING ===
      const docsContent = document.getElementById("docs-content");
      if (docsContent) {
        docsContent.tabIndex = -1;
        docsContent.focus();
        docsContent.scrollTop = 0;
      }
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

// ==================== DELETE MY ACCOUNT ====================
document.getElementById("delete-my-account")?.addEventListener("click", () => {
  openConfirmModal(
    "Delete My Account",
    "⚠️ This action is PERMANENT and cannot be undone.\n\n" +
    "Your account, all jobs, clusters, calendars, and data will be permanently deleted.\n\n" +
    "Type DELETE below to confirm.",
    () => {
      // Send delete command
      if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
        appState.ws.send(JSON.stringify({ command: "delete_me" }));
        showToast("Account deletion requested...", "info");
      } else {
        showToast("Not connected to server", "danger");
      }
    },
    null,      // onCancel
    true       // requireDeleteConfirmation = true
  );
});

// ==================== DELETE MY ACCOUNT ====================
/*
document.getElementById("delete-my-account")?.addEventListener("click", () => {
  openConfirmModal(
    "Delete My Account",
    "⚠️ This action is PERMANENT and cannot be undone.\n\n" +
    "Your account, all jobs, clusters, calendars, and data will be permanently deleted.\n\n" +
    "Type DELETE below to confirm.",
    (confirmedText) => {
      if (confirmedText !== "DELETE") {
        showToast("You must type exactly 'DELETE' to confirm", "danger");
        return;
      }

      // Disable button during request
      const deleteBtn = document.getElementById("delete-my-account");
      if (deleteBtn) {
        deleteBtn.disabled = true;
        deleteBtn.textContent = "Deleting Account...";
      }

      // Send delete command via WebSocket
      if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
        appState.ws.send(JSON.stringify({
          command: "delete_me"
        }));

        showToast("Account deletion requested...", "info");
      } else {
        showToast("Not connected to server", "danger");
        if (deleteBtn) {
          deleteBtn.disabled = false;
          deleteBtn.textContent = "Delete My Account";
        }
      }
    }
  );
});
*/

// Internal tabs in Settings
document.addEventListener("click", (e) => {
  const tabBtn = e.target.closest(".internal-tab");
  if (!tabBtn) return;

  const tabId = tabBtn.dataset.tab;
  const container = tabBtn.closest("#settings-content");
  if (!container) return;

  // Remove active from all buttons and contents
  container
    .querySelectorAll(".internal-tab")
    .forEach((b) => b.classList.remove("active"));
  container
    .querySelectorAll(".internal-tab-content")
    .forEach((c) => (c.style.display = "none"));

  // Activate clicked
  tabBtn.classList.add("active");
  const content = container.querySelector(`#tab-${tabId}`);
  if (content) content.style.display = "block";
});

// Mobile TOC toggle
document.getElementById("docs-toc-toggle")?.addEventListener("click", () => {
  document.getElementById("docs-toc").classList.toggle("is-open");
});

// TOC click handler
// Inside your TOC click handler
/*
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
*/

// Safe Docs TOC Click Handler
function attachDocsTocListener() {
  const toc = document.getElementById("docs-toc");
  if (!toc) return;

  // Remove any existing listeners to prevent duplicates
  const newToc = toc.cloneNode(true);
  toc.parentNode.replaceChild(newToc, toc);

  newToc.addEventListener("click", (e) => {
    const link = e.target.closest("a");
    if (link && link.dataset.file) {
      e.preventDefault();
      loadDoc(link.dataset.file);
    }
  });
}

// Call it when Docs tab is activated
document.addEventListener("DOMContentLoaded", attachDocsTocListener);

// Re-attach when switching to Docs tab
/*
const originalTabHandler = window.activateTab || function () {};
window.activateTab = function (tabId) {
  if (typeof originalTabHandler === "function") originalTabHandler(tabId);

  if (tabId === "docs") {
    setTimeout(attachDocsTocListener, 200);
  }
};
*/

export function attachCalendarsTreeListeners() {
  const tbody = document.getElementById("calendars-body");
  if (!tbody) return;

  tbody.addEventListener("click", (e) => {
    const toggle = e.target.closest(".ordo-toggle");
    if (!toggle || toggle.classList.contains("empty")) return;

    const row = toggle.closest("tr");
    if (!row?.dataset.id) return;

    const calId = String(row.dataset.id);
    const isNowCollapsed = !appState.collapsedCalendars.has(calId);

    if (isNowCollapsed) {
      appState.collapsedCalendars.add(calId);
    } else {
      appState.collapsedCalendars.delete(calId);
    }

    // Re-render is the most reliable way for calendars
    renderCalendarsTable();
  });
}

// ==================== LOGIN MODAL ====================

export function showLoginModal(redirectContext = "") {
  const modal = document.getElementById("login-modal");
  if (!modal) return;

  modal.dataset.redirectContext = redirectContext;

  document.getElementById("login-form-container").style.display = "block";
  document.getElementById("login-success").style.display = "none";
  document.getElementById("login-email").value = "";

  modal.classList.add("active");
  document.getElementById("login-email").focus();
}

function initLoginModalListeners() {
  const modal = document.getElementById("login-modal");
  if (!modal) return;

  // Close button
  modal.querySelector(".close-btn")?.addEventListener("click", () => {
    modal.classList.remove("active");
  });

  // Form submit
  /*
  const form = document.getElementById("login-form");
  if (form) {
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const email = document.getElementById("login-email").value.trim();
      if (!email) return;

      const btn = document.getElementById("send-magic-link-btn");
      btn.disabled = true;
      btn.textContent = "Sending...";

      try {
        await fetch("/login", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({ email: email }),
        });

        document.getElementById("login-form-container").style.display = "none";
        document.getElementById("login-success").style.display = "block";
      } catch (err) {
        showToast("Failed to send magic link", "danger");
      } finally {
        btn.disabled = false;
        btn.textContent = "Send Magic Link";
      }
    });
  }
*/
}

// ==================== PRICING MODAL ====================
export function showPricingModal() {
  const modal = document.getElementById("pricing-modal");
  if (!modal) return;

  const isLoggedIn = document.body.classList.contains("is-logged-in");

  // Highlight current plan only if logged in
  if (isLoggedIn && appState.orgData?.tier) {
    const currentTier = appState.orgData.tier.toLowerCase();
    document.querySelectorAll("#pricing-modal .card-simple").forEach((card) => {
      card.style.borderColor = "";
      card.style.boxShadow = "";
      if (card.id === `plan-${currentTier}`) {
        card.style.borderColor = "var(--glow-cyan)";
        card.style.boxShadow = "0 0 25px rgba(0, 255, 255, 0.4)";
      }
    });
  }

  modal.classList.add("active");
}

function initPricingModalListeners() {
  const modal = document.getElementById("pricing-modal");
  if (!modal) return;

  modal.addEventListener("click", (e) => {
    const upgradeBtn = e.target.closest("button[data-plan]");
    if (upgradeBtn) {
      const plan = upgradeBtn.dataset.plan;
      modal.classList.remove("active");

      const isLoggedIn = document.body.classList.contains("is-logged-in");

      if (!isLoggedIn) {
        showLoginModal("pricing"); // Ask to log in first
      } else {
        sendWS({ command: "create_checkout_session", plan: plan });
        showToast(`Redirecting to ${plan} checkout...`, "info");
      }
      return;
    }

    if (e.target.id === "contact-sales-btn") {
      modal.classList.remove("active");
      window.location.href =
        "mailto:ordosched@proton.me?subject=Enterprise%20Inquiry";
    }

    if (e.target.classList.contains("close-btn")) {
      modal.classList.remove("active");
    }
  });
}

function debugDumpTreeContext() {
  const tree = appState.monitorData?.tree || [];
  console.groupCollapsed(
    `[Tree Debug] ${new Date().toLocaleTimeString()} - ${tree.length} top-level items`,
  );

  let runningCount = 0;
  let staleRunning = [];

  traverseTree(tree, (item) => {
    if (item.is_cluster) return;
    if ((item.jobstate || "").toLowerCase() === "running") {
      runningCount++;
      const age = item.started
        ? Math.floor(Date.now() / 1000) - Number(item.started)
        : 0;
      if (age > 30) {
        // suspiciously old
        staleRunning.push({
          id: item.id,
          name: item.name,
          started: item.started,
          ageSeconds: age,
          state: item.jobstate,
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

// ==================== DASHBOARD MAIN RENDER ====================
export function renderDashboard() {
  document.getElementById("dash-running-list").innerHTML =
    getLongestRunningJobsHTML(5);
  document.getElementById("dash-failed-list").innerHTML =
    getRecentlyFailedListHTML(5);
  document.getElementById("dash-overdue-list").innerHTML =
    getOverdueClustersListHTML();

  updateNextScheduledClusters(); // ← important
  renderRecentActivityTable();

  // Do NOT call updateKPIBar here — it's handled live by broadcasts
  startDashboardLiveTimer();
}

// ==================== CARD FUNCTIONS (Maps-only) ====================

export function getLongestRunningJobsHTML(max = 5) {
  const jobMap = new Map();

  appState.jobsMap.forEach((job) => {
    const state = String(job.jobstate || "")
      .toLowerCase()
      .trim();
    if (state !== "running" && state !== "starting") return;

    const jobId = Number(job.id);
    const started = Number(job.started || 0);
    if (started < 1000000000) return;

    const runtime = formatTplus(started) || "just started";
    const fullPath = getFullPath(job, appState.monitorData.tree);

    const existing = jobMap.get(jobId);
    if (!existing || started > Number(existing.started || 0)) {
      jobMap.set(jobId, {
        name: job.name || "Unnamed",
        fullPath,
        started,
        runtime,
      });
    }
  });

  const running = Array.from(jobMap.values())
    .sort((a, b) => b.started - a.started)
    .slice(0, max);

  const countEl = document.getElementById("dash-running-count");
  if (countEl) countEl.textContent = running.length;

  if (running.length === 0) {
    return `<div class="empty-state">No jobs currently running</div>`;
  }

  return running
    .map(
      (job) => `
    <div class="mini-item dash-running-item" title="${job.fullPath}">
      <div class="mini-item-name">
        <span class="mini-job">⚙️ ${job.name}</span>
      </div>
      <div class="mini-item-time runtime" data-started="${job.started}">
        ${job.runtime}
      </div>
    </div>
  `,
    )
    .join("");
}

export function getRecentlyFailedListHTML(max = 5) {
  const now = Math.floor(Date.now() / 1000);
  const failed = [];

  appState.jobsMap.forEach((job) => {
    const state = String(job.jobstate || "")
      .toLowerCase()
      .trim();
    if (!["failed", "killed", "zombie"].includes(state) || !job.ended) return;

    const endedTs = Number(job.ended);
    const agoSeconds = now - endedTs;
    if (agoSeconds < 0) return;

    const path = getFullPath(job, appState.monitorData.tree);

    failed.push({
      name: job.name || "Unnamed",
      path: path,
      endedTs: endedTs,
      agoSeconds: agoSeconds,
    });
  });

  failed.sort((a, b) => b.endedTs - a.endedTs);
  const topFailed = failed.slice(0, max);

  const countEl = document.getElementById("dash-failed-count");
  if (countEl) countEl.textContent = topFailed.length;

  if (topFailed.length === 0) {
    return `<div class="empty-state">No recent failures</div>`;
  }

  return topFailed
    .map(
      (item) => `
      <div class="mini-item">
        <div class="mini-item-name">
          <span class="mini-job">⚙️ ${item.name}</span>
        </div>
        <div class="mini-item-time text-red failed-time" 
             data-ended="${item.endedTs}">
          ${formatRelativeTime(item.agoSeconds)}
        </div>
      </div>
    `,
    )
    .join("");
}

export function getOverdueClustersListHTML(max = 5) {
  const now = Math.floor(Date.now() / 1000);
  const overdue = [];

  appState.clustersMap.forEach((cluster) => {
    const next = Number(cluster.next_start);
    if (!next || next > now) return;

    overdue.push({
      name: cluster.name || "Unnamed",
      nextStart: next,
      overdueBy: formatTminus(next) || "Overdue",
    });
  });

  overdue.sort((a, b) => a.nextStart - b.nextStart);
  const topOverdue = overdue.slice(0, max);

  const countEl = document.getElementById("dash-overdue-count");
  if (countEl) countEl.textContent = topOverdue.length;

  if (topOverdue.length === 0) {
    return `<div class="empty-state">No overdue clusters</div>`;
  }

  return topOverdue
    .map(
      (item) => `
    <div class="mini-item" title="Overdue cluster: ${item.name}">
      <div class="mini-item-name">
        <span class="mini-path">📁 ${item.name}</span>
      </div>
      <div class="mini-item-time overdue-time" data-next-start="${item.nextStart}">
        ${item.overdueBy}
      </div>
    </div>
  `,
    )
    .join("");
}

export function updateNextScheduledClusters() {
  const container = document.getElementById("dash-next-5");
  if (!container) return;

  const upcoming = collectNextScheduledClusters(5); // assuming this helper exists

  const countEl = document.getElementById("dash-next-count");
  if (countEl) countEl.textContent = upcoming.length;

  if (upcoming.length === 0) {
    container.innerHTML = `<div class="empty-state">No upcoming scheduled clusters</div>`;
    return;
  }

  container.innerHTML = upcoming
    .map(
      (item) => `
    <div class="mini-item dash-next-item" title="Next run for cluster: ${item.name}">
      <div class="mini-item-name">
        <span class="mini-path">📁 ${item.name}</span>
      </div>
      <div class="mini-item-time countdown" data-nextStart="${item.next_start}">
        ${formatTminus(item.next_start) || "—"}
      </div>
    </div>
  `,
    )
    .join("");
}

export function collectNextScheduledClusters(limit = 6) {
  const now = Math.floor(Date.now() / 1000);
  const upcoming = [];

  appState.clustersMap.forEach((cluster) => {
    const next = Number(cluster.next_start);
    if (!next || isNaN(next)) return;

    const state = String(cluster.jobstate || "")
      .toLowerCase()
      .trim();

    // Only include clusters that are truly scheduled in the future
    // and not currently overdue or on hold
    if (next > now && state !== "hold") {
      upcoming.push({
        id: cluster.id,
        name: cluster.name || "Unnamed",
        next_start: next,
        state: state,
      });
    }
  });

  // Sort by soonest first
  upcoming.sort((a, b) => a.next_start - b.next_start);

  return upcoming.slice(0, limit);
}

// Only updates live timings — nothing else
let dashboardLiveTimer = null;
let dashboardTimingCache = null;

export function startDashboardLiveTimer() {
  if (dashboardLiveTimer) return;

  console.log("[DashboardTimer] Starting with cache setup");

  refreshDashboardTimingCache();

  dashboardLiveTimer = setInterval(updateDashboardLiveTimings, 1000);
  updateDashboardLiveTimings(); // immediate update
}

function refreshDashboardTimingCache() {
  dashboardTimingCache = {
    countdowns: document.querySelectorAll(
      ".countdown, [data-nextstart], [data-next-start]",
    ),
    runtimes: document.querySelectorAll(".runtime, [data-started]"),
    recentTimes: document.querySelectorAll(
      "#dash-recent-body td[data-timestamp]",
    ),
    failedTimes: document.querySelectorAll(".failed-time, [data-ended]"),
  };

  console.log(
    `[DashboardTimer] Cache refreshed: ${dashboardTimingCache.countdowns.length} countdowns, ${dashboardTimingCache.runtimes.length} runtimes`,
  );
}

export function updateDashboardLiveTimings() {
  if (!document.getElementById("dashboard")?.classList.contains("active"))
    return;

  const now = Math.floor(Date.now() / 1000);

  // Live countdowns (T-minus) - Next Scheduled
  dashboardTimingCache.countdowns.forEach((el) => {
    const next = parseInt(el.dataset.nextStart || el.dataset.nextstart || 0);
    if (next > 0) {
      el.textContent = formatTminus(next) || "—";
    }
  });

  // Running job timers (T-plus)
  dashboardTimingCache.runtimes.forEach((el) => {
    const started = parseInt(el.dataset.started || 0);
    if (started > 0) {
      el.textContent = formatTplus(started) || "—";
    }
  });

  // Recent activity "ago" times
  dashboardTimingCache.recentTimes.forEach((td) => {
    const ts = parseInt(td.dataset.timestamp || 0);
    if (ts > 0) td.textContent = formatRelativeTime(now - ts);
  });

  // Recently failed times
  dashboardTimingCache.failedTimes.forEach((el) => {
    const endedTs = parseInt(el.dataset.ended || 0);
    if (endedTs > 0) el.textContent = formatRelativeTime(now - endedTs);
  });

  // Overdue Clusters - Always check and refresh when needed
  const overdueList = document.getElementById("dash-overdue-list");
  if (overdueList) {
    let hasOverdue = false;
    appState.clustersMap.forEach((cluster) => {
      const next = Number(cluster.next_start);
      if (next && next <= now) hasOverdue = true;
    });

    // Refresh if there are overdue items OR if the list currently has content
    if (hasOverdue || overdueList.children.length > 0) {
      overdueList.innerHTML = getOverdueClustersListHTML();
    }
  }
}

export function stopDashboardLiveTimer() {
  if (dashboardLiveTimer) {
    clearInterval(dashboardLiveTimer);
    dashboardLiveTimer = null;
  }
  dashboardTimingCache = null;
}

export function updateDashboardLiveCards() {
  if (!document.getElementById("dashboard")?.classList.contains("active"))
    return;

  console.log("[updateDashboardLiveCards] Refreshing all cards");

  // These can safely do full innerHTML rebuilds
  const runningList = document.getElementById("dash-running-list");
  if (runningList) runningList.innerHTML = getLongestRunningJobsHTML(5);

  const failedList = document.getElementById("dash-failed-list");
  getRecentlyFailedListHTML(5);
  //if (failedList) failedList.innerHTML = getRecentlyFailedListHTML(5);

  // Next Scheduled & Overdue
  updateNextScheduledClusters();
  const overdueList = document.getElementById("dash-overdue-list");
  if (overdueList) overdueList.innerHTML = getOverdueClustersListHTML();

  // Recent Activity
  renderRecentActivityTable();
}

// ==================== DASHBOARD CORE ====================

export function refreshDashboard() {
  if (!document.getElementById("dashboard")?.classList.contains("active"))
    return;

  console.log("[refreshDashboard] Full refresh");

  // Rebuild all visual cards from current Maps (single source of truth)
  document.getElementById("dash-running-list").innerHTML =
    getLongestRunningJobsHTML(5);
  document.getElementById("dash-failed-list").innerHTML =
    getRecentlyFailedListHTML(5);
  document.getElementById("dash-overdue-list").innerHTML =
    getOverdueClustersListHTML();

  updateNextScheduledClusters();
  renderRecentActivityTable();
  updateDashboardLiveTimings();
}

// ==================== DASHBOARD REFRESH ====================
let dashboardRefreshTimeout = null;

export function refreshDashboardCards(reason = "") {
  if (!document.getElementById("dashboard")?.classList.contains("active"))
    return;

  console.log(`[refreshDashboardCards] Queued by: ${reason}`);

  // Debounce the actual refresh
  clearTimeout(dashboardRefreshTimeout);
  dashboardRefreshTimeout = setTimeout(() => {
    refreshDashboardCardsInternal();
  }, 350);
}

function refreshDashboardCardsInternal() {
  console.log("[refreshDashboardCardsInternal] Executing full refresh");

  const runningList = document.getElementById("dash-running-list");
  const failedList = document.getElementById("dash-failed-list");
  const overdueList = document.getElementById("dash-overdue-list");

  if (runningList) runningList.innerHTML = getLongestRunningJobsHTML(5);
  if (failedList) failedList.innerHTML = getRecentlyFailedListHTML(5);
  if (overdueList) overdueList.innerHTML = getOverdueClustersListHTML();

  updateNextScheduledClusters();
  renderRecentActivityTable();
  updateDashboardLiveTimings();
  // IMPORTANT: Refresh cache after rebuild
  if (typeof refreshDashboardTimingCache === "function") {
    refreshDashboardTimingCache();
  }
}

// KPI Bar Updater
export function updateKPIBar(stats = {}) {
  console.log(
    "[updateKPIBar] Called with runs=",
    stats.runs_today,
    "failed=",
    stats.failed_runs_today,
  );

  const successEl = document.getElementById("kpi-success-rate");
  const runsEl = document.getElementById("kpi-runs-today");
  const failedEl = document.getElementById("kpi-failed-today"); // if you have this field

  console.log("[updateKPIBar] Elements found:", {
    success: !!successEl,
    runs: !!runsEl,
    failed: !!failedEl,
  });

  if (successEl) successEl.textContent = (stats.success_rate || 100) + "%";
  if (runsEl) runsEl.textContent = stats.runs_today || 0;
  if (failedEl) failedEl.textContent = stats.failed_runs_today || 0;

  console.log("[updateKPIBar] DOM updated →", {
    success: successEl ? successEl.textContent : null,
    runs: runsEl ? runsEl.textContent : null,
  });
}

// Broadcast-driven updates
export function updateDashboardFromBroadcast(data) {
  if (!data) return;

  // Handle find_stats reply
  if (data.command_reply === "find_stats") {
    console.log("[find_stats] Reply received:", data);
    appState.dashboardStats = data;
    return;
  }

  // Handle jobs_changed incremental counter (only once)
  if (data.broadcast === "jobs_changed" && data.updates?.length) {
    updateDashboardCountersFromBroadcast(data.updates);
  }

  // Light UI refresh if dashboard is visible
  if (document.getElementById("dashboard")?.classList.contains("active")) {
    renderDashboard();
  }
}

// Global deduplication tracker (outside any function)
let lastProcessedJobUpdate = new Map(); // job_id → timestamp

export function updateDashboardCountersFromBroadcast(updates = []) {
  if (
    !appState.dashboardStats ||
    !Array.isArray(updates) ||
    updates.length === 0
  ) {
    return;
  }

  let newRuns = 0;
  let newFailed = 0;
  const now = Date.now();

  updates.forEach((item) => {
    if (
      !item ||
      item.is_cluster ||
      !item.jobstate ||
      typeof item.jobstate !== "string"
    ) {
      return;
    }

    const jobId = Number(item.id);
    if (!jobId) return;

    const lastTime = lastProcessedJobUpdate.get(jobId) || 0;
    if (now - lastTime < 800) {
      console.log(`[Counter] Ignored duplicate update for job ${jobId}`);
      return;
    }
    lastProcessedJobUpdate.set(jobId, now);

    const state = item.jobstate.toLowerCase().trim();

    if (state === "complete" || state === "completed") {
      newRuns++;
    } else if (state === "failed" || state === "killed" || state === "zombie") {
      newRuns++;
      newFailed++;
    }
  });

  if (newRuns > 0 || newFailed > 0) {
    appState.dashboardStats.runs_today =
      (appState.dashboardStats.runs_today || 0) + newRuns;
    appState.dashboardStats.failed_runs_today =
      (appState.dashboardStats.failed_runs_today || 0) + newFailed;

    console.log(
      `[Counter] +${newRuns} runs, +${newFailed} failed → Total runs: ${appState.dashboardStats.runs_today}`,
    );

    // ← THIS WAS MISSING
    updateKPIBar(appState.dashboardStats);
  }
}

export function getNextScheduledHTML(max = 5) {
  const now = Math.floor(Date.now() / 1000);
  const upcoming = [];

  appState.clustersMap.forEach((cluster) => {
    const next = Number(cluster.next_start);
    if (!next || next <= now) return;

    upcoming.push({
      name: cluster.name || "Unnamed",
      nextStart: next,
      tminus: formatTminus(next) || "—",
    });
  });

  upcoming.sort((a, b) => a.nextStart - b.nextStart);
  const topUpcoming = upcoming.slice(0, max);

  const countEl = document.getElementById("dash-next-count");
  if (countEl) countEl.textContent = topUpcoming.length;

  if (topUpcoming.length === 0) {
    return `<div class="empty-state">No upcoming runs scheduled</div>`;
  }

  return topUpcoming
    .map(
      (item) => `
    <div class="mini-item">
      <div class="mini-item-name">
        <span class="mini-path">📁 ${item.name}</span>
      </div>
      <div class="mini-item-time countdown" data-next-start="${item.nextStart}">
        ${item.tminus}
      </div>
    </div>
  `,
    )
    .join("");
}

// Initial stats load - called once after login or when dashboard tab is first activated
export function loadDashboardStats() {
  const since = getStartOfTodayUnix();

  console.log(`[find_stats] Requesting initial stats (since: ${since})`);

  sendWS({
    command: "find_stats",
    since: since,
  });
}

// Resync Button
export function initResyncButton() {
  const btn = document.getElementById("resync-all-btn");
  if (!btn) return;

  btn.addEventListener("click", () => {
    if (btn.disabled) return;
    const originalHTML = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Resyncing...';

    sendWS({ command: "sync" });
    // sendWS({ command: "find_stats", since: getStartOfTodayUnix() });
    // sendWS({ command: "find_cluster", name: "root" });

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

// In public/js/ui-handlers.js

export function getRunningJobsListHTML(tree, max = 8) {
  let html = "";
  let shown = 0;

  traverseTree(tree, (item) => {
    if (
      (item.jobstate === "running" || item.state === "running") &&
      shown < max
    ) {
      const duration = item.started
        ? formatTplus(item.started)
        : "just started";
      html += `
        <div class="flex justify-between items-center py-1">
          <span class="truncate">${item.name || "Unnamed"}</span>
          <span class="text-xs">${duration}</span>
        </div>`;
      shown++;
    }
  });

  if (shown === 0) {
    html =
      '<div class="text-grey text-sm py-6 text-center">No jobs currently running</div>';
  }

  return html;
}

// ==================== RECENT ACTIVITY ====================

// In public/js/ui-handlers.js
export function renderRecentActivityTable() {
  const tbody = document.getElementById("dash-recent-body");
  if (!tbody) return;

  tbody.innerHTML = "";

  const activities = collectRecentActivityFromMap(12);

  if (activities.length === 0) {
    tbody.innerHTML = `<tr><td colspan="4" class="text-center text-grey py-12">No recent activity</td></tr>`;
    return;
  }

  activities.forEach((item) => {
    const row = document.createElement("tr");
    const stateClass = (item.jobstate || "unknown").toLowerCase();

    row.innerHTML = `
      <td data-timestamp="${item.timestamp}">${item.timeAgo}</td>
      <td class="font-medium">${item.name || "Unnamed"}</td>
      <td><span class="state-badge ${stateClass}">${item.action}</span></td>
      <td class="text-grey">${item.server || "—"}</td>
    `;
    tbody.appendChild(row);
  });
}

function collectRecentActivityFromMap(max = 12) {
  const activities = [];
  const now = Math.floor(Date.now() / 1000);

  appState.jobsMap.forEach((job) => {
    if (
      job.name === "root" ||
      (job.parent_id == null && job.name?.toLowerCase() === "root")
    )
      return;

    const timestamp =
      job.ended || job.last_update || job.started || job.creation_time || 0;
    if (!timestamp) return;

    let action = "Updated";
    const state = String(job.jobstate || "")
      .toLowerCase()
      .trim();

    if (state.includes("fail") || state === "killed") action = "Failed";
    else if (state === "complete" || state === "completed")
      action = "Completed";
    else if (state === "running") action = "Running";
    else if (state === "starting") action = "Starting";
    else if (state === "hold") action = "Held";
    else if (state === "ice") action = "Iced";

    activities.push({
      name: job.name || "Unnamed",
      action: action,
      server: job.server_name || "—",
      timestamp: timestamp,
      timeAgo: formatRelativeTime(now - timestamp),
      jobstate: state,
    });
  });

  activities.sort((a, b) => b.timestamp - a.timestamp);
  return activities.slice(0, max);
}

// ==================== HELPER ====================

// Incremental KPI updates with deduplication for terminal states
export function incrementDashboardStatsFromJob(job) {
  if (!job?.id) return;

  if (!appState.dashboardStats) {
    appState.dashboardStats = {
      runs_today: 0,
      failed_runs_today: 0,
      success_rate: 100,
    };
  }

  if (!appState._countedTerminalJobs) {
    appState._countedTerminalJobs = new Map();
  }

  const state = (job.jobstate || "").toLowerCase().trim();
  const jobKey = `${job.id}-${job.started || job.last_update || Date.now()}`; // ← key change

  const lastCounted = appState._countedTerminalJobs.get(jobKey);

  let changed = false;

  if (state === "complete" && lastCounted !== "complete") {
    appState.dashboardStats.runs_today =
      (appState.dashboardStats.runs_today || 0) + 1;
    appState._countedTerminalJobs.set(jobKey, "complete");
    changed = true;
  } else if (
    (state === "failed" || state === "killed" || state === "zombie") &&
    lastCounted !== state
  ) {
    appState.dashboardStats.runs_today =
      (appState.dashboardStats.runs_today || 0) + 1;
    appState.dashboardStats.failed_runs_today =
      (appState.dashboardStats.failed_runs_today || 0) + 1;
    appState._countedTerminalJobs.set(jobKey, state);
    changed = true;
  }

  if (changed) {
    const runs = appState.dashboardStats.runs_today || 0;
    const failed = appState.dashboardStats.failed_runs_today || 0;
    if (runs > 0) {
      const percent = (100 * (runs - failed)) / runs;
      appState.dashboardStats.success_rate = Math.round(percent * 10) / 10;
    }

    updateKPIBar(appState.dashboardStats);
  }
}

function collectRecentActivity(tree, max = 12) {
  const activities = [];
  const now = Math.floor(Date.now() / 1000);

  traverseTree(tree, (item) => {
    // === SKIP ROOT CLUSTER ===
    if (
      !item ||
      item.name === "root" ||
      (item.parent_id === null && item.name?.toLowerCase() === "root")
    ) {
      return;
    }

    const timestamp =
      item.ended || item.last_update || item.started || item.creation_time || 0;
    if (!timestamp) return;

    let action = "—";
    const js = (item.jobstate || "").toLowerCase();

    if (js === "failed" || js === "killed") action = "Failed";
    else if (js === "complete" || js === "completed") action = "Completed";
    else if (js === "running" || js === "starting") action = "Started";
    else if (js === "hold") action = "Held";
    else if (js === "ice") action = "Iced";

    activities.push({
      name: item.name || "Unnamed",
      action: action,
      server: item.server_name || item.server || "—",
      timestamp: timestamp,
      timeAgo: formatRelativeTime(now - timestamp),
      jobstate: item.jobstate || "unknown",
    });
  });

  // Most recent first
  activities.sort((a, b) => b.timestamp - a.timestamp);
  return activities.slice(0, max);
}

// ==================== INITIALIZE ALL ====================

export function initModals() {
  initSettingsListeners();
  initLoginModalListeners();
  initPricingModalListeners();
  initResyncButton();

  // Logged-out "Log in" tab
  document
    .getElementById("logged-out-login-tab")
    ?.addEventListener("click", (e) => {
      e.preventDefault();
      showLoginModal("");
    });
}

export function initSettingsListeners() {
  //document
  //  .getElementById("refresh-settings")
  //  ?.addEventListener("click", refreshSettings);

  document
    .getElementById("save-account")
    ?.addEventListener("click", saveAccount);
  document.getElementById("copy-token")?.addEventListener("click", copyToken);
  document
    .getElementById("view-plans-btn")
    ?.addEventListener("click", showPricingModal);
  document
    .getElementById("footer-pricing-link")
    ?.addEventListener("click", (e) => {
      e.preventDefault();
      showPricingModal();
    });

  // Regenerate Token - Direct Force Reconnect
  document
    .getElementById("regenerate-token")
    .addEventListener("click", function () {
      openConfirmModal(
        "Confirm Token Regeneration",
        "This will immediately invalidate your current API token. " +
          "All active MCP connections (including Grok) will stop working until they are updated with the new token. " +
          "Are you sure you want to continue?",
        () => {
          sendWS({ command: "new_token" });
        },
        () => showToast("Token regeneration cancelled", "info"),
      );
    });

  document.getElementById("rotate-exec-token").addEventListener("click", () => {
    openConfirmModal(
      "Rotate Execution Token?",
      "This will invalidate the current token for all remote servers. " +
        "Currently running jobs may lose the ability to report status. " +
        "Are you sure you want to continue?",
      () => {
        sendWS({ command: "rotate_execution_token" });
      },
      () => showToast("Rotate token cancelled", "info"),
    );
  });
}

// ==================== END OF FILE MARKER ====================
console.log("[ui-handlers] >>> FILE FULLY EXECUTED SUCCESSFULLY <<<");
// ==========================================================
