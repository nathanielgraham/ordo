// utils.js – pure helper functions (no DOM, no state mutation, reusable everywhere)

import { appState } from "./state.js";

// Date & Time Formatting
export function formatDate(epoch) {
  if (!epoch) return "—";
  return new Date(epoch * 1000).toLocaleString();
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
  const diff = epoch - Math.floor(Date.now() / 1000);
  if (diff <= 0) return "Overdue";
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

export function findClusterById(items, id) {

  if (!Array.isArray(items)) {
    console.warn("[DEBUG] findClusterById: items is NOT an array - returning null");
    return null;
  }

  id = Number(id);
  for (let item of items) {
    if (item.id === id && item.is_cluster) {
      return item;
    }
    if (item.children) {
      const found = findClusterById(item.children, id);
      if (found) return found;
    }
  }
  return null;
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

/*
export function getFullPath(node, tree = []) {
  console.log(`[DEBUG] getFullPath called with node:`, node, "tree length:", tree.length);

  if (!node || !tree) {
    console.warn("[DEBUG] getFullPath: invalid node or tree - returning fallback");
    return node?.name + (node?.is_cluster ? "/" : "") || "—";
  }

  if (!node.parent_id) {
    return node.name + (node.is_cluster ? "/" : "");
  }

  const parent = findClusterById(tree, node.parent_id);
  if (!parent) {
    console.warn("[DEBUG] getFullPath: parent not found for node", node);
    return node.name + (node.is_cluster ? "/" : "");
  }

  return getFullPath(parent, tree) + node.name + (node.is_cluster ? "/" : "");
}
*/

export function findJobById(items, id) {
  id = Number(id);
  for (let item of items) {
    if (item.id === id && !item.is_cluster) return item;
    if (item.children) {
      const found = findJobById(item.children, id);
      if (found) return found;
    }
  }
  return null;
}

// State & UI Mapping (pure)
export function stateClass(state) {
  if (!state) return "ordo-default";
  const lowerState = state.toLowerCase();
  if (["complete"].includes(lowerState)) return "ordo-complete";
  if (["immutable", "ice", "pruned"].includes(lowerState)) return "ordo-immutable";
  if (lowerState === "running") return "ordo-running";
  if (["failed", "hold", "zombie", "killed"].includes(lowerState)) return "ordo-failed";
  if (["ready", "waiting", "looping", "retrying"].includes(lowerState)) return "ordo-ready";
  return "ordo-default";
}

/*
export function getStateColor(state) {
  if (!state) return "#97C2FC";
  const lower = state.toLowerCase();
  if (["complete", "success"].includes(lower)) return "#4CAF50";
  if (lower === "running") return "#2196F3";
  if (["failed", "killed", "zombie"].includes(lower)) return "#F44336";
  if (["hold", "ice"].includes(lower)) return "#FF9800";
  if (lower === "immutable") return "#9C27B0";
  return "#9E9E9E";
}
*/

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

export function removeJobById(items, id) {
  id = Number(id);
  for (let i = 0; i < items.length; i++) {
    if (items[i].id === id && !items[i].is_cluster) {
      items.splice(i, 1);
      return true;
    }
    if (items[i].children) {
      if (removeJobById(items[i].children, id)) return true;
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

