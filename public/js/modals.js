// modals.js
import { appState } from "./state.js";
import { openDependencyGraph } from "./graph.js";
import {
  showToast,
  renderCalendarsTable,
  showLogHistoryModal,
  initModalTomSelect,
} from "./ui-handlers.js";
import { sendWS } from "./websocket.js";
import {
  getFullPath,
  findClusterById,
  findJobById,
  commonTimezones,
  formatDate,
} from "./utils.js";

// ==================== TOM SELECT HELPERS ====================
// Helper to get values from TomSelect multi-selects
function TomSelectGetValues(selectId) {
  const el = document.getElementById(selectId);
  if (!el || !el.tomselect) {
    console.warn(
      `[TomSelectGetValues] Element ${selectId} or TomSelect not found`,
    );
    return [];
  }
  const value = el.tomselect.getValue();
  if (!value) return [];
  return String(value)
    .split(",")
    .filter(Boolean)
    .map((id) => Number(id.trim()));
}

// ==================== SHARED HELPERS ====================
function resetAllModals() {
  document.querySelectorAll(".app-modal").forEach((modal) => {
    modal.classList.remove("active");
  });

  // Reset form fields
  [
    "job-name",
    // "job-description",
    "job-script",
    "job-loops",
    "job-retrys",
    "job-delay",
    "cluster-name",
    //"cluster-description",
    "cluster-loops",
    //"cluster-clonable",
    "attach-cal-select",
    "calendar-name",
    "calendar-tz",
    "calendar-tz-custom",
    "calendar-description",
    "cron-expression",
    "cron-description",
    "cron-begin",
    "cron-expire",
  ].forEach((id) => {
    const el = document.getElementById(id);
    if (el) {
      if (el.type === "checkbox") el.checked = false;
      else if (el.type === "number") el.value = "0";
      else if (el.tagName === "SELECT") el.value = "";
      else el.value = "";
    }
  });

  // Destroy Tom Select instances
  [
    "job-needs",
    "job-needs-any",
    "job-on-fail",
    "job-server",
    "cluster-needs",
    "cluster-needs-any",
    "cluster-on-fail",
    "cluster-on-overdue",
    "attach-cal-select",
  ].forEach((id) => {
    const sel = document.getElementById(id);
    if (sel?.tomselect) {
      sel.tomselect.destroy();
      sel.tomselect = null;
    }
  });
}

// ==================== JOB MODAL ====================
export function openJobModal(
  mode = "create",
  itemId = null,
  parentId = null,
  parentName = null,
) {
  const modal = document.getElementById("job-modal");
  if (!modal) return;
  let item = null;
  const numericId = Number(itemId);
  if (mode === "edit" && numericId) {
    item =
      appState.jobsMap.get(numericId) ||
      findJobById(appState.monitorData.tree, numericId);
  }
  const isEdit = mode === "edit" && item !== null;
  const currentClusterId = item?.cluster_id || parentId;
  modal.dataset.editId = isEdit ? String(numericId) : "";
  modal.dataset.parentId = parentId || "";
  // Title & Context
  document.getElementById("job-modal-title").textContent = isEdit
    ? "Edit Job"
    : "New Job";
  document.getElementById("job-context").textContent = isEdit
    ? `Editing: ${item?.name || "—"}`
    : parentName
      ? `In cluster: ${parentName}`
      : "In root";
  // Basic fields
  document.getElementById("job-name").value = isEdit ? item?.name || "" : "";
  document.getElementById("job-script").value = isEdit
    ? item?.script || ""
    : "";
  document.getElementById("job-loops").value = isEdit
    ? (item?.loops ?? 0)
    : "0";
  document.getElementById("job-retrys").value = isEdit
    ? (item?.retrys ?? 0)
    : "0";
  document.getElementById("job-delay").value = isEdit
    ? (item?.delay ?? 0)
    : "0";

  // ==================== SCRIPT TEXTAREA + CLEAR BUTTON + TEMPLATE DROPDOWN ====================
  const scriptTextarea = document.getElementById("job-script");
  const clearBtn = document.getElementById("clear-script-btn");
  const templateSelect = document.getElementById("script-template");
  if (scriptTextarea) scriptTextarea.focus();
  function updateClearButton() {
    if (clearBtn) {
      clearBtn.style.display = scriptTextarea.value.trim() ? "block" : "none";
    }
  }
  if (scriptTextarea) {
    scriptTextarea.addEventListener("input", updateClearButton);
    updateClearButton();
  }
  if (clearBtn) {
    clearBtn.addEventListener("click", () => {
      scriptTextarea.value = "";
      scriptTextarea.focus();
      updateClearButton();
    });
  }

  // Template dropdown
  if (templateSelect) {
    if (templateSelect.tomselect) templateSelect.tomselect.destroy();
    const isEditMode = mode === "edit";
    new TomSelect(templateSelect, {
      maxItems: 1,
      placeholder: isEditMode
        ? "Replace with Template..."
        : "Insert Template...",
      dropdownParent: "body",
      maxOptions: 20,
      controlInput: "<input>",
      onChange: function (value) {
        if (!value || !scriptTextarea) return;
        switch (value) {
          case "shell":
            scriptTextarea.value = `#!/bin/sh
# ==================== ORDO ENVIRONMENT VARIABLES ====================
# ORDO_JOB_ID, ORDO_CLUSTER_ID, ORDO_SERVER_ID, ORDO_EMAIL, ORDO_TEAM
# ORDO_TOKEN, ORDO_API, ORDO_JSON + handler vars

echo "Starting job $ORDO_JOB_ID in cluster $ORDO_CLUSTER_ID"

# Example API call (token in body):
# curl -s "$ORDO_API" \\
#   -H "Content-Type: application/json" \\
#   -d '{
#     "command": "read_cluster",
#     "id": "'"$ORDO_CLUSTER_ID"'",
#     "token": "'"$ORDO_TOKEN"'"
#   }'
`;
            break;
          case "python":
            scriptTextarea.value = `#!/usr/bin/env python3
import os
import requests

# ==================== ORDO ENVIRONMENT VARIABLES ====================
print("=== ORDO Environment ===")
for key in sorted(k for k in os.environ if k.startswith("ORDO_")):
    print(f"{key}={os.environ[key]}")

api = os.getenv("ORDO_API")
token = os.getenv("ORDO_TOKEN")

# Example API call (token in body)
if api and token:
    payload = {
        "command": "read_cluster",
        "id": os.getenv("ORDO_CLUSTER_ID"),
        "token": token
    }
    resp = requests.post(api, json=payload)
    print("API Response:", resp.json())
`;
            break;
          case "perl":
            scriptTextarea.value = `#!/usr/bin/perl
use strict;
use warnings;

# ==================== ORDO ENVIRONMENT VARIABLES ====================
foreach my $key (sort grep { /^ORDO_/ } keys %ENV) {
    print "$key=$ENV{$key}\\n";
}
`;
            break;

          // === Utility Templates ===
          case "stats":
            scriptTextarea.value = `#!/bin/sh
# === Update Stats ===
# This is a simple wrapper that calls the full update_stats.pl script.
# It collects real-time server metrics (CPU, memory, disk, load average, etc.)
# and process-level stats for the server it runs on.
#
# Recommended: Run this frequently (every 30-60 seconds) in a dedicated "Monitoring" cluster.
update_stats.pl
`;
            break;

          case "on-fail":
            scriptTextarea.value = `#!/usr/bin/perl
use strict;
use warnings;

# ==================== ON FAIL HANDLER ====================
# Purpose: Runs when a cluster fails. Use this to send alerts,
#          start fallback workflows, or perform cleanup.

print "=== On Fail Handler ===\\n";
print "Failed cluster: $ENV{ORDO_FAILED_CLUSTER_ID}\\n";

# Example: Send alert
# system(\\"email_team.pl\\", \\"Cluster $ENV{ORDO_FAILED_CLUSTER_ID} has failed!\\");
`;
            break;

          case "on-overdue":
            scriptTextarea.value = `#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON::MaybeXS;

# ==================== ON OVERDUE HANDLER ====================
# Purpose: Runs when a calendar tries to start a cluster that is not ready (overdue).
#          Most common use: automatically clone and start a fresh copy of the overdue cluster.

my $overdue_id = $ENV{ORDO_OVERDUE_CLUSTER_ID} or die "ORDO_OVERDUE_CLUSTER_ID not set\\n";
my $api_url = $ENV{ORDO_API} or die "ORDO_API not set\\n";
my $token   = $ENV{ORDO_TOKEN} or die "ORDO_TOKEN not set\\n";

my $ua = LWP::UserAgent->new(timeout => 15);

sub post {
  my ($cmd, $payload) = @_;
  my $res = $ua->post($api_url, Content_Type => 'application/json',
    Content => encode_json({ command => $cmd, id => $payload, token => $token }));
  die "$cmd failed: " . $res->status_line unless $res->is_success;
  return decode_json($res->decoded_content);
}

my $clone_data = post("clone_cluster", $overdue_id);
my $clone_id = $clone_data->{clone_id} or die "No clone_id returned";

print "Cloned $overdue_id -> $clone_id\\n";
post("start_cluster", $clone_id);
print "Started cloned cluster $clone_id\\n";
`;
            break;

          case "max-runtime":
            scriptTextarea.value = `#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON::MaybeXS;

# ==================== MAX RUNTIME HANDLER ====================
# Purpose: Runs when a cluster exceeds its configured maximum runtime.
#          Most common use: kill the long-running job and/or send an alert.

print "=== Max Runtime Handler ===\\n";
print "Cluster: $ENV{ORDO_MAX_RUNTIME_CLUSTER_ID}\\n";
print "Job: $ENV{ORDO_MAX_RUNTIME_JOB_ID}\\n";

my $api_url = $ENV{ORDO_API} or die "ORDO_API not set\\n";
my $token   = $ENV{ORDO_TOKEN} or die "ORDO_TOKEN not set\\n";

my $ua = LWP::UserAgent->new(timeout => 15);

sub post {
  my ($cmd, $payload) = @_;
  my $res = $ua->post($api_url, Content_Type => 'application/json',
    Content => encode_json({ command => $cmd, id => $payload, token => $token }));
  die "$cmd failed: " . $res->status_line unless $res->is_success;
  return decode_json($res->decoded_content);
}

my $job_info = post("read_job", $ENV{ORDO_MAX_RUNTIME_JOB_ID});
my $pid = $job_info->{pid} or die "Could not find PID for job";

print "Killing job $ENV{ORDO_MAX_RUNTIME_JOB_ID} (PID: $pid)\\n";
kill(9, $pid) or warn "Failed to kill PID $pid: $!";
`;
            break;

          default:
            console.warn("Unknown template:", value);
        }
        scriptTextarea.focus();
        updateClearButton();
        scriptTextarea.scrollTop = 0;
      },
    });
  }

  // ==================== SERVER ====================
  initModalTomSelect("job-server", {
    maxItems: 1,
    options: appState.serversData.map((s) => ({
      value: s.name,
      text: s.name,
    })),
  }).setValue(item?.server_name ? [item.server_name] : []);

  // ==================== DEPENDENCIES (same cluster only) ====================
  const jobOptions = Array.from(appState.jobsMap.values())
    .filter(
      (j) =>
        Number(j.cluster_id) === Number(currentClusterId) &&
        Number(j.id) !== numericId,
    )
    .map((j) => ({
      value: String(j.id),
      text: j.name || `Job ${j.id}`,
    }));
  initModalTomSelect("job-needs", {
    maxItems: null,
    options: jobOptions,
  }).setValue((item?.needs_ids || []).map(String));
  initModalTomSelect("job-needs-any", {
    maxItems: null,
    options: jobOptions,
  }).setValue((item?.needs_any_ids || []).map(String));

  // Max Runtime
  const maxRuntimeInput = document.getElementById("job-max-runtime");
  if (maxRuntimeInput) {
    maxRuntimeInput.value =
      isEdit && item?.max_runtime_seconds ? item.max_runtime_seconds : "";
  }

  // Max Runtime Handler
  const rootId = Number(appState.orgData.root_cluster_id);
  const clusterOptions = Array.from(appState.clustersMap.values())
    .filter((c) => {
      const cid = Number(c.id);
      return cid !== rootId && cid !== numericId; // exclude root and self
    })
    .map((c) => ({
      value: String(c.id),
      text: c.name || `Cluster ${c.id}`,
    }));

  initModalTomSelect("job-max-runtime-handler", {
    maxItems: 1,
    options: clusterOptions,
  });

  if (isEdit && item?.max_runtime_cluster_id) {
    document
      .getElementById("job-max-runtime-handler")
      .tomselect?.setValue([String(item.max_runtime_cluster_id)]);
  }

  modal.classList.add("active");
  document.getElementById("job-name").focus();
}

