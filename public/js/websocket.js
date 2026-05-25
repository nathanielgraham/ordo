// websocket.js – WS connection + command helpers
import { appState } from "./state.js";
import {
  updateAccount,
  updateOrgAndTeam,
  updateLog,
  updateLogHistory,
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
  updateNextScheduledClusters,
  incrementDashboardStatsFromJob,
  getOverdueClustersListHTML,
  updateKPIBar,
  renderRecentActivityTable,
  getLongestRunningJobsHTML,
  getRecentlyFailedListHTML,
  handleCommandReply,
} from "./ui-handlers.js";

export function checkLoginAndConnect() {
  console.log("[WS Init] checkLoginAndConnect called");

  const token = document.cookie.match(/ordo_token=([^;]+)/)?.[1];

  if (token) {
    document.body.classList.add("is-logged-in");

    // If we already have an open connection, just re-auth it
    if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
      appState.ws.send(JSON.stringify({ command: "login_user", token }));
      //sendWS({ command: "login_user", token: token });
      //sendWS({ command: "delete_monitor", id: serverId })
    } else {
      connectWS(token);
    }
  } else {
    document.body.classList.remove("is-logged-in");
  }
}

export function connectWS(token) {
  console.log("[WS Init] connectWS called");

  // Extra safety: make sure we don't have a lingering connection
  if (window.ws) {
    console.log("[WS Init] Old WS still existed, clearing it");
    try {
      window.ws.close();
    } catch (e) {}
    window.ws = null;
  }

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
        appState.ws.send(
          JSON.stringify({
            command: "find_stats",
            since: Math.floor(
              new Date(new Date().setHours(0, 0, 0, 0)).getTime() / 1000,
            ),
          }),
        );
      }
      else if (data.command_reply === "login_user" &! data.success) {
        document.cookie = "ordo_token=; Path=/; Max-Age=0; SameSite=Strict";
        checkLoginAndConnect();
      }

      // ====================== CENTRAL COMMAND REPLY HANDLER ======================
      if (data.command_reply) {
        handleCommandReply(data);
      }

      // ====================== BROADCASTS ======================
      if (data.broadcast === "clusters_changed") {
        applyClusterBroadcast(data);
        if (
          document.getElementById("dashboard")?.classList.contains("active")
        ) {
          updateNextScheduledClusters();
          document.getElementById("dash-overdue-list").innerHTML =
            getOverdueClustersListHTML();
        }
      }

      if (data.broadcast === "jobs_changed") {
        applyJobBroadcast(data);
        if (data.updates && data.updates.length > 0) 
        {
          data.updates.forEach((job) => incrementDashboardStatsFromJob(job));
        }
        if (
          document.getElementById("dashboard")?.classList.contains("active")
        ) 
        {
          document.getElementById("dash-running-list").innerHTML =
            getLongestRunningJobsHTML(5);
          document.getElementById("dash-failed-list").innerHTML =
            getRecentlyFailedListHTML(5);
            renderRecentActivityTable();
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
