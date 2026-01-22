import { loadDoc } from "./ui-handlers.js";

// tabs.js – tab navigation + default activation
export function attachTabListeners() {
  const tabLinks = document.querySelectorAll(".nav-tab[data-tab]");
  console.log(`Found ${tabLinks.length} tab links`);

  tabLinks.forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault();
      const tabId = link.dataset.tab;

      // Inside your tab click/switch handler, when tabId === "docs"
      if (tabId === "docs") {
        const content = document.getElementById("docs-content");
        if (content && !content.innerHTML.trim()) {
          loadDoc("quickstart.md"); // ← one line, direct call
        }
      }

      // Dynamic import for tree timings
      if (tabId === "monitor") {
        import("./tree-table.js").then((m) => m.startTreeTimings());
      } else {
        import("./tree-table.js").then((m) => m.stopTreeTimings());
      }

      // Update active tab style
      tabLinks.forEach((l) => l.classList.remove("active"));
      link.classList.add("active");

      // Switch content visibility
      document.querySelectorAll(".tab-content").forEach((s) => {
        s.classList.remove("active");
      });

      const target = document.getElementById(tabId);
      if (target) {
        target.classList.add("active");
        console.log(`Switched to #${tabId}`);
      } else {
        console.error(`Tab content missing: #${tabId}`);
      }
    });
  });
}

export function activateDefaultTab() {
  const isLoggedIn = document.body.classList.contains("is-logged-in");
  const defaultTab = isLoggedIn ? "monitor" : "about";

  console.log(
    "Default tab content visible?",
    document.getElementById(defaultTab)?.style.display,
  );
  const link = document.querySelector(`.nav-tab[data-tab="${defaultTab}"]`);
  if (link) {
    console.log(`Activating default tab: ${defaultTab}`);
    link.click(); // Triggers the listener above
  } else {
    console.warn(`Default tab link not found: ${defaultTab}`);
  }
}
