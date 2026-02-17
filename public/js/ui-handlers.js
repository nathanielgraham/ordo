// ui-handlers.js
import { appState, updateCollapsedClusters, updateCalendarCollapsed } from "./state.js";
import { renderJobsTable } from "./tree/tree-table.js";
import { openCronsModal } from "./modals.js";
import { updateRow, insertRow, removeRow, updateLiveTimings } from "./tree/tree-table.js";

import {
  formatDate,
  formatDuration,
  formatUptime,
  formatRelativeTime,
  buildTree,
  findClusterById,
  findJobById,
  getFullPath,
  removeJobById,
  removeClusterById,
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
  const updateTime = server.update_time != null ? Number(server.update_time) : null;
  const updatedAgo = updateTime != null && !isNaN(updateTime) ? now - updateTime : Infinity;

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
  const noServers = document.getElementById("no-servers");
  tbody.innerHTML = "";
  if (appState.serversData.length === 0) {
    noServers.style.display = "block";
    return;
  }
  noServers.style.display = "none";

  const now = Math.floor(Date.now() / 1000);
  appState.serversData.forEach(server => {

    const updateTime = server.update_time != null ? Number(server.update_time) : null;
    const updatedAgo = updateTime != null && !isNaN(updateTime) ? now - updateTime : Infinity;
    let relTime = "—";
    if (Number.isFinite(updatedAgo)) {
      relTime = formatRelativeTime(updatedAgo);
    }

    // Load Avg
    const load1 = server.load_1 != null ? server.load_1.toFixed(2) : "—";
    const coresText = server.cores != null ? ` (on ${server.cores} cores)` : "";
    const loadTooltip = server.load_1 != null
      ? `1-min: ${server.load_1.toFixed(2)}${coresText}\n5-min: ${server.load_5?.toFixed(2) ?? "—"}\n15-min: ${server.load_15?.toFixed(2) ?? "—"}`
      : "Load averages not available";

    // CPU %
    const cpu = server.cpu_percent != null ? `${server.cpu_percent.toFixed(1)}%` : "—";
    const cpuTooltip = "True CPU utilization (user + system) from top snapshot";

    // Memory + Swap (smart units)
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

      const swapPct = server.total_swap != null && server.total_swap > 0
        ? ((server.used_swap || 0) / server.total_swap * 100).toFixed(1) + "%"
        : "—";
      memTooltip = `RAM: ${memPct}% (${usedDisplay}/${totalDisplay} ${unit})\nSwap: ${swapPct}`;
    }

    // Disk + Root (smart units)
    let disk = "—";
    let diskTooltip = "Disk usage not available";

    if (server.total_disk != null && server.total_disk > 0) {
      const usedBytes = server.used_disk != null ? server.used_disk : 0;
      const totalBytes = server.total_disk;

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
      const diskPct = isNaN(pct) ? "—" : pct.toFixed(1);

      disk = `${diskPct}% (${usedDisplay}/${totalDisplay} ${unit})`;

      const rootPct = server.root_total_disk != null && server.root_total_disk > 0
        ? ((server.root_used_disk || 0) / server.root_total_disk * 100).toFixed(1) + "%"
        : "—";
      diskTooltip = `Aggregate: ${diskPct}% (${usedDisplay}/${totalDisplay} ${unit})\nRoot: ${rootPct}`;
    }

    // Uptime
    const uptime = server.uptime != null ? formatUptime(server.uptime) : "—";

    // Host tooltip with Port + static info + Ping
    const pingText = server.ping != null ? server.ping.toFixed(3) + "s" : "—";
    const hostTooltip = [
      `Host: ${server.host || server.ip_address || "—"}`,
      `Port: ${server.port || "—"}`,
      `Ping: ${pingText}`,
      `OS: ${server.os || "—"}`,
      `CWD: ${server.cwd || "—"}`,
      `Home: ${server.home || "—"}`
    ].filter(Boolean).join("\n");

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
            <button class="btn btn-sm btn-ghost" aria-haspopup="menu">
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

    // Initial freshness update using central function
    updateFreshnessCell(tr, server, now);
  });
}

export function updateAccount(data) {
  appState.accountData = data;
  hideLoading("account-loading");
  document.getElementById("account-content").style.display = "block";
  renderUserProfile();
}

