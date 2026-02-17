// tabs.js – tab navigation + default activation
import { loadDoc } from "./ui-handlers.js";
import { startLiveTimings, stopLiveTimings } from "./tree/tree-table.js";

export function attachTabListeners() {
  const tabLinks = document.querySelectorAll(".nav-tab[data-tab]");
  console.log(`Found ${tabLinks.length} tab links`);
  tabLinks.forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault();
      const tabId = link.dataset.tab;

      // === DEBUG START ===
      console.log("[DEBUG] Tab clicked:", tabId);
      console.log(
        "[DEBUG] All section elements in DOM:",
        document.querySelectorAll("section"),
      );
      console.log(
        "[DEBUG] All section IDs:",
        Array.from(document.querySelectorAll("section"))
          .map((s) => s.id)
          .filter(Boolean),
      );
      console.log(
        "[DEBUG] Direct getElementById('servers'):",
        document.getElementById("servers"),
      );
      console.log(
        "[DEBUG] Query selector for #servers:",
        document.querySelector("#servers"),
      );
      console.log(
        "[DEBUG] Query selector for section[id='servers']:",
        document.querySelector("section[id='servers']"),
      );
      // === DEBUG END ===

      if (tabId === "docs") {
        const content = document.getElementById("docs-content");
        if (content && !content.innerHTML.trim()) {
          loadDoc("quickstart.md");
        }
      }
      // Dynamic import for tree timings

if (tabId === "monitor" || tabId === "servers" || tabId === "calendars") {
  startLiveTimings();
} else {
  stopLiveTimings();
}

      // Update active tab style
      tabLinks.forEach((l) => l.classList.remove("active"));
      link.classList.add("active");

      // Switch content visibility
      document
        .querySelectorAll(".tab-content")
        .forEach((s) => s.classList.remove("active"));

      // Robust lookup with fallback
      let target = document.getElementById(tabId);
      if (!target) {
        console.warn(
          "[DEBUG] getElementById failed — trying querySelector fallback",
        );
        target = document.querySelector(`section[id="${tabId}"]`);
      }
      if (target) {
        target.classList.add("active");
        console.log(`[DEBUG] Successfully activated #${tabId}`);
      } else {
        console.error(`Tab content missing: #${tabId}`);
      }
    });
  });
}

export function activateDefaultTab() {
  const isLoggedIn = document.body.classList.contains("is-logged-in");
  const defaultTab = isLoggedIn ? "servers" : "about";
  const link = document.querySelector(`.nav-tab[data-tab="${defaultTab}"]`);
  if (link) {
    link.click();
  } else {
    console.warn(`Default tab link not found: ${defaultTab}`);
  }
}
