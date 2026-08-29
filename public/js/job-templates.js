// job-templates.js — Insert Template from window.ORDO_JOB_TEMPLATES
// Wraps window.TomSelect so #script-template uses the catalog
// instead of the hardcoded switch still in modals.js.
const CATEGORY_ORDER = ["languages", "handlers", "triggers"];

export function getJobTemplates() {
  const raw = window.ORDO_JOB_TEMPLATES;
  if (!raw || !Array.isArray(raw.items)) {
    return { categories: [], items: [], byId: {} };
  }
  const byId = {};
  for (const item of raw.items) {
    if (item && item.id) byId[item.id] = item;
  }
  return {
    categories: raw.categories || [],
    items: raw.items,
    byId,
  };
}

export function templateScript(id) {
  const { byId } = getJobTemplates();
  return byId[id]?.script ?? null;
}

let OrigTomSelect;

function installTomSelectHook() {
  if (typeof window === "undefined" || !window.TomSelect) return;
  if (window.TomSelect.__ordoCatalogHook) return;
  OrigTomSelect = window.TomSelect;
  function Wrapped(el, opts = {}) {
    const node = typeof el === "string" ? document.querySelector(el) : el;
    if (node && node.id === "script-template") {
      const isEditMode = String(opts.placeholder || "").includes("Replace");
      return initJobTemplateSelect(node, {
        isEditMode,
        onPick(_id, script) {
          const ta = document.getElementById("job-script");
          if (!ta || script == null) return;
          ta.value = script;
          ta.focus();
          ta.scrollTop = 0;
          const btn = document.getElementById("clear-script-btn");
          if (btn) btn.style.display = ta.value.trim() ? "block" : "none";
        },
      });
    }
    return new OrigTomSelect(el, opts);
  }
  Wrapped.prototype = OrigTomSelect.prototype;
  Object.assign(Wrapped, OrigTomSelect);
  Wrapped.__ordoCatalogHook = true;
  window.TomSelect = Wrapped;
}

installTomSelectHook();

export function initJobTemplateSelect(selectEl, { isEditMode, onPick } = {}) {
  if (!selectEl) return null;
  if (selectEl.tomselect) selectEl.tomselect.destroy();

  const { categories, items } = getJobTemplates();
  const catLabel = {};
  for (const c of categories) catLabel[c.id] = c.label || c.id;

  const optgroups = CATEGORY_ORDER.filter((id) =>
    items.some((i) => i.category === id),
  ).map((id) => ({
    value: id,
    label: catLabel[id] || id,
  }));

  const options = items.map((i) => ({
    value: i.id,
    text: i.label || i.id,
    optgroup: i.category,
  }));

  const Ctor = OrigTomSelect || window.TomSelect;
  const ts = new Ctor(selectEl, {
    maxItems: 1,
    placeholder: isEditMode ? "Replace with Template..." : "Insert Template...",
    dropdownParent: "body",
    maxOptions: null,
    optgroups,
    options,
    lockOptgroupOrder: true,
    controlInput: "<input>",
    onChange(value) {
      if (!value) return;
      const script = templateScript(value);
      if (script == null) {
        console.warn("Unknown template:", value);
        return;
      }
      if (typeof onPick === "function") onPick(value, script);
      this.clear(true);
    },
  });
  return ts;
}