export function openJobModal2(
  mode = "create",
  itemId = null,
  parentId = null,
  parentName = null,
) {
  const modal = document.getElementById("job-modal");
  if (!modal) return;

  let item = null;
  const numericId = Number(itemId);
  if (mode === "edit" && numericId) {
    item =
      appState.jobsMap.get(numericId) ||
      findJobById(appState.monitorData.tree, numericId);
  }

  const isEdit = mode === "edit" && item !== null;
  const currentClusterId = item?.cluster_id || parentId;

  modal.dataset.editId = isEdit ? String(numericId) : "";
  modal.dataset.parentId = parentId || "";

  // Title & Context
  document.getElementById("job-modal-title").textContent = isEdit
    ? "Edit Job"
    : "New Job";

  document.getElementById("job-context").textContent = isEdit
    ? `Editing: ${item?.name || "—"}`
    : parentName
      ? `In cluster: ${parentName}`
      : "In root";

  // Basic fields
  document.getElementById("job-name").value = isEdit ? item?.name || "" : "";
  document.getElementById("job-script").value = isEdit
    ? item?.script || ""
    : "";
  document.getElementById("job-loops").value = isEdit
    ? (item?.loops ?? 0)
    : "0";
  document.getElementById("job-retrys").value = isEdit
    ? (item?.retrys ?? 0)
    : "0";
  document.getElementById("job-delay").value = isEdit
    ? (item?.delay ?? 0)
    : "0";

  // ==================== SCRIPT TEXTAREA + CLEAR BUTTON + TEMPLATE DROPDOWN ====================
  const scriptTextarea = document.getElementById("job-script");
  const clearBtn = document.getElementById("clear-script-btn");
  const templateSelect = document.getElementById("script-template");

  if (scriptTextarea) scriptTextarea.focus();

  function updateClearButton() {
    if (clearBtn) {
      clearBtn.style.display = scriptTextarea.value.trim() ? "block" : "none";
    }
  }

  if (scriptTextarea) {
    scriptTextarea.addEventListener("input", updateClearButton);
    updateClearButton();
  }

  if (clearBtn) {
    clearBtn.addEventListener("click", () => {
      scriptTextarea.value = "";
      scriptTextarea.focus();
      updateClearButton();
    });
  }

  // Template dropdown
  if (templateSelect) {
    if (templateSelect.tomselect) templateSelect.tomselect.destroy();

    const isEditMode = mode === "edit";

    new TomSelect(templateSelect, {
      maxItems: 1,
      placeholder: isEditMode
        ? "Replace with Template..."
        : "Insert Template...",
      //width: '100%',                    // ensure full width
      dropdownParent: "body", // better positioning
      maxOptions: 20,
      controlInput: "<input>", // force full width
      //onInitialize: function() {
      //  this.control.style.minWidth = '340px';
      //},

      onChange: function (value) {
        if (!value || !scriptTextarea) return;

        switch (value) {
          case "shell":
            scriptTextarea.value = `#!/bin/sh
echo "Starting task at $(date)"
# Your shell commands here...
echo "Task completed at $(date)"
`;
            break;

          case "python":
            scriptTextarea.value = `#!/usr/bin/env python3
import datetime
print("Started at:", datetime.datetime.now())
# Your Python code here...
print("Python script finished successfully")
`;
            break;

          case "perl":
            scriptTextarea.value = `#!/usr/bin/env perl
use strict;
use warnings;
print "Started at: " . localtime() . "\\n";
# Your Perl code here...
print "Perl script finished.\\n";
`;
            break;

          // === Utility Templates ===
          case "stats":
            scriptTextarea.value = `#!/bin/sh

# === Update Stats ===
# This is a simple wrapper that calls the full update_stats.pl script.
# It collect real-time server metrics (CPU, memory, disk, load average, etc.)
# and process-level stats (CPU %, memory %, PID, runtime) for the server it runs on.
# 
# Recommended: Run this frequently (every 30-60 seconds) in a dedicated "Monitoring" cluster.

update_stats.pl
`;
            break;

          case "on-fail-alert":
            scriptTextarea.value = `#!/usr/bin/env perl
use strict;
use warnings;

# === On Fail Alert Template ===
# This job is typically used in an On Fail Handler cluster.
# It receives ORDO_FAILED_CLUSTER_ID.

my $failed_id = $ENV{ORDO_FAILED_CLUSTER_ID} || "unknown";

print "=== JOB FAILURE ALERT ===\\n";
print "Failed cluster ID: $failed_id\\n";
print "Time: " . localtime() . "\\n";

# Customize your alert here (email, Slack, PagerDuty, etc.)
# Example:
# system("echo 'Job failed in cluster $failed_id' | mail -s 'Ordo Alert' admin@example.com");
`;
            break;

          case "clone-overdue":
            scriptTextarea.value = `#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON::MaybeXS;

# === Clone Overdue Cluster ===
# This job is typically used in an On Overdue Handler.
# It automatically clones and starts the overdue cluster.

my $overdue_id = $ENV{ORDO_OVERDUE_CLUSTER_ID} 
  or die "ORDO_OVERDUE_CLUSTER_ID not set\\n";

my $api_url = $ENV{ORDO_API} or die "ORDO_API not set\\n";
my $token   = $ENV{ORDO_TOKEN} or die "ORDO_TOKEN not set\\n";

my $ua = LWP::UserAgent->new;

sub post {
  my ($cmd, $payload) = @_;
  my $res = $ua->post(
    $api_url,
    Content_Type => 'application/json',
    Content      => encode_json({
      command => $cmd,
      id      => $payload,
      token   => $token,
    })
  );
  die "$cmd failed: " . $res->status_line unless $res->is_success;
  return decode_json($res->decoded_content);
}

# Clone
my $clone_data = post("clone_cluster", $overdue_id);
my $clone_id = $clone_data->{clone_id} or die "No clone_id returned";

print "Cloned $overdue_id -> $clone_id\\n";

# Start clone
post("start_cluster", $clone_id);

print "Started cloned cluster $clone_id\\n";
`;
            break;

          default:
            console.warn("Unknown template:", value);
        }
        scriptTextarea.focus();
        updateClearButton();
        scriptTextarea.scrollTop = 0;
      },
    });
  }

  // ==================== SERVER ====================
  initModalTomSelect("job-server", {
    maxItems: 1,
    options: appState.serversData.map((s) => ({
      value: s.name,
      text: s.name,
    })),
  }).setValue(item?.server_name ? [item.server_name] : []);

  // ==================== DEPENDENCIES (same cluster only) ====================
  const jobOptions = Array.from(appState.jobsMap.values())
    .filter(
      (j) =>
        Number(j.cluster_id) === Number(currentClusterId) &&
        Number(j.id) !== numericId,
    )
    .map((j) => ({
      value: String(j.id),
      text: j.name || `Job ${j.id}`,
    }));

  initModalTomSelect("job-needs", {
    maxItems: null,
    options: jobOptions,
  }).setValue((item?.needs_ids || []).map(String));

  initModalTomSelect("job-needs-any", {
    maxItems: null,
    options: jobOptions,
  }).setValue((item?.needs_any_ids || []).map(String));

  // Max Runtime
  const maxRuntimeInput = document.getElementById("job-max-runtime");
  if (maxRuntimeInput) {
    maxRuntimeInput.value =
      isEdit && item?.max_runtime_seconds ? item.max_runtime_seconds : "";
  }

  // Max Runtime Handler
  const rootId = Number(appState.orgData.root_cluster_id);
  const clusterOptions = Array.from(appState.clustersMap.values())
    .filter((c) => {
      const cid = Number(c.id);
      return cid !== rootId && cid !== numericId; // exclude root and self
    })
    .map((c) => ({
      value: String(c.id),
      text: c.name || `Cluster ${c.id}`,
    }));

  initModalTomSelect("job-max-runtime-handler", {
    maxItems: 1,
    options: clusterOptions,
  });

  if (isEdit && item?.max_runtime_cluster_id) {
    document
      .getElementById("job-max-runtime-handler")
      .tomselect?.setValue([String(item.max_runtime_cluster_id)]);
  }

  // ==================== ON_FAIL REMOVED FOR JOBS ====================

  modal.classList.add("active");
  document.getElementById("job-name").focus();
}

