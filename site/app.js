const repository = "https://github.com/Hecatoncheir/amnezia-proxy-manager";
const platforms = {
  windows: {
    label: "Windows",
    file: "AmneziaProxyManager-Setup-windows-x64.exe",
  },
  macos: { label: "macOS", file: "AmneziaProxyManager-macos-arm64.dmg" },
  linux: { label: "Linux", file: "AmneziaProxyManager-linux-x64.run" },
};
const platformButtons = [...document.querySelectorAll("[data-platform]")];
const modeButtons = [...document.querySelectorAll("button[data-mode]")];
const illustration = document.querySelector(".illustration");
const themeButton = document.querySelector(".theme-button");
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
let selectedPlatform;
let downloadAnimation;

function selectPlatform(platform, animate = false) {
  const target = platforms[platform];
  if (!target) return;
  if (animate && selectedPlatform === platform) return;
  selectedPlatform = platform;
  document.querySelector("#download").href =
    `${repository}/releases/latest/download/${target.file}`;
  document.querySelector("#download-label").textContent =
    `Скачать для ${target.label}`;
  const index = platformButtons.findIndex(
    (button) => button.dataset.platform === platform,
  );
  document
    .querySelector(".platforms")
    .style.setProperty("--platform-index", index);
  platformButtons.forEach((button) =>
    button.setAttribute(
      "aria-pressed",
      String(button.dataset.platform === platform),
    ),
  );
  if (animate) animateDownloadLabel();
}

function animateDownloadLabel() {
  if (reducedMotion.matches) return;
  downloadAnimation?.cancel();
  downloadAnimation = document.querySelector("#download-label").animate(
    [
      { opacity: 0, transform: "translateY(7px)" },
      { opacity: 1, transform: "translateY(0)" },
    ],
    { duration: 240, easing: "cubic-bezier(.2,.7,.3,1)" },
  );
}

function detectedPlatform() {
  if (/Macintosh|Mac OS X/.test(navigator.userAgent)) return "macos";
  if (/Linux/.test(navigator.userAgent) && !/Android/.test(navigator.userAgent))
    return "linux";
  return "windows";
}

function selectMode(mode) {
  if (!["all", "proxy"].includes(mode)) return;
  illustration.dataset.mode = mode;
  modeButtons.forEach((button) =>
    button.setAttribute("aria-pressed", String(button.dataset.mode === mode)),
  );
  document.querySelector(".mode-caption").textContent =
    mode === "all"
      ? "Локальные прокси остаются доступны."
      : "Через VPN идут программы с настроенным прокси.";
}

function setTheme(theme) {
  document.documentElement.dataset.theme = theme;
  themeButton.setAttribute(
    "aria-label",
    theme === "dark" ? "Включить светлую тему" : "Включить тёмную тему",
  );
  document.querySelector('meta[name="theme-color"]').content =
    theme === "dark" ? "#22251f" : "#f3f0e2";
}

function readTheme() {
  try {
    const theme = localStorage.getItem("amnezia-theme");
    if (["dark", "light"].includes(theme)) return theme;
  } catch {
    /* Хранилище может быть недоступно в приватном режиме. */
  }
  return "dark";
}

function toggleTheme() {
  const theme =
    document.documentElement.dataset.theme === "dark" ? "light" : "dark";
  setTheme(theme);
  try {
    localStorage.setItem("amnezia-theme", theme);
  } catch {
    /* Тема работает и без сохранения. */
  }
}

async function showRelease() {
  try {
    const response = await fetch(
      "https://api.github.com/repos/Hecatoncheir/amnezia-proxy-manager/releases/latest",
      { signal: AbortSignal.timeout(5000) },
    );
    if (!response.ok) return;
    const release = await response.json();
    if (!isStableRelease(release)) return;
    document.querySelector("#release").textContent =
      `${release.tag_name} · Что нового ↗`;
  } catch {
    /* При ошибке остаётся обычная ссылка на последний выпуск. */
  }
}

function isStableRelease(release) {
  return (
    !release.draft &&
    !release.prerelease &&
    /^v\d+\.\d+\.\d+$/.test(release.tag_name)
  );
}

function tiltIllustration(event) {
  if (event.pointerType !== "mouse") return;
  const bounds = illustration.getBoundingClientRect();
  const x = (event.clientX - bounds.left) / bounds.width - 0.5;
  const y = (event.clientY - bounds.top) / bounds.height - 0.5;
  illustration.style.setProperty("--tilt-x", `${-y * 4}deg`);
  illustration.style.setProperty("--tilt-y", `${x * 4}deg`);
}

function resetTilt() {
  illustration.style.setProperty("--tilt-x", "0deg");
  illustration.style.setProperty("--tilt-y", "0deg");
}

platformButtons.forEach((button) =>
  button.addEventListener("click", () =>
    selectPlatform(button.dataset.platform, true),
  ),
);
modeButtons.forEach((button) =>
  button.addEventListener("click", () => selectMode(button.dataset.mode)),
);
themeButton.addEventListener("click", toggleTheme);
document.addEventListener("visibilitychange", () => {
  document.documentElement.dataset.paused = String(document.hidden);
});
if (!reducedMotion.matches) {
  illustration.addEventListener("pointermove", tiltIllustration);
  illustration.addEventListener("pointerleave", resetTilt);
}
selectPlatform(detectedPlatform());
setTheme(readTheme());
showRelease();
