// state.js – shared mutable application state
export const appState = {
  ws: null,

  // === AUTHORITATIVE DATA SOURCES (NEW) ===
  jobsMap: new Map(),           // job.id → job object
  clustersMap: new Map(),       // cluster.id → cluster object

  // === LEGACY / DISPLAY LAYER ===
  monitorData: { tree: [] },    // still maintained incrementally for now

  // === ACCOUNT & ORG ===
  accountData: null,
  orgData: null,

  // === OTHER DATA ===
  calendarsData: [],
  serversData: [],
  dashboardStats: {},

  // === UI / MODAL STATE (IMPORTANT - DO NOT REMOVE) ===
  currentEditItem: null,
  currentParentId: null,
  currentParentName: null,
  currentAttachClusterId: null,
  currentEditCalId: null,
  currentEditServerId: null,

  // === TAB & COLLAPSE STATE ===
  currentTab: "docs",          // safe default

  collapsedClusters: new Set(
    JSON.parse(localStorage.getItem("ordo_collapsed_clusters") || "[]")
  ),
  collapsedCalendars: new Set(
    JSON.parse(localStorage.getItem("ordo_collapsed_calendars") || "[]")
  ),

  // Dashboard flag
  dashboardStatsLoaded: false,
};

/*
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
  collapsedCalendars: new Set(
    JSON.parse(localStorage.getItem("ordo_collapsed_calendars") || "[]")
  ),
};
*/

// New persistence functions
const CAL_COLLAPSE_KEY = "ordo_collapsed_calendars";
const CAL_COLLAPSE_VERSION_KEY = "ordo_collapsed_calendars_version";
const CURRENT_CAL_COLLAPSE_VERSION = "1";

export function validateCalendarCollapsedStorage() {
  const storedVersion = localStorage.getItem(CAL_COLLAPSE_VERSION_KEY);
  if (storedVersion !== CURRENT_CAL_COLLAPSE_VERSION) {
    console.log(`Calendar collapsed version mismatch. Resetting.`);
    localStorage.removeItem(CAL_COLLAPSE_KEY);
    localStorage.setItem(CAL_COLLAPSE_VERSION_KEY, CURRENT_CAL_COLLAPSE_VERSION);
    appState.collapsedCalendars.clear();
  }
}

export function updateCalendarCollapsed() {
  try {
    const array = [...appState.collapsedCalendars];
    localStorage.setItem(CAL_COLLAPSE_KEY, JSON.stringify(array));
  } catch (e) {
    console.error("Failed to save calendar collapsed state:", e);
  }
}

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
