// websocket.js – WS connection + command helpers
import { appState } from "./state.js";
import {
  updateAccount,
  updateOrgAndTeam,
  updateLog,
  updateLogHistory,
  updateJobsClusters,
  updateCalendars,
  updateServers,
  applyClusterBroadcast,
  applyJobBroadcast,
  applyCalBroadcast,
  applyServerBroadcast,
  showToast,
  renderDashboard,
  loadDashboardStats,
  updateDashboardCountersFromBroadcast,
  updateDashboardFromBroadcast,
  updateKPIBar,
} from "./ui-handlers.js";

export function checkLoginAndConnect() {
  console.log("[WS Init] checkLoginAndConnect called");

  const token = document.cookie.match(/ordo_token=([^;]+)/)?.[1];
  if (token) {
    console.log("[WS Init] Token found → connecting");
    document.body.classList.add("is-logged-in");
    connectWS(token);
  } else {
    console.log("[WS Init] No token found");
    document.body.classList.remove("is-logged-in");
  }
}

export function connectWS(token) {
  console.log("[WS Init] connectWS called");

  if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    console.log("[WS Init] WebSocket already open, skipping");
    return;
  }

  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  appState.ws = new WebSocket(`${proto}//${location.host}/websocket`);

  appState.ws.addEventListener("open", () => {
    console.log("WS connected");
    appState.ws.send(JSON.stringify({ command: "login_user", token }));
  });

  appState.ws.onmessage = (e) => {
    console.log("WS message:", e.data);
    try {
      const data = JSON.parse(e.data);

      // ====================== LOGIN & INITIAL LOADS ======================

      if (data.command_reply === "login_user" && data.success) {
        console.log("Login success - requesting initial loads");

        appState.ws.send(JSON.stringify({ command: "read_user" }));
        appState.ws.send(JSON.stringify({ command: "read_org" }));
        appState.ws.send(
          JSON.stringify({ command: "find_cluster", name: "/root" }),
        );
        appState.ws.send(JSON.stringify({ command: "find_cal" }));
        appState.ws.send(JSON.stringify({ command: "find_monitor" }));

        // ADD THIS LINE:
        appState.ws.send(
          JSON.stringify({
            command: "find_stats",
            since: Math.floor(
              new Date(new Date().setHours(0, 0, 0, 0)).getTime() / 1000,
            ),
          }),
        );
      }

      // ====================== DIRECT COMMAND REPLIES ======================
      if (data.command_reply === "read_user") updateAccount(data);
      if (data.command_reply === "read_org") updateOrgAndTeam(data);
      if (data.command_reply === "read_log") updateLog(data);
      if (data.command_reply === "find_log") updateLogHistory(data);
      if (data.command_reply === "find_cluster") updateJobsClusters(data);
      if (data.command_reply === "find_cal") updateCalendars(data);
      if (data.command_reply === "find_monitor") updateServers(data);

      if (data.command_reply === "sync") {
        // Reset button
        const btn = document.getElementById("resync-all-btn");
        if (btn) {
          btn.disabled = false;
          btn.innerHTML = '<i class="fas fa-sync-alt"></i> Resync';
        }

        // Update zombies count if returned
        if (data.zombie_count !== undefined) {
          const zombiesEl = document.getElementById("kpi-zombies");
          if (zombiesEl) zombiesEl.textContent = data.zombie_count;
        }

        // The toast will be shown automatically by your existing code
      }

      // ====================== STATS ======================
      if (data.command_reply === "find_stats") {
        console.log("[find_stats] Reply received:", data);
        appState.dashboardStats = data;

        if (
          document.getElementById("dashboard")?.classList.contains("active")
        ) {
          updateKPIBar(data);
        }
      }

      // ====================== BROADCASTS ======================
      if (data.broadcast === "clusters_changed") {
        applyClusterBroadcast(data);
        // Only light refresh for clusters (no counter increment)
        if (
          document.getElementById("dashboard")?.classList.contains("active")
        ) {
          renderDashboard();
        }
      }

      if (data.broadcast === "jobs_changed") {
        applyJobBroadcast(data);

        if (data.updates && data.updates.length > 0) {
          updateDashboardCountersFromBroadcast(data.updates);
        }

        if (
          document.getElementById("dashboard")?.classList.contains("active")
        ) {
          renderDashboard();
        }
      }

      if (data.broadcast === "cals_changed") applyCalBroadcast(data);
      if (data.broadcast === "servers_changed") applyServerBroadcast(data);
      if (data.broadcast === "org_changed") updateOrgAndTeam(data);

      // ====================== TOASTS ======================
      if (data.command_reply && data.message) {
        showToast(data.message, data.success ? "success" : "danger");
      }
    } catch (err) {
      console.error("Parse error:", err);
    }
  };

  appState.ws.onclose = () => {
    console.log("WS closed");
    showToast("Disconnected", "danger");
    setTimeout(checkLoginAndConnect, 5000);
  };
}

export function sendWS(payload) {
  console.log("[sendWS] Called with command:", payload.command);

  if (appState.ws?.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify(payload));
  } else {
    console.warn("[sendWS] Not connected - showing toast");
    showToast("Not connected", "danger");
  }
}

// Convenience wrapper for common commands (used by UI actions)
export function sendCommand(action, id, type = "cluster") {
  let command;
  switch (action) {
    case "run":
      command = `start_${type}`;
      break;
    case "kill":
      command = `kill_${type}`;
      break;
    case "hold":
      command = `hold_${type}`;
      break;
    case "release":
      command = `release_${type}`;
      break;
    case "ice":
      command = `ice_${type}`;
      break;
    case "melt":
      command = `melt_${type}`;
      break;
    case "complete":
      command = `complete_${type}`;
      break;
    case "reset":
      command = `reset_${type}`;
      break;
    case "delete":
      command = `delete_${type}`;
      break;
    default:
      console.warn("Unknown command action:", action);
      return;
  }

  sendWS({ command, id });
}