// ==================== SERVER MODAL ====================
export function openServerModal(mode = "create", serverData = null) {
  const modal = document.getElementById("server-modal");
  if (!modal) {
    console.error("Server modal element not found");
    return;
  }

  const titleEl = document.getElementById("server-modal-title");

  if (mode === "edit" && serverData) {
    titleEl.textContent = "Edit Server";
    document.getElementById("server-name").value = serverData.name || "";
    document.getElementById("server-host").value =
      serverData.host || serverData.ip_address || "";
    document.getElementById("server-user").value = serverData.user || "";
    document.getElementById("server-port").value = serverData.port || "22";
    // Do NOT prefill password for security
    appState.currentEditServerId = serverData.id;
  } else {
    // Create mode
    titleEl.textContent = "Add Server";
    document.getElementById("server-name").value = "";
    document.getElementById("server-host").value = "";
    document.getElementById("server-user").value = "";
    document.getElementById("server-port").value = "22";
    document.getElementById("server-password").value = "";
    appState.currentEditServerId = null;
  }

  modal.classList.add("active");
  document.getElementById("server-name").focus();
}

// ==================== CLUSTER MODAL ====================
export function openClusterModal(
  mode = "create",
  itemId = null,
  parentId = null,
  parentName = null,
) {
  const modal = document.getElementById("cluster-modal");
  if (!modal) return;

  let item = null;
  if (mode === "edit" && itemId) {
    item =
      appState.clustersMap.get(Number(itemId)) ||
      findClusterById(appState.monitorData.tree, itemId);
  }

  const isEdit = mode === "edit";
  modal.dataset.editId = isEdit ? String(itemId) : "";
  modal.dataset.parentId = parentId || "";

  document.getElementById("cluster-modal-title").textContent = isEdit
    ? "Edit Cluster"
    : "New Cluster";

  document.getElementById("cluster-context").textContent = isEdit
    ? `Editing: ${item?.name || "—"}`
    : parentName
      ? `In cluster: ${parentName}`
      : "In root";

  // Basic fields
  document.getElementById("cluster-name").value = item?.name || "";
  document.getElementById("cluster-loops").value = item?.loops ?? 0;

  // Auto Start (default true)
  const autoStartCheckbox = document.getElementById("cluster-auto-start");
  if (autoStartCheckbox) {
    autoStartCheckbox.checked = item ? !!item.auto_start : true;
  }

  // ==================== CALENDAR (TomSelect) ====================
  const calendarOptions = (appState.calendarsData || []).map(cal => ({
    value: String(cal.id),
    text: cal.name || `Calendar ${cal.id}`
  }));

  const calTom = initModalTomSelect("cluster-calendar", {
    maxItems: 1,
    options: calendarOptions,
    placeholder: "No Calendar (Manual / Triggered Only)"
  });

  if (isEdit && item?.cal_id) {
    calTom.setValue([String(item.cal_id)]);
  } else {
    calTom.setValue([]);
  }

  // ==================== OTHER TOMSELECTS ====================
  const rootId = Number(appState.orgData?.root_cluster_id || appState.accountData?.root_cluster_id);
  const currentId = Number(itemId);

  const clusterOptions = Array.from(appState.clustersMap.values())
    .filter((c) => {
      const cid = Number(c.id);
      return cid !== rootId && cid !== currentId;
    })
    .map((c) => ({
      value: String(c.id),
      text: c.name || `Cluster ${c.id}`,
    }));

  initModalTomSelect("cluster-needs", {
    maxItems: null,
    options: clusterOptions,
  });

  initModalTomSelect("cluster-needs-any", {
    maxItems: null,
    options: clusterOptions,
  });

  initModalTomSelect("cluster-on-fail", {
    maxItems: 1,
    options: clusterOptions,
  });

  initModalTomSelect("cluster-on-overdue", {
    maxItems: 1,
    options: clusterOptions,
  });

  // Restore values for edit mode
  if (isEdit && item) {
    document.getElementById("cluster-needs").tomselect?.setValue((item.needs_ids || []).map(String));
    document.getElementById("cluster-needs-any").tomselect?.setValue((item.needs_any_ids || []).map(String));

    if (item.on_fail_id) {
      document.getElementById("cluster-on-fail").tomselect?.setValue([String(item.on_fail_id)]);
    }
    if (item.on_overdue_id) {
      document.getElementById("cluster-on-overdue").tomselect?.setValue([String(item.on_overdue_id)]);
    }
  }

  modal.classList.add("active");
  document.getElementById("cluster-name").focus();
}

