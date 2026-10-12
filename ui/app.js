"use strict";

(() => {
  const $ = selector => document.querySelector(selector);
  const $$ = selector => [...document.querySelectorAll(selector)];
  const pages = ["movement", "keybinds", "settings"];
  const keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];
  const timingFields = ["wInterval", "clickDelay", "weaponReturnDelay", "runResumeDelay"];
  const channel = window.chrome?.webview;
  const queue = [];
  let page = "movement";
  let state = null;
  let requestNumber = 0;
  let inFlight = null;
  let toastTimeout = null;
  let busyTimeout = null;
  let layoutFrame = null;
  let lastHeight = 0;
  let captureSlot = null;

  function cancelCapture() {
    if (captureSlot === null) return;
    const button = $(`[data-trigger="${captureSlot}"]`);
    button.removeAttribute("data-capturing");
    button.textContent = `[${state ? state.settings.triggers[captureSlot] : captureSlot}]`;
    captureSlot = null;
    if ($("#toast").dataset.level === "capture") $("#toast").hidden = true;
  }

  function beginCapture(slot) {
    cancelCapture();
    if (!state || inFlight) return;
    captureSlot = slot;
    const button = $(`[data-trigger="${slot}"]`);
    button.dataset.capturing = "true";
    button.textContent = "…";
    button.focus();
    notice("capture", "Pressione a nova tecla do jogo. Esc cancela.");
  }

  function captureKey(event) {
    if (captureSlot === null) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.repeat) return;
    if (event.key === "Escape") { cancelCapture(); return; }
    if (event.ctrlKey || event.altKey || event.metaKey || event.code.startsWith("Numpad")) {
      notice("capture", "Use uma tecla sem Ctrl, Alt ou Win; numpad não é aceito. Esc cancela.");
      return;
    }
    const aliases = { " ": "Space", ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left",
      ArrowRight: "Right", PageUp: "PgUp", PageDown: "PgDn" };
    const key = aliases[event.key] || (/^[a-z]$/i.test(event.key) ? event.key.toUpperCase() : event.key);
    if (!state.triggerKeys.includes(key)) {
      notice("capture", key === "W" ? "W é reservada ao Double Tap. Escolha outra tecla; Esc cancela."
        : "Tecla não suportada. Use letras, 1–0, F1–F12 ou teclas de navegação. Esc cancela.");
      return;
    }
    const slot = captureSlot;
    cancelCapture();
    send(`trigger|${slot}|${key}`);
  }

  function navigate(nextPage) {
    if (!pages.includes(nextPage)) return;
    cancelCapture();
    page = nextPage;
    pages.forEach(name => { $(`#page-${name}`).hidden = name !== page; });
    $$(".nav-item").forEach(button => {
      const selected = button.dataset.page === page;
      button.classList.toggle("active", selected);
      button.setAttribute("aria-selected", String(selected));
      button.tabIndex = selected ? 0 : -1;
    });
    $("main").scrollTop = 0;
    scheduleLayout();
  }

  function scheduleLayout() {
    if (!channel || !state) return;
    cancelAnimationFrame(layoutFrame);
    layoutFrame = requestAnimationFrame(() => {
      const mainStyle = getComputedStyle($("main"));
      const height = Math.ceil($(".app-header").getBoundingClientRect().height
        + $(`#page-${page}`).getBoundingClientRect().height
        + parseFloat(mainStyle.paddingTop) + parseFloat(mainStyle.paddingBottom) + 8);
      const boundedHeight = Math.max(200, Math.min(600, height));
      if (boundedHeight === lastHeight) return;
      lastHeight = boundedHeight;
      send(`layout|${boundedHeight}`);
    });
  }

  function setBusy() {
    const disabled = !channel || !state || Boolean(inFlight);
    $$("[data-control]").forEach(control => { control.disabled = disabled; });
    $("#master-button").setAttribute("aria-busy", String(Boolean(inFlight)));
  }

  function send(command) {
    if (!channel) return;
    queue.push(command);
    dispatch();
  }

  function dispatch() {
    if (inFlight || queue.length === 0) return;
    inFlight = { id: ++requestNumber, command: queue.shift() };
    setBusy();
    if (inFlight.command !== "ready" && !inFlight.command.startsWith("layout|"))
      busyTimeout = setTimeout(() => notice("pending", "Salvando…"), 180);
    try { channel.postMessage(`${inFlight.id}|${inFlight.command}`); }
    catch {
      clearTimeout(busyTimeout);
      queue.length = 0;
      // Controls stay disabled until there is a confirmed engine connection.
      notice("error", "Conexão perdida. Reabra Marco (Bloodlines).");
    }
  }

  function notice(level, message) {
    clearTimeout(toastTimeout);
    const toast = $("#toast");
    toast.dataset.level = level;
    toast.textContent = message;
    toast.hidden = false;
    if (level !== "pending" && level !== "capture")
      toastTimeout = setTimeout(() => { toast.hidden = true; }, level === "error" ? 7000 : 1600);
  }

  function paintRange(field, value) {
    $(`#${field}-range`).value = value;
    $(`#${field}-number`).value = value;
  }

  function focusLabel(status) {
    return status === "Connected" ? "focused" : status === "Unfocused" ? "idle" : "off";
  }

  function render(message) {
    if (state && message.revision <= state.revision) return;
    state = message;
    const settings = message.settings;
    const master = Boolean(settings.masterEnabled);
    const status = focusLabel(message.robloxStatus);
    $$("[data-version]").forEach(node => { node.textContent = `v${message.version}`; });
    $("[data-roblox-status]").textContent = status;
    $(".connection").dataset.status = status;
    $(".connection").title = status === "focused" ? "Roblox em primeiro plano"
      : status === "idle" ? "Roblox aberto, fora de foco" : "Roblox não detectado";
    $("#master-button").setAttribute("aria-checked", String(master));
    $("#master-button span").textContent = master ? "on" : "off";
    $$("[data-setting]").forEach(button => {
      const enabled = Boolean(settings[button.dataset.setting]);
      button.setAttribute("aria-checked", String(enabled));
      button.querySelector("span").textContent = enabled ? "on" : "off";
    });
    const acknowledged = inFlight && message.ack === inFlight.id;
    timingFields.forEach(field => {
      // Focus snapshots should not replace a value the user is still editing.
      const editing = document.activeElement === $(`#${field}-number`)
        || document.activeElement === $(`#${field}-range`);
      const ownAck = acknowledged && inFlight.command.startsWith(`set|${field}|`);
      if (!editing || ownAck) paintRange(field, settings[field]);
    });
    keys.forEach(key => {
      const entry = $(`[data-key="${key}"]`);
      entry.dataset.action = settings.binds[key];
      entry.querySelector("select").value = settings.binds[key];
      const trigger = entry.querySelector("[data-trigger]");
      if (captureSlot !== key) trigger.textContent = `[${settings.triggers[key]}]`;
      trigger.setAttribute("aria-label", `Alterar tecla do autocast: ${settings.triggers[key]}`);
      trigger.title = `Tecla do jogo: ${settings.triggers[key]}. Clique e pressione a substituta. Esc cancela.`;
      entry.querySelector("select").setAttribute("aria-label", `Ação da tecla ${settings.triggers[key]}`);
    });
    const weapon = keys.find(key => settings.binds[key] === "weapon");
    $("#weapon-return-row").hidden = !weapon;
    $("[data-weapon-key]").textContent = weapon ? `[${settings.triggers[weapon]}]` : "";
    $("#run-resume-row").hidden = !settings.resumeAfterM1;
    if (acknowledged) {
      const command = inFlight.command;
      clearTimeout(busyTimeout);
      inFlight = null;
      if (command !== "ready" && command !== "defaults" && !command.startsWith("layout|"))
        notice("success", "Salvo");
      dispatch();
    }
    setBusy();
    scheduleLayout();
  }

  // Five rows, two columns. Snapshots update controls without rebuilding them.
  keys.forEach(key => {
    const entry = document.createElement("div");
    entry.className = "key-entry";
    entry.dataset.key = key;
    entry.dataset.action = "disabled";
    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "trigger-key";
    trigger.dataset.trigger = key;
    trigger.dataset.control = "";
    trigger.textContent = `[${key}]`;
    trigger.disabled = true;
    trigger.addEventListener("click", () => beginCapture(key));
    trigger.addEventListener("blur", () => { if (captureSlot === key) cancelCapture(); });
    const select = document.createElement("select");
    select.id = `binding-${key}`;
    select.setAttribute("aria-label", `Ação da tecla ${key}`);
    select.title = "Weapon: seleciona a arma após o autocast, sem clique próprio. Apenas uma tecla pode ser Weapon.";
    select.dataset.control = "";
    select.disabled = true;
    [["disabled", "Disabled"], ["left", "Left Click"], ["right", "Right Click"], ["weapon", "Weapon"]].forEach(([value, title]) => {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = title;
      select.append(option);
    });
    select.addEventListener("change", () => send(`bind|${key}|${select.value}`));
    entry.append(trigger, select);
    $("#key-grid").append(entry);
  });

  $$(".nav-item").forEach(button => {
    button.addEventListener("click", () => navigate(button.dataset.page));
    button.addEventListener("keydown", event => {
      const current = pages.indexOf(button.dataset.page);
      let next;
      if (event.key === "ArrowRight") next = (current + 1) % pages.length;
      else if (event.key === "ArrowLeft") next = (current + pages.length - 1) % pages.length;
      else if (event.key === "Home") next = 0;
      else if (event.key === "End") next = pages.length - 1;
      else return;
      event.preventDefault();
      navigate(pages[next]);
      $(`#tab-${pages[next]}`).focus();
    });
  });
  $$("[data-setting]").forEach(button => button.addEventListener("click", () => {
    if (state && !inFlight)
      send(`set|${button.dataset.setting}|${state.settings[button.dataset.setting] ? 0 : 1}`);
  }));
  $("#master-button").addEventListener("click", () => send("toggle"));
  timingFields.forEach(field => {
    const range = $(`#${field}-range`);
    const number = $(`#${field}-number`);
    range.addEventListener("input", () => paintRange(field, range.value));
    range.addEventListener("change", () => send(`set|${field}|${range.value}`));
    number.addEventListener("change", () => {
      const value = Number(number.value);
      if (number.value.trim() === "" || !Number.isInteger(value) || value < Number(number.min) || value > Number(number.max)) {
        notice("error", `Intervalo permitido: ${number.min}–${number.max} ms.`);
        if (state) paintRange(field, state.settings[field]);
        return;
      }
      paintRange(field, value);
      send(`set|${field}|${value}`);
    });
    number.addEventListener("keydown", event => { if (event.key === "Enter") number.blur(); });
    number.addEventListener("blur", () => {
      if (state && !inFlight) paintRange(field, state.settings[field]);
    });
  });

  const dialog = $("#reset-dialog");
  document.addEventListener("keydown", captureKey, true);
  window.addEventListener("blur", cancelCapture);
  $("#reset-button").addEventListener("click", () => dialog.showModal());
  $("#reset-cancel").addEventListener("click", () => dialog.close());
  $("#reset-confirm").addEventListener("click", () => { dialog.close(); send("defaults"); });
  $("#toast").addEventListener("click", () => { $("#toast").hidden = true; });
  const layoutObserver = new ResizeObserver(scheduleLayout);
  pages.forEach(name => layoutObserver.observe($(`#page-${name}`)));
  layoutObserver.observe($(".app-header"));
  if (channel) {
    channel.addEventListener("message", event => {
      const message = event.data;
      if (!message || typeof message !== "object") return;
      if (message.type === "state") render(message);
      else if (message.type === "notice") notice(message.level, message.message);
    });
    send("ready");
  } else {
    $("[data-roblox-status]").textContent = "off";
    $("#master-button span").textContent = "off";
    notice("error", "Abra Bloodlines.ahk ou MarcoBloodlines.exe.");
  }
})();
