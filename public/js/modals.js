// modals.js – all modal open/close/save/interaction logic

import { appState } from "./state.js";
import { showToast } from "./ui-handlers.js"; // needs showToast 
import { getFullPath } from "./utils.js"; 

// Save entity (create/edit job/cluster)
document.getElementById("save-entity")?.addEventListener("click", () => {
  const name = document.getElementById("entity-name").value.trim();
  if (!name) {
    showToast("Name is required", "danger");
    return;
  }

  const isEdit = appState.currentEditItem !== null;
  const isJob =
    document.getElementById("entity-script-field").style.display !== "none";

  const payload = {
    command: isEdit
      ? isJob
        ? "update_job"
        : "update_cluster"
      : isJob
        ? "create_job"
        : "create_cluster",
    name,
  };

  if (isEdit) payload.id = appState.currentEditItem.id;
  else payload.parent_id = appState.currentParentId;

  if (isJob) {
    const script = document.getElementById("entity-script").value.trim();
    const server = document.getElementById("entity-server").value;
    if (!script || !server) {
      showToast("Script and Server are required for jobs", "danger");
      return;
    }
    payload.script = script;
    payload.server = server;

    const retrys = document.getElementById("entity-retrys").value;
    if (retrys) payload.retrys = Number(retrys);

    const delay = document.getElementById("entity-delay").value;
    if (delay) payload.delay = Number(delay);
  }

  const description = document
    .getElementById("entity-description")
    .value.trim();
  if (description) payload.description = description;

  const loops = document.getElementById("entity-loops").value;
  if (loops) payload.loops = Number(loops);

  // Dependencies
  const needsSelect = document.getElementById("entity-needs");
  const needsIds = Array.from(needsSelect.selectedOptions)
    .map((opt) => Number(opt.value))
    .filter((id) => id > 0);
  if (
    needsIds.length > 0 ||
    needsSelect.querySelector('option[value=""]').selected
  ) {
    payload.needs_ids = needsIds.length > 0 ? needsIds : [];
  }

  const needsAnySelect = document.getElementById("entity-needs-any");
  const needsAnyIds = Array.from(needsAnySelect.selectedOptions)
    .map((opt) => Number(opt.value))
    .filter((id) => id > 0);
  if (
    needsAnyIds.length > 0 ||
    needsAnySelect.querySelector('option[value=""]').selected
  ) {
    payload.needs_any_ids = needsAnyIds.length > 0 ? needsAnyIds : [];
  }

  const onFailSelect = document.getElementById("entity-on-fail");
  const onFailId = onFailSelect.value;
  if (onFailId) {
    payload.on_fail_id = Number(onFailId);
  } else if (onFailSelect.querySelector('option[value=""]').selected) {
    payload.on_fail_id = null;
  }

  if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify(payload));
    showToast(isEdit ? "Update sent" : "Creation requested", "info");
  } else {
    showToast("Not connected", "danger");
  }

  document.getElementById("entity-modal").classList.remove("is-active");
});

// Save attach calendar
document.getElementById("save-attach-cal")?.addEventListener("click", () => {
  const calId = document.getElementById("attach-cal-select").value;
  const payload = {
    command: "update_cluster",
    id: appState.currentAttachClusterId,
    cal_id: calId ? Number(calId) : null,
  };

  if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify(payload));
    showToast("Calendar updated", "info");
  } else {
    showToast("Not connected", "danger");
  }

  document.getElementById("attach-cal-modal").classList.remove("is-active");
});

// Log modal buttons
document.getElementById("close-log")?.addEventListener("click", () => {
  document.getElementById("log-modal").classList.remove("is-active");
});

document.getElementById("refresh-log")?.addEventListener("click", () => {
  const jobId = document.getElementById("log-modal").dataset.jobId;
  if (jobId && appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify({ command: "read_log", id: jobId }));
  }
});

document.getElementById("view-history")?.addEventListener("click", () => {
  const jobId = document.getElementById("log-modal").dataset.jobId;
  if (jobId && appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify({ command: "find_log", id: jobId }));
    document.getElementById("log-history-modal").classList.add("is-active");
  }
});