export function openClusterModal2(
  mode = "create",
  itemId = null,
  parentId = null,
  parentName = null,
) {
  const modal = document.getElementById("cluster-modal");
  if (!modal) return;

  let item = null;
  if (mode === "edit" && itemId) {
    item =
      appState.clustersMap.get(Number(itemId)) ||
      findClusterById(appState.monitorData.tree, itemId);
  }

  const isEdit = mode === "edit";
  modal.dataset.editId = isEdit ? String(itemId) : "";
  modal.dataset.parentId = parentId || "";

  document.getElementById("cluster-modal-title").textContent = isEdit
    ? "Edit Cluster"
    : "New Cluster";

  document.getElementById("cluster-context").textContent = isEdit
    ? `Editing: ${item?.name || "—"}`
    : parentName
      ? `In cluster: ${parentName}`
      : "In root";

  // Basic fields
  document.getElementById("cluster-name").value = item?.name || "";
  document.getElementById("cluster-loops").value = item?.loops ?? 0;

  // Auto Start (default true)
  const autoStartCheckbox = document.getElementById("cluster-auto-start");
  if (autoStartCheckbox) {
    autoStartCheckbox.checked = item ? !!item.auto_start : true;
  }

  // === CALENDAR SELECT ===
  const calSelect = document.getElementById("cluster-calendar");
  calSelect.innerHTML = `<option value="">No Calendar (Manual / Triggered Only)</option>`;

  (appState.calendarsData || []).forEach(cal => {
    const opt = document.createElement("option");
    opt.value = String(cal.id);
    opt.textContent = cal.name || `Calendar ${cal.id}`;
    calSelect.appendChild(opt);
  });

  if (isEdit && item?.cal_id) {
    calSelect.value = String(item.cal_id);
  }

  // Options (exclude root and self)
  const rootId = Number(appState.orgData.root_cluster_id);
  const currentId = Number(itemId);

  const clusterOptions = Array.from(appState.clustersMap.values())
    .filter((c) => {
      const cid = Number(c.id);
      return cid !== rootId && cid !== currentId;
    })
    .map((c) => ({
      value: String(c.id),
      text: c.name || `Cluster ${c.id}`,
    }));

  initModalTomSelect("cluster-needs", {
    maxItems: null,
    options: clusterOptions,
  });
  initModalTomSelect("cluster-needs-any", {
    maxItems: null,
    options: clusterOptions,
  });

  initModalTomSelect("cluster-on-fail", {
    maxItems: 1,
    options: clusterOptions,
  });

  initModalTomSelect("cluster-on-overdue", {
    maxItems: 1,
    options: clusterOptions,
  });

  // Restore values
  if (isEdit && item) {
    document
      .getElementById("cluster-needs")
      .tomselect?.setValue((item.needs_ids || []).map(String));
    document
      .getElementById("cluster-needs-any")
      .tomselect?.setValue((item.needs_any_ids || []).map(String));

    if (item.on_fail_id) {
      document
        .getElementById("cluster-on-fail")
        .tomselect?.setValue([String(item.on_fail_id)]);
    }

    if (item.on_overdue_id) {
      document
        .getElementById("cluster-on-overdue")
        .tomselect?.setValue([String(item.on_overdue_id)]);
    }
  }

  modal.classList.add("active");
  document.getElementById("cluster-name").focus();
}

// ==================== ATTACH CALENDAR MODAL ====================
export function openAttachCalendarModal(
  clusterId,
  clusterName,
  currentCalName = "",
  currentCalId = null,
) {
  appState.currentAttachClusterId = clusterId;

  const clusterNameEl = document.getElementById("attach-cluster-name");
  if (clusterNameEl) {
    clusterNameEl.textContent = clusterName || `Cluster #${clusterId}`;
  }

  const select = document.getElementById("calendar-select");
  if (!select)
    return console.error("[Attach Calendar] #calendar-select not found");

  // Destroy previous instance
  if (select.tomselect) {
    select.tomselect.destroy();
  }

  // Create TomSelect with body dropdown
  const ts = new TomSelect(select, {
    maxItems: 1,
    dropdownParent: "body", // Break out of modal
    plugins: ["remove_button"], // Enable the red X
    placeholder: "Select calendar or type to search...",
    options: appState.calendarsData.map((cal) => ({
      value: String(cal.id),
      text: cal.name || `Calendar ${cal.id}`,
    })),
    sortField: "text",
    onInitialize: function () {
      if (currentCalId != null) {
        this.setValue(String(currentCalId));
      }
    },
  });

  select.tomselect = ts; // Store reference

  document.getElementById("attach-calendar-modal").classList.add("active");
}

