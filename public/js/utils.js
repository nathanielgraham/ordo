// utils.js – pure helper functions (no DOM, no state mutation, reusable everywhere)

import { appState } from "./state.js";


// Debug helper - pretty print the monitor tree
export function debugDumpMonitorTree(label = "after initial load") {
  const tree = appState.monitorData?.tree || [];
  
  console.group(`%c[DEBUG] monitorData.tree ${label} — ${tree.length} top-level items`, 
    'color: #00ffcc; font-weight: bold; font-size: 13px;');

  console.log('Raw tree:', tree);

  let jobCount = 0;
  let runningCount = 0;
  const runningJobs = [];

  traverseTree(tree, (item) => {
    if (!item.is_cluster) {
      jobCount++;
      if (String(item.jobstate).toLowerCase() === 'running') {
        runningCount++;
        runningJobs.push({
          id: item.id,
          name: item.name,
          started: item.started,
          runtime: item.started ? Math.floor(Date.now()/1000 - item.started) + "s" : "—"
        });
      }
    }
  });

  console.log(`Total jobs: ${jobCount} | Running: ${runningCount}`);
  if (runningJobs.length > 0) {
    console.table(runningJobs);
  }

  console.groupEnd();
}

// Date & Time Formatting
export function formatDate(epoch) {
  if (!epoch) return "—";
  return new Date(epoch * 1000).toLocaleString();
}

export function formatUptime(seconds) {
  if (typeof seconds !== 'number' || seconds <= 0 || isNaN(seconds)) {
    return "—";
  }

  const days    = Math.floor(seconds / 86400);
  seconds %= 86400;
  const hours   = Math.floor(seconds / 3600);
  seconds %= 3600;
  const minutes = Math.floor(seconds / 60);
  seconds = Math.floor(seconds % 60);

  const parts = [];
  if (days > 0)    parts.push(`${days}d`);
  if (hours > 0)   parts.push(`${hours}h`);
  if (minutes > 0) parts.push(`${minutes}m`);
  if (seconds > 0 && (days + hours + minutes === 0)) parts.push(`${seconds}s`); // only show seconds if very short

  return parts.join(" ") || "just now";
}

export function formatRelativeTime(agoSeconds) {
  if (agoSeconds < 60) return `${agoSeconds}s ago`;
  if (agoSeconds < 3600) return `${Math.floor(agoSeconds / 60)}m ago`;
  if (agoSeconds < 86400) return `${Math.floor(agoSeconds / 3600)}h ago`;
  return `${Math.floor(agoSeconds / 86400)}d ago`;
}

export function formatTplus(epoch) {
  if (!epoch || isNaN(epoch)) return "—";
  const diff = Math.floor(Date.now() / 1000) - epoch;
  if (diff <= 0) return "T+0";
  const h = Math.floor(diff / 3600).toString().padStart(2, "0");
  const m = Math.floor((diff % 3600) / 60).toString().padStart(2, "0");
  const s = (diff % 60).toString().padStart(2, "0");
  return `T+${h}:${m}:${s}`;
}

export function formatTminus(epoch) {
  if (!epoch || isNaN(epoch)) return "—";

  const now = Math.floor(Date.now() / 1000);
  const diff = epoch - now;

  if (diff <= 0) return "Overdue";

  // Show days if more than 24 hours
  if (diff >= 86400) {
    const days = Math.floor(diff / 86400);
    const remaining = diff % 86400;
    const h = Math.floor(remaining / 3600).toString().padStart(2, "0");
    const m = Math.floor((remaining % 3600) / 60).toString().padStart(2, "0");
    return `T+${days}d ${h}:${m}`;
  }

  // Normal HH:MM:SS format
  const h = Math.floor(diff / 3600).toString().padStart(2, "0");
  const m = Math.floor((diff % 3600) / 60).toString().padStart(2, "0");
  const s = (diff % 60).toString().padStart(2, "0");

  return `T-${h}:${m}:${s}`;
}

export function formatDuration(start, end) {
  if (!start) return "—";
  const endTime = end || Math.floor(Date.now() / 1000);
  const diff = endTime - start;
  if (diff <= 0) return "—";
  const h = Math.floor(diff / 3600).toString().padStart(2, "0");
  const m = Math.floor((diff % 3600) / 60).toString().padStart(2, "0");
  const s = (diff % 60).toString().padStart(2, "0");
  return `${h}:${m}:${s}`;
}

// Tree Data Helpers
export function traverseTree(items, callback) {
  if (!items) return;
  const list = Array.isArray(items) ? items : [items];

  for (const item of list) {
    if (!item) continue;
    callback(item);

    if (item.jobs && Array.isArray(item.jobs)) {
      traverseTree(item.jobs, callback);
    }
    if (item.children && Array.isArray(item.children)) {
      traverseTree(item.children, callback);
    }
  }
}