document.getElementById("close-log-history")?.addEventListener("click", () => {
  document.getElementById("log-history-modal").classList.remove("is-active");
});

// Invite team modal
document.getElementById("invite-team")?.addEventListener("click", () => {
  document.getElementById("invite-modal").classList.add("is-active");
  document.getElementById("invite-email").value = "";
});

document.getElementById("cancel-invite")?.addEventListener("click", () => {
  document.getElementById("invite-modal").classList.remove("is-active");
});

document.getElementById("close-invite")?.addEventListener("click", () => {
  document.getElementById("invite-modal").classList.remove("is-active");
});

document.getElementById("send-invite")?.addEventListener("click", () => {
  const email = document.getElementById("invite-email").value.trim();
  if (!email) {
    showToast("Enter email", "danger");
    return;
  }

  if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(
      JSON.stringify({
        command: "register_user",
        email,
        team_member: "1",
      }),
    );
    showToast("Invitation sent", "success");
    document.getElementById("invite-modal").classList.remove("is-active");
  } else {
    showToast("Not connected", "danger");
  }
});

// Global cancel button handler (for all cancel buttons in modals)
document.addEventListener("click", (e) => {
  const cancelBtn = e.target.closest(
    '[id^="cancel-"], .button[data-action="cancel"]',
  );
  if (cancelBtn) {
    const modal = cancelBtn.closest(".modal");
    if (modal) {
      modal.classList.remove("is-active");
    }
  }
});

function populateDependencySelects(selectId, selectedIds = [], includeNone = true) {
  const select = document.getElementById(selectId);
  select.innerHTML = "";

  if (includeNone) {
    const noneOpt = document.createElement("option");
    noneOpt.value = "";
    noneOpt.textContent = "None";
    select.appendChild(noneOpt);
  }

  console.log(`[DEBUG] populateDependencySelects called for ${selectId}`);
  console.log(`[DEBUG] selectedIds:`, selectedIds);
  console.log(`[DEBUG] appState.monitorData.tree:`, appState.monitorData.tree);

  function addClusters(items) {
    console.log(`[DEBUG] addClusters called with items:`, items);
    console.log(`[DEBUG] items is array?`, Array.isArray(items));

    if (!Array.isArray(items)) {
      console.warn("[DEBUG] addClusters: items is NOT an array - skipping");
      return;
    }

    items.forEach((item) => {
      if (item.is_cluster) {
        if (appState.currentEditItem && Number(item.id) === Number(appState.currentEditItem.id)) return;
        console.log(`[DEBUG] Adding cluster option for id:`, item.id, "name:", item.name);
        const opt = document.createElement("option");
        opt.value = item.id;
        opt.textContent = getFullPath(item);
        if (selectedIds.includes(Number(item.id))) opt.selected = true;
        select.appendChild(opt);
        if (item.children) {
          console.log(`[DEBUG] Recursing into children of cluster ${item.id}`);
          addClusters(item.children);
        }
      }
    });
  }

  addClusters(appState.monitorData.tree || []);
}

export function openAttachCalendarModal(
  clusterId,
  clusterName,
  currentCalName = "",
  currentCalId = null,
) {
  appState.currentAttachClusterId = clusterId;
  document.getElementById("attach-target-name").textContent = clusterName;
  document.getElementById("attach-current-cal").textContent =
    currentCalName || "None";

  const select = document.getElementById("attach-cal-select");
  select.innerHTML = '<option value="">None (run manually only)</option>';
  appState.calendarsData.forEach((cal) => {
    const opt = document.createElement("option");
    opt.value = cal.id;
    opt.textContent = cal.name;
    if (Number(cal.id) === Number(currentCalId)) opt.selected = true;
    select.appendChild(opt);
  });

  document.getElementById("attach-cal-modal").classList.add("is-active");
}