// ==================== CONFIRM MODAL ====================
export function openConfirmModal(
  title = "Confirm",
  message = "Are you sure?",
  onConfirm = null,
  onCancel = null,
  requireDeleteConfirmation = false, // Only true for dangerous actions
) {
  const modal = document.getElementById("confirm-modal");
  if (!modal) {
    console.error("[openConfirmModal] Modal not found");
    return;
  }

  const titleEl = modal.querySelector(".modal-title");
  const msgEl = document.getElementById("confirm-message");

  if (titleEl) titleEl.textContent = title;
  if (msgEl) msgEl.textContent = message;

  // Remove any previous delete input
  const oldInput = document.getElementById("confirm-delete-container");
  if (oldInput) oldInput.remove();

  // Add delete confirmation input only when requested
  if (requireDeleteConfirmation) {
    const inputHTML = `
      <div id="confirm-delete-container" class="mt-medium">
        <label class="label-bold text-red">Type DELETE to confirm</label>
        <input type="text" id="confirm-delete-input" class="input" placeholder="DELETE" autocomplete="off">
      </div>`;
    msgEl.insertAdjacentHTML("afterend", inputHTML);
  }

  const yesBtn = document.getElementById("confirm-yes");
  const noBtn = document.getElementById("confirm-no");

  // Clone buttons to clear old listeners
  const newYes = yesBtn.cloneNode(true);
  yesBtn.parentNode.replaceChild(newYes, yesBtn);

  if (noBtn) {
    const newNo = noBtn.cloneNode(true);
    noBtn.parentNode.replaceChild(newNo, noBtn);
    newNo.addEventListener("click", () => {
      modal.classList.remove("active");
      if (typeof onCancel === "function") onCancel();
    });
  }

  newYes.addEventListener("click", () => {
    if (requireDeleteConfirmation) {
      const input = document.getElementById("confirm-delete-input");
      if (!input || input.value.trim().toUpperCase() !== "DELETE") {
        showToast("You must type exactly DELETE to confirm", "danger");
        return;
      }
    }

    modal.classList.remove("active");
    if (typeof onConfirm === "function") onConfirm();
  });

  modal.classList.add("active");
}

// ==================== CALENDAR MODAL ====================
function populateTimezoneSelect() {
  const tzSelect = document.getElementById("calendar-tz");
  if (!tzSelect) return;

  tzSelect.innerHTML = '<option value="">Select common timezone...</option>';
  commonTimezones.forEach((tz) => {
    const option = document.createElement("option");
    option.value = tz;
    option.textContent = tz;
    tzSelect.appendChild(option);
  });

  tzSelect.addEventListener("change", () => {
    const customInput = document.getElementById("calendar-tz-custom");
    if (tzSelect.value === "") {
      customInput.style.display = "block";
      customInput.required = true;
    } else {
      customInput.style.display = "none";
      customInput.required = false;
      customInput.value = "";
    }
  });
}

// utils.js or modals.js
function getTimezoneOptions() {
  const options = [];

  // Modern browsers: full IANA list
  if (Intl && Intl.supportedValuesOf) {
    const timezones = Intl.supportedValuesOf("timeZone");
    timezones.forEach((tz) => {
      // Optional: friendly name with offset (dynamic)
      const formatter = new Intl.DateTimeFormat("en-US", {
        timeZone: tz,
        timeZoneName: "long",
      });
      const parts = formatter.formatToParts(new Date());
      const tzName = parts.find((p) => p.type === "timeZoneName")?.value || tz;
      options.push({
        value: tz,
        text: `${tz} – ${tzName}`,
      });
    });
  } else {
    // Static fallback - large curated list (add more as needed)
    const staticTz = [
      "UTC",
      "America/New_York – Eastern Time (US & Canada)",
      "America/Chicago – Central Time (US & Canada)",
      "America/Denver – Mountain Time (US & Canada)",
      "America/Los_Angeles – Pacific Time (US & Canada)",
      "Europe/London – GMT / BST",
      "Europe/Paris – Central European Time",
      "Europe/Berlin – Central European Time",
      "Asia/Tokyo – Japan Standard Time",
      "Asia/Shanghai – China Standard Time",
      "Asia/Singapore – Singapore Time",
      "Australia/Sydney – Eastern Time (Australia)",
      "Pacific/Auckland – New Zealand Time",
      // ... add 100+ more major ones
    ];
    staticTz.forEach((tz) => {
      options.push({ value: tz.split(" – ")[0], text: tz });
    });
  }

  // Sort alphabetically by text
  options.sort((a, b) => a.text.localeCompare(b.text));

  return options;
}

export function openCalendarModal(mode = "create", calId = null) {
  const modal = document.getElementById("calendar-modal");
  if (!modal) return;

  const isEdit = mode === "edit";

  modal.dataset.editId = isEdit ? String(calId) : "";

  document.getElementById("calendar-modal-title").textContent = isEdit
    ? "Edit Calendar"
    : "Create Calendar";

  // Basic fields
  document.getElementById("calendar-name").value = "";
  document.getElementById("calendar-description").value = "";

  // Timezone TomSelect
  const tzOptions = getTimezoneOptions(); // your existing function

  initModalTomSelect("calendar-tz", {
    maxItems: 1,
    placeholder: "Type to search or select timezone...",
    options: tzOptions,
  });

  // Restore values on edit
  if (isEdit && calId) {
    const cal = appState.calendarsData.find(
      (c) => Number(c.id) === Number(calId),
    );
    if (cal) {
      document.getElementById("calendar-name").value = cal.name || "";
      document.getElementById("calendar-description").value =
        cal.description || "";

      const tzTS = document.getElementById("calendar-tz").tomselect;
      if (tzTS) {
        if (tzTS.options[cal.tz]) {
          tzTS.setValue(cal.tz);
        } else {
          tzTS.setValue("");
          document.getElementById("calendar-tz-custom").value = cal.tz || "";
          document.getElementById("calendar-tz-custom").style.display = "block";
        }
      }
    }
  } else {
    // New calendar → default to user's local timezone
    const localTz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const tzTS = document.getElementById("calendar-tz").tomselect;
    if (tzTS) {
      if (tzTS.options[localTz]) {
        tzTS.setValue(localTz);
      } else {
        tzTS.setValue("");
        document.getElementById("calendar-tz-custom").value = localTz;
        document.getElementById("calendar-tz-custom").style.display = "block";
      }
    }
  }

  modal.classList.add("active");
  document.getElementById("calendar-name").focus();
}

// ==================== CRONS LIST MODAL ====================
export function openCronsModal(calId) {
  const cal = appState.calendarsData.find(
    (c) => Number(c.id) === Number(calId),
  );
  if (!cal) {
    showToast("Calendar not found", "danger");
    return;
  }

  const modal = document.getElementById("crons-modal");
  if (!modal) return;

  modal.dataset.calId = String(calId);
  document.getElementById("crons-modal-title").textContent =
    `Crons for ${cal.name || "Calendar"}`;

  const loading = document.getElementById("crons-loading");
  const content = document.getElementById("crons-content");
  const body = document.getElementById("crons-body");
  const noCronsMsg = document.getElementById("no-crons-message");

  loading.style.display = "block";
  content.style.display = "none";
  body.innerHTML = "";

  const crons = cal.crons || [];

  if (crons.length > 0) {
    crons.forEach((cron) => {
      const tr = document.createElement("tr");
      tr.className = "crons-row";
      tr.innerHTML = `
        <td>${cron.id}</td>
        <td>${escapeHtml(cron.name || cron.expression || "—")}</td>
        <td>${escapeHtml(cron.english || "—")}</td>
        <td>${cron.begin ? formatDate(cron.begin) : "Immediate"}</td>
        <td>${cron.expire ? formatDate(cron.expire) : "Never"}</td>
        <td>${escapeHtml(cron.description || "—")}</td>
        <td>${formatDate(cron.next_start) || "—"}</td>
        <td>
          <button class="btn btn-sm btn-danger delete-cron" 
                  data-cron-id="${cron.id}" 
                  data-cal-id="${cal.id}">
            <i class="fas fa-trash"></i>
          </button>
        </td>
      `;
      body.appendChild(tr);
    });
    noCronsMsg.style.display = "none";
  } else {
    noCronsMsg.style.display = "block";
  }

  loading.style.display = "none";
  content.style.display = "block";
  modal.classList.add("active");
}