export function renderUserProfile() {
  if (!appState.accountData || !appState.accountData.success) return;
  document.getElementById("account-email").textContent =
    appState.accountData.email || "—";
  document.getElementById("account-id").textContent =
    appState.accountData.id || "—";
  document.getElementById("account-level").textContent =
    appState.accountData.level || "—";
  document.getElementById("edit-name").value = appState.accountData.name || "";
  document.getElementById("edit-mode").value = appState.accountData.mode || "";
  document.getElementById("account-creation").textContent =
    formatDate(appState.accountData.creation_time) || "—";
  document.getElementById("account-update").textContent =
    formatDate(appState.accountData.update_time) || "—";
  document.getElementById("account-remote").textContent =
    appState.accountData.remote_address || "—";
  document.getElementById("account-token").value =
    appState.accountData.token || "—";
}

export function updateOrgAndTeam(data) {
  appState.orgData = data;
  renderOrgTeam();
  hideLoading("account-loading");
  document.getElementById("account-content").style.display = "block";
}

export function renderOrgTeam() {
  if (!appState.orgData) return;
  document.getElementById("org-id").textContent = appState.orgData.id || "—";
  document.getElementById("edit-org-name").value = appState.orgData.name || "";
  document.getElementById("edit-org-desc").value =
    appState.orgData.description || "";
  document.getElementById("org-creation").textContent =
    formatDate(appState.orgData.creation_time) || "—";

  const teamBody = document.getElementById("team-body");
  teamBody.innerHTML = "";
  if (appState.orgData.members?.length) {
    appState.orgData.members.forEach((member) => {
      const row = document.createElement("tr");
      row.innerHTML = `
          <td>${member.email || "—"}</td>
          <td>${member.id || "—"}</td>
          <td>${member.level || "—"}</td>
          <td>${formatDate(member.creation_time) || "—"}</td>
        `;
      teamBody.appendChild(row);
    });
    document.getElementById("no-team").style.display = "none";
  } else {
    document.getElementById("no-team").style.display = "block";
  }
}

/*
export function updateLog(data) {
  document.getElementById("log-content").textContent = data.out;
  const jobId = data.job_id;
  const runId = data.id || "unknown";
  document.querySelector("#log-modal .modal-title").textContent =
    `Job ${jobId} (Run ${runId})`;
}
*/

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
  const tbody = document.getElementById("log-history-body");
  const noHistory = document.getElementById("no-history");
  tbody.innerHTML = "";
  if (!data.logs || data.logs.length === 0) {
    noHistory.style.display = "block";
    return;
  }
  noHistory.style.display = "none";
  data.logs.forEach((log) => {
    const row = document.createElement("tr");
    row.style.cursor = "pointer";
    row.innerHTML = `
        <td>${log.id}</td>
        <td>${formatDate(log.started) || "—"}</td>
        <td>${formatDuration(log.started, log.ended) || "—"}</td>
        <td>${log.exit_code === 0 ? "Success" : (log.exit_code ?? "—")}</td>
      `;
    row.addEventListener("click", () => {
      const jobId = document.getElementById("log-modal").dataset.jobId;
      appState.ws.send(
        JSON.stringify({
          command: "read_log",
          id: jobId,
          log_id: log.id,
        }),
      );
      document.getElementById("log-history-modal").classList.remove("active");
      //document.querySelector("#log-modal .modal-title").textContent = `Run: ${id} (Job ID: ${id})`;
    });
    tbody.appendChild(row);
  });
}

/*
export function updateJobsClusters(data) {
  hideLoading("monitor-loading");
  document.getElementById("monitor-content").style.display = "block";
  if (data.success) {
    appState.monitorData.tree = buildTree(data);
    renderJobsTable();
  }
}
*/

