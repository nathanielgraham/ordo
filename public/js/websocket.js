import { appState, updateCollapsedClusters } from "./state.js";
//import { checkLoginAndConnect } from "./app.js";  

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
  renderUserProfile,
  renderOrgTeam,
  renderServersTable,
  renderCalendarsTable,
  loadDoc
} from './ui-handlers.js';

export function checkLoginAndConnect() {
  const token = document.cookie.match(/ordo_token=([^;]+)/)?.[1];
  if (token) {
    document.body.classList.add("is-logged-in");
    console.log("DEBUG: Logged IN");
    connectWS(token);
  } else {
    document.body.classList.remove("is-logged-in");
    console.log("DEBUG: Logged OUT");
  }
  //activateDefaultTab();
}

export function connectWS(token) {
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
      if (data.command_reply === "login_user" && data.success) {
        console.log("Login success - requesting initial loads");
        appState.ws.send(JSON.stringify({ command: "read_user" }));
        appState.ws.send(JSON.stringify({ command: "read_org" }));
        appState.ws.send(
          JSON.stringify({ command: "find_cluster", name: "/root" }),
        );
        appState.ws.send(JSON.stringify({ command: "find_cal" }));
        appState.ws.send(JSON.stringify({ command: "find_monitor" }));
      }
      if (data.command_reply === "read_user") updateAccount(data);
      if (data.command_reply === "read_org") updateOrgAndTeam(data);
      if (data.command_reply === "read_log") updateLog(data);

      if (data.command_reply === "find_log") updateLogHistory(data);
      if (data.command_reply === "find_cluster") updateJobsClusters(data);

      if (data.command_reply === "find_cal") updateCalendars(data);
      if (data.command_reply === "find_monitor") updateServers(data);
      if (data.broadcast === "clusters_changed") applyClusterBroadcast(data);
      if (data.broadcast === "jobs_changed") applyJobBroadcast(data);
      if (data.broadcast === "cals_changed") applyCalBroadcast(data);
      if (data.broadcast === "servers_changed") applyServerBroadcast(data);
      if (data.broadcast === "org_changed") updateOrgAndTeam(data);
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