export function removeJobById(tree, id) {
  const targetId = Number(id);
  if (!targetId || !tree) return false;

  let removed = false;

  traverseTree(tree, (item) => {
    if (item.is_cluster && item.jobs && Array.isArray(item.jobs)) {
      const originalLength = item.jobs.length;
      
      item.jobs = item.jobs.filter(job => Number(job.id) !== targetId);

      if (item.jobs.length < originalLength) {
        removed = true;
      }
    }
  });

  return removed;
}

export function findClusterById(tree, id) {
  const targetId = Number(id);
  if (!targetId || !tree) return null;

  let found = null;

  traverseTree(tree, (item) => {
    if (item.is_cluster && Number(item.id) === targetId) {
      found = item;
    }
  });

  return found;
}

export function findJobById(tree, id) {
  const targetId = Number(id);
  if (!targetId || !tree) return null;

  let found = null;

  traverseTree(tree, (item) => {
    if (!item.is_cluster && Number(item.id) === targetId) {
      found = item;
    }
  });

  return found;
}

export function buildTree(data) {
  const nodes = new Map();
  const root = { id: "root", children: [], depth: 0 };

  data.clusters.forEach((c) => {
    const node = {
      ...c,
      id: Number(c.id),
      type: "cluster",
      is_cluster: true,
      children: c.jobs?.map((j) => ({
        ...j,
        id: Number(j.id),
        type: "job",
        is_cluster: false,
        depth: 0,
      })) || [],
      depth: 0,
    };
    nodes.set(node.id, node);
  });

  data.clusters.forEach((c) => {
    const node = nodes.get(Number(c.id));
    if (c.parent_id == null) {
      root.children.push(node);
      node.depth = 0;
    } else {
      const parent = nodes.get(Number(c.parent_id));
      if (parent) {
        parent.children.push(node);
        node.depth = parent.depth + 1;
      } else {
        root.children.push(node);
        node.depth = 0;
      }
    }
    node.children.forEach((job) => (job.depth = node.depth + 1));
  });

  return root.children;
}

export function findServerById(id) {
  return appState.serversData.find(s => s.id === Number(id)) || null;
}

export function getFullPath(node) {
  if (!node) return "—";

  let path = node.name + (node.is_cluster ? "/" : "");

  if (node.parent_id) {
    const parent = findClusterById(appState.monitorData.tree, node.parent_id);
    if (parent) {
      if (!parent.is_cluster) {
        console.error("[getFullPath] Parent is not a cluster for node", node.id);
      } else {
        path = getFullPath(parent) + path;
      }
    } else {
      console.warn("[getFullPath] No parent cluster found for node", node.id);
    }
  }

  return path;
}

// Data removal helpers (pure, recursive)
export function removeClusterById(items, id) {
  id = Number(id);
  for (let i = 0; i < items.length; i++) {
    if (items[i].id === id && items[i].is_cluster) {
      items.splice(i, 1);
      return true;
    }
    if (items[i].children) {
      if (removeClusterById(items[i].children, id)) return true;
    }
  }
  return false;
}

// utils.js – add this function at the end (if it's not already there)
export function resolveDepName(id, tree, isCluster = false) {
  id = Number(id);
  let node = null;
  if (isCluster) {
    node = findClusterById(tree, id);
  } else {
    node = findJobById(tree, id);
  }
  if (node) {
    return getFullPath(node);
  } else {
    return `ID:${id} (missing or type mismatch)`;
  }
}

// ==================== HASH REDIRECT UTILITY ====================

/**
 * Navigate to a specific tab (and optional submenu)
 * Example: goToTab('docs', 'quickstart')
 *          goToTab('settings')
 */
export function goToTab(tabName, subItem = null) {
  let hash = tabName;
  if (subItem) {
    hash += '/' + subItem;
  }

  console.log(`[goToTab] Navigating to #${hash}`);
  window.location.hash = hash;
}

// Optional: Also trigger immediately if needed
export function goToTabAndActivate(tabName, subItem = null) {
  goToTab(tabName, subItem);
  // The hash handler will take care of activation
}

// utils.js or new const in ui-handlers.js
export const commonTimezones = [
  "UTC",
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Phoenix",
  "Europe/London",
  "Europe/Paris",
  "Europe/Berlin",
  "Europe/Moscow",
  "Asia/Tokyo",
  "Asia/Shanghai",
  "Asia/Singapore",
  "Asia/Kolkata",
  "Australia/Sydney",
  "Pacific/Auckland",
  "America/Toronto",
  "America/Vancouver",
  "Europe/Amsterdam",
  "Europe/Stockholm",
  "Asia/Dubai",
  "Asia/Hong_Kong",
  "Asia/Seoul",
  "Europe/Madrid",
  "Europe/Rome",
  "America/Sao_Paulo",
  "Africa/Johannesburg",
  "America/Mexico_City",
  "Asia/Bangkok",
  "Pacific/Honolulu",
  // Add more as needed
];

