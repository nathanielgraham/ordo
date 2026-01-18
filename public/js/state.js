// state.js – shared mutable application state

export const appState = {
  ws: null,
  monitorData: { tree: [] },
  accountData: null,
  orgData: null,
  calendarsData: [],
  serversData: [],
  currentEditItem: null,
  currentParentId: null,
  currentParentName: null,
  currentAttachClusterId: null,
  collapsedClusters: new Set(
    JSON.parse(localStorage.getItem("ordo_collapsed_clusters") || "[]")
  ),
};

// Persistence helpers for collapsed clusters
const COLLAPSE_KEY = "ordo_collapsed_clusters";

export function getCollapsedIds() {
  try {
    const stored = localStorage.getItem(COLLAPSE_KEY);
    return stored ? new Set(JSON.parse(stored)) : new Set();
  } catch {
    return new Set();
  }
}

export function saveCollapsedIds(set) {
  try {
    localStorage.setItem(COLLAPSE_KEY, JSON.stringify([...set]));
  } catch {}
}

export function updateCollapsedClusters() {
  saveCollapsedIds(appState.collapsedClusters);
}