// ==================== SINGLE CRON MODAL ====================
// Replace openCronModal
export function openCronModal(mode = "create", calId, cron = null) {
  const isEdit = mode === "edit" && cron;
  const titleEl = document.getElementById("cron-modal-title");
  titleEl.textContent = isEdit ? "Edit Cron" : "Add Cron";

  // Clear fields first
  document.getElementById("cron-expression").value = "";
  document.getElementById("cron-description").value = "";
  document.getElementById("cron-begin").value = "";
  document.getElementById("cron-expire").value = "";

  if (isEdit && cron) {
    document.getElementById("cron-expression").value = cron.name || "";
    document.getElementById("cron-description").value = cron.description || "";
    document.getElementById("cron-begin").value = cron.begin || "";
    document.getElementById("cron-expire").value = cron.expire || "";
  }

  const modal = document.getElementById("cron-modal");
  modal.dataset.calId = calId;
  modal.dataset.cronId = isEdit ? cron.id : "";
  modal.classList.add("active");
}

// ==================== SAVE FUNCTIONS ====================
function saveAttachCalendar() {
  const select = document.getElementById("calendar-select");
  if (!select) {
    console.error("[Save Calendar] #calendar-select not found");
    return;
  }
  const calId = select.value;
  sendWS({
    command: "update_cluster",
    id: appState.currentAttachClusterId,
    cal_id: calId || "", // empty = detach
  });
  showToast(calId ? "Calendar attached" : "Calendar detached", "success");
  document.getElementById("attach-calendar-modal").classList.remove("active");
}

export function saveJob() {
  const modal = document.getElementById("job-modal");
  const isEdit = !!modal.dataset.editId;
  const id = isEdit ? Number(modal.dataset.editId) : null;

  const payload = {
    command: isEdit ? "update_job_config" : "create_job",
    name: (document.getElementById("job-name").value || "").trim(),
    script: (document.getElementById("job-script").value || "").trim(),
    server: (document.getElementById("job-server").value || "").trim(),
    // description: (document.getElementById("job-description").value || "").trim(),
    retrys: parseInt(document.getElementById("job-retrys").value) || 0,
    loops: parseInt(document.getElementById("job-loops").value) || 0,
    delay: parseInt(document.getElementById("job-delay").value) || 0,
  };

  // Read current TomSelect values
  payload.needs_ids =
    document.getElementById("job-needs").tomselect?.getValue().map(Number) ||
    [];
  payload.needs_any_ids =
    document
      .getElementById("job-needs-any")
      .tomselect?.getValue()
      .map(Number) || [];

  // ==================== MAX RUNTIME HANDLER ====================
  const maxRuntimeEl = document.getElementById("job-max-runtime");
  const maxSeconds = maxRuntimeEl ? parseInt(maxRuntimeEl.value) || 0 : 0;

  const maxHandlerEl = document.getElementById("job-max-runtime-handler");
  let maxClusterId = null;

  if (maxHandlerEl && maxHandlerEl.tomselect) {
    const val = maxHandlerEl.tomselect.getValue();
    if (val && String(val).trim() !== "" && String(val) !== "null") {
      maxClusterId = Number(val);
    }
  }

  // Validation: one but not both
  if ((maxSeconds > 0 && !maxClusterId) || (maxClusterId && maxSeconds === 0)) {
    showToast(
      "Max Runtime requires both seconds AND a handler (or neither)",
      "danger",
    );
    return; // stop save
  }

  // Send to server
  if (maxSeconds > 0 && maxClusterId) {
    payload.max_runtime_seconds = maxSeconds;
    payload.max_runtime_cluster_id = maxClusterId;
  } else {
    payload.max_runtime_seconds = 0;
    payload.max_runtime_cluster_id = null;
  }

  console.log("[saveJob] Max Runtime →", {
    max_runtime_seconds: maxSeconds,
    max_runtime_cluster_id: maxClusterId,
  });

  /*
  const maxRuntimeVal = parseInt(document.getElementById("job-max-runtime").value) || 0;
  const maxRuntimeHandlerVal = document
    .getElementById("job-max-runtime-handler")
    .tomselect?.getValue();

  if (maxRuntimeVal > 0) {
    payload.max_runtime_seconds = maxRuntimeVal;
    if (maxRuntimeHandlerVal && maxRuntimeHandlerVal.length > 0) {
      payload.max_runtime_cluster_id = Number(maxRuntimeHandlerVal);
    }
  } else if (maxRuntimeHandlerVal && maxRuntimeHandlerVal.length > 0) {
    // If handler is set but no seconds, show error
    payload.max_runtime_cluster_id = null;   // explicitly clear
    showToast("Max Runtime (seconds) is required when using a handler", "danger");
    return;
  }
*/

  // ==================== PARENT / RENAME HANDLING ====================
  if (!isEdit) {
    let parentId = modal.dataset.parentId;
    if (parentId) payload.parent_id = Number(parentId);
  } else {
    payload.id = id;

    // Rename handling
    const newName = payload.name;
    if (newName) {
      payload.newname = newName;
      delete payload.name; // backend wants newname on update
    }
  }

  // Validation - check the right field
  if (!payload.name && !isEdit) {
    showToast("Job name is required", "danger");
    return;
  }

  console.log("[saveJob] Final payload:", payload);
  sendWS(payload);

  modal.classList.remove("active");
  //showToast(isEdit ? "Job updated" : "Job created", "success");
}

// ==================== SAVE CLUSTER ====================
// ==================== SAVE CLUSTER ====================
export function saveCluster() {
  const modal = document.getElementById("cluster-modal");
  const isEdit = !!modal.dataset.editId;
  const id = isEdit ? Number(modal.dataset.editId) : null;

  const payload = {
    command: isEdit ? "update_cluster" : "create_cluster",
    name: (document.getElementById("cluster-name").value || "").trim(),
    loops: parseInt(document.getElementById("cluster-loops").value) || 0,
    auto_start: document.getElementById("cluster-auto-start").checked ? 1 : 0,
  };

  // Calendar
  const calEl = document.getElementById("cluster-calendar");
  if (calEl?.tomselect) {
    const raw = calEl.tomselect.getValue();
    const hasValue = raw && (Array.isArray(raw) ? raw.length > 0 : String(raw).trim() !== "");
    payload.cal_id = hasValue ? Number(Array.isArray(raw) ? raw[0] : raw) : "";
  } else {
    payload.cal_id = "";
  }

  // On Fail
  const onFailEl = document.getElementById("cluster-on-fail");
  if (onFailEl?.tomselect) {
    const raw = onFailEl.tomselect.getValue();
    const hasValue = raw && (Array.isArray(raw) ? raw.length > 0 : String(raw).trim() !== "");
    payload.on_fail_id = hasValue ? Number(Array.isArray(raw) ? raw[0] : raw) : "";
  } else {
    payload.on_fail_id = "";
  }

  // On Overdue
  const onOverdueEl = document.getElementById("cluster-on-overdue");
  if (onOverdueEl?.tomselect) {
    const raw = onOverdueEl.tomselect.getValue();
    const hasValue = raw && (Array.isArray(raw) ? raw.length > 0 : String(raw).trim() !== "");
    payload.on_overdue_id = hasValue ? Number(Array.isArray(raw) ? raw[0] : raw) : "";
  } else {
    payload.on_overdue_id = "";
  }

  // === NEEDS + NEEDS ANY (multi-select) ===
  const needsEl = document.getElementById("cluster-needs");
  if (needsEl?.tomselect) {
    const values = needsEl.tomselect.getValue();
    payload.needs_ids = Array.isArray(values) ? values.map(Number).filter(Boolean) : [];
  }

  const needsAnyEl = document.getElementById("cluster-needs-any");
  if (needsAnyEl?.tomselect) {
    const values = needsAnyEl.tomselect.getValue();
    payload.needs_any_ids = Array.isArray(values) ? values.map(Number).filter(Boolean) : [];
  }

  // ==================== PARENT / RENAME ====================
  if (!isEdit && modal.dataset.parentId) {
    payload.parent_id = Number(modal.dataset.parentId);
  } else if (isEdit) {
    payload.id = id;
    const newName = payload.name;
    if (newName) {
      payload.newname = newName;
      delete payload.name;
    }
  }

  if (!payload.name && !isEdit) {
    showToast("Cluster name is required", "danger");
    return;
  }

  console.log("[saveCluster] Final payload:", payload);
  sendWS(payload);
  modal.classList.remove("active");
}