export function openEntityModal(
  mode = "create",
  type = "job",
  item = null,
  parentId = null,
  parentName = null,
) {
  appState.currentEditItem = item;
  appState.currentParentId = parentId;
  appState.currentParentName = parentName;

  const isEdit = mode === "edit";
  const isJob = type === "job";

  document.getElementById("entity-modal-title").textContent = isEdit
    ? `Edit ${isJob ? "Job" : "Cluster"}`
    : `New ${isJob ? "Job" : "Cluster"}`;

  const contextEl = document.getElementById("entity-context");
  if (isEdit) contextEl.textContent = `ID: ${item.id}`;
  else if (parentName) contextEl.textContent = `In cluster: ${parentName}`;
  else contextEl.textContent = "In root";

  document.getElementById("entity-script-field").style.display = isJob
    ? "block"
    : "none";
  document.getElementById("entity-server-field").style.display = isJob
    ? "block"
    : "none";
  document.getElementById("entity-retrys-field").style.display = isJob
    ? "block"
    : "none";
  document.getElementById("entity-delay-field").style.display = isJob
    ? "block"
    : "none";

  if (isEdit && item) {
    document.getElementById("entity-name").value = item.name || "";
    document.getElementById("entity-description").value =
      item.description || "";
    document.getElementById("entity-script").value = item.script || "";
    document.getElementById("entity-server").value = item.server_name || "";
    document.getElementById("entity-loops").value = item.loops ?? 0;
    document.getElementById("entity-retrys").value = item.retrys ?? 0;
    document.getElementById("entity-delay").value = item.delay ?? 0;

    populateDependencySelects("entity-needs", item.needs_ids || [], true);
    populateDependencySelects(
      "entity-needs-any",
      item.needs_any_ids || [],
      true,
    );
    populateDependencySelects(
      "entity-on-fail",
      item.on_fail_id ? [item.on_fail_id] : [],
      true,
    );
  } else {
    document.getElementById("entity-name").value = isJob
      ? "new-job"
      : "new-cluster";
    document.getElementById("entity-description").value = "";
    document.getElementById("entity-script").value = "";
    document.getElementById("entity-loops").value = "0";
    document.getElementById("entity-retrys").value = "0";
    document.getElementById("entity-delay").value = "0";

    populateDependencySelects("entity-needs", [], true);
    populateDependencySelects("entity-needs-any", [], true);
    populateDependencySelects("entity-on-fail", [], true);
  }

  const serverSelect = document.getElementById("entity-server");
  serverSelect.innerHTML = "";
  appState.serversData.forEach((s) => {
    const opt = document.createElement("option");
    opt.value = s.name;
    opt.textContent = s.name;
    if (!isEdit && appState.serversData[0]) opt.selected = true;
    if (isEdit && s.name === item.server_name) opt.selected = true;
    serverSelect.appendChild(opt);
  });

  document.getElementById("entity-modal").classList.add("is-active");
}

  // Copy token
  document.getElementById("copy-token").addEventListener("click", () => {
    const tokenInput = document.getElementById("account-token");
    if (!tokenInput.value) {
      showToast("No token to copy", "warning");
      return;
    }
    tokenInput.select();
    tokenInput.setSelectionRange(0, 99999);
    try {
      document.execCommand("copy");
      showToast("Token copied!", "success");
    } catch (err) {
      showToast("Failed to copy", "danger");
    }
  });

  // Save profile
  document.getElementById("save-profile").addEventListener("click", () => {
    const name = document.getElementById("edit-name").value.trim();
    const mode = document.getElementById("edit-mode").value.trim();
    if (!name && !mode) {
      showToast("No changes", "info");
      return;
    }
    if (ws && appState.ws.readyState === WebSocket.OPEN) {
      appState.ws.send(
        JSON.stringify({
          command: "update_user",
          name: name || undefined,
          mode: mode || undefined,
        }),
      );
      showToast("Profile update requested", "info");
    } else {
      showToast("Not connected", "danger");
    }
  });

  // Save org
  document.getElementById("save-org").addEventListener("click", () => {
    const payload = { command: "update_org" };
    const name = document.getElementById("edit-org-name").value.trim();
    const desc = document.getElementById("edit-org-desc").value.trim();
    if (name) payload.name = name;
    if (desc) payload.description = desc;
    if (Object.keys(payload).length === 1) {
      showToast("No changes", "info");
      return;
    }
    if (ws && appState.ws.readyState === WebSocket.OPEN) {
      appState.ws.send(JSON.stringify(payload));
      showToast("Organization update requested", "info");
    } else {
      showToast("Not connected", "danger");
    }
  });

