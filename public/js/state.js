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
// Version key for collapsed clusters
const COLLAPSE_VERSION_KEY = "ordo_collapsed_version";
const CURRENT_COLLAPSE_VERSION = "1"; // ← Increment this (e.g. "2") when you change tree structure or data format

// Validate / reset on load
export function validateCollapsedStorage() {
  const storedVersion = localStorage.getItem(COLLAPSE_VERSION_KEY);
  if (storedVersion !== CURRENT_COLLAPSE_VERSION) {
    console.log(`Collapsed storage version mismatch (was ${storedVersion}, expected ${CURRENT_COLLAPSE_VERSION}). Resetting.`);
    localStorage.removeItem("ordo_collapsed_clusters");
    localStorage.setItem(COLLAPSE_VERSION_KEY, CURRENT_COLLAPSE_VERSION);
    appState.collapsedClusters.clear();
  }
}

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