export function saveCluster4() {
  const modal = document.getElementById("cluster-modal");
  const isEdit = !!modal.dataset.editId;
  const id = isEdit ? Number(modal.dataset.editId) : null;

  const payload = {
    command: isEdit ? "update_cluster" : "create_cluster",
    name: (document.getElementById("cluster-name").value || "").trim(),
    loops: parseInt(document.getElementById("cluster-loops").value) || 0,
    auto_start: document.getElementById("cluster-auto-start").checked ? 1 : 0,
  };

  // Calendar - use "" to clear
  const calEl = document.getElementById("cluster-calendar");
  if (calEl && calEl.tomselect) {
    const raw = calEl.tomselect.getValue();
    const hasValue = raw && (Array.isArray(raw) ? raw.length > 0 : String(raw).trim() !== "");
    payload.cal_id = hasValue ? Number(Array.isArray(raw) ? raw[0] : raw) : "";
  } else {
    payload.cal_id = "";
  }

  // On Fail - use "" to clear
  const onFailEl = document.getElementById("cluster-on-fail");
  if (onFailEl && onFailEl.tomselect) {
    const raw = onFailEl.tomselect.getValue();
    const hasValue = raw && (Array.isArray(raw) ? raw.length > 0 : String(raw).trim() !== "");
    payload.on_fail_id = hasValue ? Number(Array.isArray(raw) ? raw[0] : raw) : "";
  } else {
    payload.on_fail_id = "";
  }

  // On Overdue - use "" to clear
  const onOverdueEl = document.getElementById("cluster-on-overdue");
  if (onOverdueEl && onOverdueEl.tomselect) {
    const raw = onOverdueEl.tomselect.getValue();
    const hasValue = raw && (Array.isArray(raw) ? raw.length > 0 : String(raw).trim() !== "");
    payload.on_overdue_id = hasValue ? Number(Array.isArray(raw) ? raw[0] : raw) : "";
  } else {
    payload.on_overdue_id = "";
  }

  // ==================== PARENT / RENAME ====================
  if (!isEdit && modal.dataset.parentId) {
    payload.parent_id = Number(modal.dataset.parentId);
  } else if (isEdit) {
    payload.id = id;
    const newName = payload.name;
    if (newName) {
      payload.newname = newName;
      delete payload.name;
    }
  }

  if (!payload.name && !isEdit) {
    showToast("Cluster name is required", "danger");
    return;
  }

  console.log("[saveCluster] Final payload:", payload);
  sendWS(payload);
  modal.classList.remove("active");
}

export function saveCluster3() {
  const modal = document.getElementById("cluster-modal");
  const isEdit = !!modal.dataset.editId;
  const id = isEdit ? Number(modal.dataset.editId) : null;

  const payload = {
    command: isEdit ? "update_cluster" : "create_cluster",
    name: (document.getElementById("cluster-name").value || "").trim(),
    loops: parseInt(document.getElementById("cluster-loops").value) || 0,
    auto_start: document.getElementById("cluster-auto-start").checked ? 1 : 0,
  };

  // === CALENDAR (force clear when x is clicked) ===
  const calEl = document.getElementById("cluster-calendar");
  let calId = null;

  if (calEl && calEl.tomselect) {
    const ts = calEl.tomselect;
    const raw = ts.getValue();

    if (raw && (Array.isArray(raw) ? raw.length > 0 : String(raw).trim() !== "")) {
      calId = Number(Array.isArray(raw) ? raw[0] : raw);
    } else {
      calId = "";   // explicit empty string for detach
    }
  } else {
    calId = "";
  }

  payload.cal_id = calId;

  // On Fail
  const onFailEl = document.getElementById("cluster-on-fail");
  if (onFailEl && onFailEl.tomselect) {
    const val = onFailEl.tomselect.getValue();
    if (val && (Array.isArray(val) ? val.length > 0 : String(val).trim() !== "")) {
      payload.on_fail_id = Number(Array.isArray(val) ? val[0] : val);
    }
  }

  // On Overdue
  const onOverdueEl = document.getElementById("cluster-on-overdue");
  if (onOverdueEl && onOverdueEl.tomselect) {
    const val = onOverdueEl.tomselect.getValue();
    if (val && (Array.isArray(val) ? val.length > 0 : String(val).trim() !== "")) {
      payload.on_overdue_id = Number(Array.isArray(val) ? val[0] : val);
    }
  }

  // Parent / Rename
  if (!isEdit && modal.dataset.parentId) {
    payload.parent_id = Number(modal.dataset.parentId);
  } else if (isEdit) {
    payload.id = id;
    const newName = payload.name;
    if (newName) {
      payload.newname = newName;
      delete payload.name;
    }
  }

  if (!payload.name && !isEdit) {
    showToast("Cluster name is required", "danger");
    return;
  }

  console.log("[saveCluster] Final payload:", payload);
  sendWS(payload);
  modal.classList.remove("active");
}


export function saveCalendar() {
  const modal = document.getElementById("calendar-modal");
  const isEdit = !!modal.dataset.editId;
  const id = isEdit ? Number(modal.dataset.editId) : null;

  const tzSelect = document.getElementById("calendar-tz");
  let tzValue = tzSelect.tomselect
    ? tzSelect.tomselect.getValue()
    : tzSelect.value;

  // Fallback to custom field
  if (!tzValue || tzValue === "") {
    tzValue = document.getElementById("calendar-tz-custom").value.trim();
  }

  const payload = {
    command: isEdit ? "update_cal" : "create_cal",
    name: (document.getElementById("calendar-name").value || "").trim(),
    tz: tzValue || "UTC",
    description: (
      document.getElementById("calendar-description").value || ""
    ).trim(),
  };

  if (!payload.name) {
    showToast("Calendar name is required", "danger");
    return;
  }

  if (isEdit) {
    payload.id = id;
    const newName = payload.name;
    if (newName) {
      payload.newname = newName;
      delete payload.name;
    }
  }

  console.log("[saveCalendar] Final payload:", payload);
  sendWS(payload);

  modal.classList.remove("active");
  showToast(isEdit ? "Calendar updated" : "Calendar created", "success");
}

