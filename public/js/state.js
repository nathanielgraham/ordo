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
  currentEditCalId: null,
  currentEditServerId: null,
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
  console.log("[DEBUG STORAGE] Loaded collapsedClusters:", [...appState.collapsedClusters]);
}

export function getCollapsedIds() {
  try {
    const stored = localStorage.getItem(COLLAPSE_KEY);
    return stored ? new Set(JSON.parse(stored)) : new Set();
  } catch {
    return new Set();
  }
}

export function updateCollapsedClusters() {
  try {
    const array = [...appState.collapsedClusters];
    console.log("[DEBUG STORAGE] Saving collapsed IDs to localStorage:", array);
    localStorage.setItem(COLLAPSE_KEY, JSON.stringify(array));
    console.log("[DEBUG STORAGE] Save complete - verify in devtools Application > Local Storage");
  } catch (e) {
    console.error("[DEBUG STORAGE] Save failed:", e);
  }
}