export function updateJobsClusters(data) {
  hideLoading("monitor-loading");
  document.getElementById("monitor-content").style.display = "block";

  if (data.success) {
    appState.monitorData.tree = buildTree(data);

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
  document.getElementById("calendars-content").style.display = "block";
  if (data.success) {
    appState.calendarsData = data.cals || [];
    renderCalendarsTable();
  }
}

export function toggleCronsRow(calendarId) {
  console.log("[DEBUG] toggleCronsRow START – calendarId:", calendarId);

  const cronsRow = document.querySelector(
    `tr[data-cal-id="${calendarId}"].crons-row`,
  );
  if (!cronsRow) {
    console.warn("[DEBUG] CRONS ROW NOT FOUND – calendarId:", calendarId);
    return;
  }

  console.log(
    "[DEBUG] Found row – current classes:",
    cronsRow.className,
    "inline display:",
    cronsRow.style.display,
  );

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
  console.log(
    "[DEBUG] Toggled – was hidden:",
    wasHidden,
    "now hidden:",
    isNowHidden,
    "final display:",
    cronsRow.style.display,
  );

  const toggleBtn = document.querySelector(
    `.dropdown-item[data-action="view-crons"][data-id="${calendarId}"]`,
  );
  if (toggleBtn) {
    toggleBtn.textContent = isNowHidden ? "View Crons" : "Hide Crons";
    console.log("[DEBUG] Button text updated to:", toggleBtn.textContent);
  } else {
    console.warn("[DEBUG] Toggle button not found for calendarId:", calendarId);
  }
}

export function renderCalendarsTable() {
  const tbody = document.getElementById("calendars-body");
  if (!tbody) return;
  tbody.innerHTML = "";

  appState.calendarsData.forEach((cal) => {
    const hasCrons = cal.crons && cal.crons.length > 0;
    const isCollapsed = appState.collapsedCalendars.has(String(cal.id));

    // === Calendar row ===
    const calRow = document.createElement("tr");
    calRow.className = "ordo-calendar-row";
    calRow.dataset.id = cal.id;
    calRow.dataset.depth = 0;
    calRow.dataset.parent = "";
    calRow.style.setProperty("--depth", 0);

    const toggleHtml = hasCrons
      ? `<span class="ordo-toggle${!hasCrons ? " empty" : ""}"></span>`
      : `<span class="ordo-toggle empty"></span>`;
    const icon = '<i class="fas fa-folder mr-2 has-text-info"></i>';

    calRow.innerHTML = `
      <td>${toggleHtml}${icon}${cal.name || "—"}</td>
      <td>${cal.tz || "—"}</td>
      <td>${cal.description || "—"}</td>
      <td>${cal.crons?.length || 0}</td>
      <td>${cal.cluster_ids?.length || 0}</td>
      <td>—</td>
      <td>—</td>
      <td>—</td>
      <td>${generateCalendarActions(cal.id, hasCrons)}</td>
    `;

    if (isCollapsed) {
      calRow.classList.add("collapsed");
      calRow.setAttribute("aria-expanded", "false");
    } else {
      calRow.setAttribute("aria-expanded", hasCrons ? "true" : "false");
    }

    tbody.appendChild(calRow);

    // === Always render cron rows (if any) ===
    if (hasCrons) {
      (cal.crons || []).forEach((cron) => {
        const cronRow = document.createElement("tr");
        cronRow.className = "ordo-cron-row";
        if (isCollapsed) cronRow.classList.add("hidden"); // hide if parent collapsed
        cronRow.dataset.id = `cron-${cal.id}-${cron.id}`;
        cronRow.dataset.depth = 1;
        cronRow.dataset.parent = cal.id;
        cronRow.style.setProperty("--depth", 1);

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
  document.getElementById("servers-content").style.display = "block";
  if (data.success) {
    appState.serversData = data.servers || [];
    renderServersTable();
  }
}

export function applyServerBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      const idx = appState.serversData.findIndex((s) => s.id === update.id);
      if (idx !== -1)
        appState.serversData[idx] = { ...appState.serversData[idx], ...update };
      else appState.serversData.push(update);
    });
  }
  if (data.deletes) {
    data.deletes.forEach((del) => {
      appState.serversData = appState.serversData.filter(
        (s) => s.id !== (del.id || del),
      );
    });
  }
  renderServersTable();
}

export function applyClusterBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);
      const rowId = `row-cluster-${id}`;
      const existingRow = document.getElementById(rowId);

      if (existingRow) {
        // Update existing row
        updateRow(existingRow, { ...update, is_cluster: true });
      } else {
        // Insert new cluster row
        const parentId = update.parent_id || null;
        insertRow({ ...update, is_cluster: true }, parentId);
      }

      // Handle nested jobs if included in update
      if (update.jobs && Array.isArray(update.jobs)) {
        update.jobs.forEach((jobUpdate) => {
          const jobId = Number(jobUpdate.id);
          const jobRowId = `row-job-${jobId}`;
          const jobRow = document.getElementById(jobRowId);

          if (jobRow) {
            updateRow(jobRow, { ...jobUpdate, is_cluster: false });
          } else {
            // Insert new job under this cluster
            insertRow({ ...jobUpdate, is_cluster: false }, id);
          }
        });
      }
    });
  }

  if (data.deletes) {
    const uniqueDeletes = [...new Set(data.deletes.map((d) => Number(d.id || d)))];
    uniqueDeletes.forEach((id) => removeClusterById(appState.monitorData.tree, id));
    // Also remove rows
    uniqueDeletes.forEach((id) => {
      const row = document.getElementById(`row-cluster-${id}`);
      if (row) row.remove();
    });
  }

  // Optional: re-apply timings if needed
  updateLiveTimings();
}