// ==================== SAVE CRON ====================
function saveCron() {
  const modal = document.getElementById("cron-modal");
  const calId = Number(modal.dataset.calId);
  const cronIdStr = modal.dataset.cronId;
  const isEdit = !!cronIdStr && cronIdStr !== "";
  const cronId = isEdit ? Number(cronIdStr) : null;

  const expression = document.getElementById("cron-expression")?.value.trim();
  const description = document.getElementById("cron-description")?.value.trim();
  const begin = document.getElementById("cron-begin")?.value.trim();
  const expire = document.getElementById("cron-expire")?.value.trim();

  if (!expression) {
    return showToast("Cron expression is required", "danger");
  }
  if (isNaN(calId) || calId <= 0) {
    return showToast("Invalid calendar ID", "danger");
  }

  const payload = {
    command: isEdit ? "update_cron" : "create_cron",
    cal_id: calId,
  };

  if (isEdit) {
    payload.id = cronId;
    // Only send newname if the expression actually changed or always (safe)
    payload.newname = expression;
  } else {
    payload.name = expression;
  }

  if (description) payload.description = description;
  if (begin) payload.begin = Number(begin);
  if (expire) payload.expire = Number(expire);

  sendWS(payload);
  showToast(isEdit ? "Cron updated" : "Cron added", "success");
  modal.classList.remove("active");

  // Full re-render calendars table to reflect changes immediately
  renderCalendarsTable();
}

// ==================== DOMContentLoaded - attach all listeners ====================
document.addEventListener("DOMContentLoaded", () => {
  // Save buttons
  document.getElementById("save-job")?.addEventListener("click", saveJob);
  document
    .getElementById("save-cluster")
    ?.addEventListener("click", saveCluster);
  document
    .getElementById("save-calendar")
    ?.addEventListener("click", saveCalendar);
  document.getElementById("save-cron")?.addEventListener("click", saveCron);

  // Cancel/close buttons
  document.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-dismiss]");
    if (!btn) return;

    const modalId = btn.dataset.dismiss;
    const modal = document.getElementById(modalId);

    if (!modal) return;

    modal.classList.remove("active");

    // Special cleanup

    if (modal.id === "log-history-modal") {
      const tbody = modal.querySelector("#log-history-body");
      if (tbody) {
        tbody.innerHTML = ""; // Safe — only clears rows
      }
    }
    if (modal.id === "graph-modal" && window.cy) {
      window.cy.destroy();
      window.cy = null;
    }

    // General reset for all modals
    resetAllModals();
  });

  // Create calendar button
  document
    .getElementById("create-calendar-btn")
    ?.addEventListener("click", () => {
      openCalendarModal("create");
    });

  document
    .getElementById("save-attach-calendar")
    ?.addEventListener("click", saveAttachCalendar);

  document
    .getElementById("add-server-btn")
    ?.addEventListener("click", () => openServerModal("create"));

  document.getElementById("save-server")?.addEventListener("click", () => {
    const name = document.getElementById("server-name").value.trim();
    const host = document.getElementById("server-host").value.trim();
    const user = document.getElementById("server-user").value.trim();
    const port = Number(document.getElementById("server-port").value) || 22;
    const password =
      document.getElementById("server-password").value || undefined;

    if (!name || !host || !user) {
      showToast("Name, Host, and User required", "danger");
      return;
    }

    const payload = {
      host,
      user,
      port,
    };

    if (appState.currentEditServerId) {
      // EDIT: use "newname" for rename, include id
      payload.command = "update_monitor";
      payload.id = appState.currentEditServerId;
      payload.newname = name; // <-- key change here
    } else {
      // CREATE: use "name"
      payload.command = "create_monitor";
      payload.name = name;
      if (password) payload.password = password;
    }

    sendWS(payload);
    showToast(
      appState.currentEditServerId ? "Updating server..." : "Adding server...",
      "info",
    );
    document.getElementById("server-modal").classList.remove("active");
  });

  // Add Cron button in crons modal
  document.getElementById("add-cron-btn")?.addEventListener("click", () => {
    const modal = document.getElementById("crons-modal");
    const calId = modal?.dataset?.calId;

    if (!calId || isNaN(Number(calId))) {
      showToast("Cannot add cron – calendar ID missing", "danger");
      return;
    }

    console.log("[DEBUG] Add Cron clicked – calId:", calId);
    openCronModal("create", Number(calId));
  });

  // Event delegation for dynamic delete-cron buttons in crons modal
  document.addEventListener("click", (e) => {
    const deleteBtn = e.target.closest(".delete-cron");
    if (!deleteBtn) return;

    e.preventDefault();
    e.stopPropagation();

    const cronId = Number(deleteBtn.dataset.cronId);
    const calId = Number(deleteBtn.dataset.calId);

    if (isNaN(cronId) || isNaN(calId)) {
      showToast("Invalid cron or calendar ID", "danger");
      return;
    }

    openConfirmModal(
      "Confirm Delete Cron",
      "Are you sure you want to delete this cron expression? This cannot be undone.",
      () => {
        sendWS({ command: "delete_cron", id: cronId });
        showToast("Cron deleted", "success");

        // Re-open the crons modal to refresh the list
        document.getElementById("crons-modal")?.classList.remove("active");
        setTimeout(() => openCronsModal(calId), 300);
      },
      () => showToast("Delete cancelled", "info"),
    );
  });

  document.getElementById("close-log")?.addEventListener("click", () => {
    document.getElementById("log-modal").classList.remove("active");
  });

  document.getElementById("refresh-log")?.addEventListener("click", () => {
    const modal = document.getElementById("log-modal");
    const jobId = modal.dataset.jobId;
    if (jobId && appState.ws?.readyState === WebSocket.OPEN) {
      document.getElementById("log-modal-title").textContent =
        `Job ID: ${jobId} — Refreshing...`;
      document.getElementById("log-modal-subtitle").textContent = "";
      appState.ws.send(JSON.stringify({ command: "read_log", id: jobId }));
    }
  });

  // View Log History
  document.getElementById("view-history")?.addEventListener("click", () => {
    const jobId = document.getElementById("log-modal")?.dataset.jobId;

    if (!jobId) {
      showToast("No job ID found", "danger");
      return;
    }

    showLogHistoryModal(jobId);
  });

  document
    .getElementById("close-log-history")
    ?.addEventListener("click", () => {
      const modal = document.getElementById("log-history-modal");
      if (modal) modal.classList.remove("active");
    });

  // Save profile
  document.getElementById("save-profile")?.addEventListener("click", () => {
    const name = document.getElementById("edit-name").value.trim();
    const mode = document.getElementById("edit-mode").value.trim();
    if (!name && !mode) {
      showToast("No changes", "info");
      return;
    }
    if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
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
  document.getElementById("save-org")?.addEventListener("click", () => {
    const payload = { command: "update_org" };
    const name = document.getElementById("edit-org-name").value.trim();
    const desc = document.getElementById("edit-org-desc").value.trim();
    if (name) payload.name = name;
    if (desc) payload.description = desc;
    if (Object.keys(payload).length === 1) {
      showToast("No changes", "info");
      return;
    }
    if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
      appState.ws.send(JSON.stringify(payload));
      showToast("Organization update requested", "info");
    } else {
      showToast("Not connected", "danger");
    }
  });

  // Invite team modal
  document.getElementById("invite-team")?.addEventListener("click", () => {
    document.getElementById("invite-modal").classList.add("active");
    document.getElementById("invite-email").value = "";
  });

  /*
  document.getElementById("cancel-invite")?.addEventListener("click", () => {
    document.getElementById("invite-modal").classList.remove("active");
  });

  document.getElementById("close-invite")?.addEventListener("click", () => {
    document.getElementById("invite-modal").classList.remove("active");
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
      document.getElementById("invite-modal").classList.remove("active");
    } else {
      showToast("Not connected", "danger");
    }
  });

  // Global cancel button handler (for all cancel buttons in modals)
  document.addEventListener("click", (e) => {
    const cancelBtn = e.target.closest(
      '[id^="cancel-"], .btn[data-action="cancel"]',
    );
    if (cancelBtn) {
      const modal = cancelBtn.closest(".app-modal");
      if (modal) {
        modal.classList.remove("active");
      }
    }
  });
*/
});