export function applyJobBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);
      const rowId = `row-job-${id}`;
      const existingRow = document.getElementById(rowId);
      if (existingRow) {
        updateRow(existingRow, update);
      } else {
        const parentId = update.cluster_id || null;
        insertRow(update, parentId);
      }
    });
  }
  if (data.deletes) {
    data.deletes.forEach((del) => {
      removeRow(Number(del.id || del), false);
    });
  }
}

// Similar for applyClusterBroadcast (use row-cluster- prefix)


export function applyCalBroadcast(data) {
  console.log(
    "[DEBUG] applyCalBroadcast received:",
    JSON.stringify(data, null, 2),
  );

  // Log current state before update
  console.log(
    "[DEBUG] Before update – calendars count:",
    appState.calendarsData.length,
  );
  appState.calendarsData.forEach((cal) => {
    console.log(
      `[DEBUG] Cal ${cal.id} (${cal.name}) has ${cal.crons?.length || 0} crons before update`,
    );
  });

  // Handle updates – FULL REPLACE
  if (data.updates && Array.isArray(data.updates)) {
    data.updates.forEach((update) => {
      const updateId = Number(update.id);
      if (isNaN(updateId)) {
        console.warn("[DEBUG] Invalid calendar ID in update:", update);
        return;
      }

      const index = appState.calendarsData.findIndex(
        (cal) => Number(cal.id) === updateId,
      );

      if (index !== -1) {
        const oldCrons = appState.calendarsData[index].crons?.length || 0;
        console.log(
          `[DEBUG] Replacing cal ${updateId} – old crons: ${oldCrons}, new crons: ${update.crons?.length || 0}`,
        );
        appState.calendarsData[index] = {
          ...update,
          id: updateId,
          crons: update.crons || [], // force empty array
        };
      } else {
        console.log(`[DEBUG] Adding new cal ${updateId}`);
        appState.calendarsData.push({
          ...update,
          id: updateId,
          crons: update.crons || [],
        });
      }
    });
  }

  // Handle deletes
  if (data.deletes && Array.isArray(data.deletes)) {
    const deleteIds = data.deletes
      .map((d) => Number(d.id || d))
      .filter((id) => !isNaN(id));
    const uniqueDeletes = [...new Set(deleteIds)];

    uniqueDeletes.forEach((id) => {
      const index = appState.calendarsData.findIndex(
        (cal) => Number(cal.id) === id,
      );
      if (index !== -1) {
        console.log(`[DEBUG] Deleting calendar ${id}`);
        appState.calendarsData.splice(index, 1);
      }
    });
  }

  // Log state after update
  console.log(
    "[DEBUG] After update – calendars count:",
    appState.calendarsData.length,
  );
  appState.calendarsData.forEach((cal) => {
    console.log(
      `[DEBUG] Cal ${cal.id} (${cal.name}) has ${cal.crons?.length || 0} crons after update`,
    );
  });

  renderCalendarsTable();

  // Refresh open crons modal if affected
  const cronsModal = document.getElementById("crons-modal");
  if (cronsModal?.classList.contains("active")) {
    const openCalId = Number(cronsModal.dataset.calId);
    const wasAffected =
      data.updates?.some((u) => Number(u.id) === openCalId) ||
      data.deletes?.some((d) => Number(d.id || d) === openCalId);

    if (wasAffected) {
      console.log("[DEBUG] Refreshing open crons modal for calId:", openCalId);
      cronsModal.classList.remove("active");
      setTimeout(() => {
        console.log("[DEBUG] Re-opening crons modal after delay");
        openCronsModal(openCalId);
      }, 800);
    } else {
      console.log("[DEBUG] No refresh needed – open modal not affected");
    }
  }

  showToast("Calendars updated", "info");
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
    if (!row || !row.classList.contains("ordo-calendar-row")) return;

    const calId = row.dataset.id;
    const isNowCollapsed = row.classList.toggle("collapsed");

    // Persist
    if (isNowCollapsed) {
      appState.collapsedCalendars.add(calId);
    } else {
      appState.collapsedCalendars.delete(calId);
    }
    updateCalendarCollapsed();

    // Show/hide children using .hidden
    document.querySelectorAll(`tr[data-parent="${calId}"]`).forEach((child) => {
      child.classList.toggle("hidden", isNowCollapsed);
    });

    row.setAttribute("aria-expanded", (!isNowCollapsed && row.querySelector(".ordo-toggle:not(.empty)")).toString());
  });
}
