const WAIT_MS = 80;
const MAX_WAIT_ATTEMPTS = 100;

const allowedArchivePattern =
  /\.(tar\.gz|tgz|tar\.bz2|tbz|tbz2|tar\.xz|txz|zip|gem|jar|war|gz|xz|bz2)(\?.*)?$/i;

function waitForBridge(attempt = 0) {
  if (window.BrewVersionCheck) {
    init(window.BrewVersionCheck);
    return;
  }

  if (attempt >= MAX_WAIT_ATTEMPTS) {
    renderBridgeFailure();
    return;
  }

  window.setTimeout(() => waitForBridge(attempt + 1), WAIT_MS);
}

function init(bridge) {
  const formulaEl = document.getElementById("formulaName");
  const urlEl = document.getElementById("sourceUrl");
  const declaredEl = document.getElementById("declaredVersion");
  const checkBtn = document.getElementById("checkBtn");

  checkBtn.addEventListener("click", async () => {
    const formulaName = formulaEl.value.trim();
    const sourceUrl = urlEl.value.trim();
    const declaredVersion = declaredEl.value.trim();

    if (!sourceUrl) {
      renderResult({
        status: "fail",
        title: "Source URL required",
        summary: "Enter a URL so the checker can run Homebrew-style version detection.",
        checks: [{ status: "fail", message: "No URL provided." }],
      });
      return;
    }

    checkBtn.disabled = true;
    checkBtn.textContent = "Checking...";

    try {
      const checks = [];
      const detectedVersion = bridge.detectVersion(sourceUrl);

      if (!detectedVersion) {
        checks.push({
          status: "fail",
          message: "Homebrew parser could not detect a version from this URL.",
        });
      } else {
        checks.push({
          status: "ok",
          message: `Detected version from URL: ${detectedVersion}`,
        });
      }

      const secure = sourceUrl.startsWith("https://");
      checks.push({
        status: secure ? "ok" : "warn",
        message: secure
          ? "URL uses HTTPS."
          : "URL does not use HTTPS. Homebrew/core generally expects secure source URLs.",
      });

      checks.push({
        status: allowedArchivePattern.test(sourceUrl) ? "ok" : "warn",
        message: allowedArchivePattern.test(sourceUrl)
          ? "URL appears to target a common source archive extension."
          : "URL extension is uncommon for source archives; verify Homebrew download strategy support.",
      });

      if (declaredVersion) {
        const declaredParsed = bridge.parseVersion(declaredVersion);
        if (!declaredParsed) {
          checks.push({
            status: "fail",
            message: "Declared version is not parseable by Homebrew version logic.",
          });
        } else if (detectedVersion) {
          const cmp = bridge.compareVersions(detectedVersion, declaredParsed);
          if (cmp === 0) {
            checks.push({
              status: "ok",
              message: `Declared version matches detected URL version (${declaredParsed}).`,
            });
          } else {
            checks.push({
              status: "fail",
              message: `Declared version (${declaredParsed}) does not match detected URL version (${detectedVersion}).`,
            });
          }
        }
      }

      if (formulaName) {
        const formulaCheck = await compareAgainstStableFormula(bridge, formulaName, detectedVersion);
        checks.push(formulaCheck);
      }

      const status = overallStatus(checks);
      renderResult({
        status,
        title: statusTitle(status),
        summary: buildSummary(status, detectedVersion),
        checks,
      });
    } catch (error) {
      renderResult({
        status: "fail",
        title: "Check failed",
        summary: "Unexpected error while running checks.",
        checks: [{ status: "fail", message: String(error) }],
      });
    } finally {
      checkBtn.disabled = false;
      checkBtn.textContent = "Check Compatibility";
    }
  });
}

async function compareAgainstStableFormula(bridge, formulaName, detectedVersion) {
  try {
    const response = await fetch(
      `https://formulae.brew.sh/api/formula/${encodeURIComponent(formulaName)}.json`
    );

    if (!response.ok) {
      return {
        status: "warn",
        message: `Could not fetch formula metadata for '${formulaName}' from formulae.brew.sh.`,
      };
    }

    const formulaData = await response.json();
    const stableVersion = formulaData?.versions?.stable;

    if (!stableVersion) {
      return {
        status: "warn",
        message: `Formula '${formulaName}' has no stable version in API response.`,
      };
    }

    if (!detectedVersion) {
      return {
        status: "warn",
        message: `Current stable for '${formulaName}' is ${stableVersion}; URL version could not be compared.`,
      };
    }

    const cmp = bridge.compareVersions(detectedVersion, stableVersion);
    if (cmp === null || cmp === undefined) {
      return {
        status: "warn",
        message: `Could not compare detected version with '${formulaName}' stable (${stableVersion}).`,
      };
    }

    if (cmp === 0) {
      return {
        status: "ok",
        message: `Detected version matches current stable '${formulaName}' version (${stableVersion}).`,
      };
    }

    if (cmp < 0) {
      return {
        status: "warn",
        message: `Detected version (${detectedVersion}) is older than current stable '${formulaName}' (${stableVersion}).`,
      };
    }

    return {
      status: "warn",
      message: `Detected version (${detectedVersion}) is newer than current stable '${formulaName}' (${stableVersion}).`,
    };
  } catch (_error) {
    return {
      status: "warn",
      message: `Failed to load formula metadata for '${formulaName}'.`,
    };
  }
}

function overallStatus(checks) {
  if (checks.some((check) => check.status === "fail")) {
    return "fail";
  }
  if (checks.some((check) => check.status === "warn")) {
    return "warn";
  }
  return "ok";
}

function statusTitle(status) {
  if (status === "ok") return "Compatible";
  if (status === "warn") return "Compatible with Warnings";
  return "Not Compatible";
}

function buildSummary(status, detectedVersion) {
  if (status === "ok") {
    return detectedVersion
      ? `All checks passed. Homebrew parser detected ${detectedVersion}.`
      : "All checks passed.";
  }
  if (status === "warn") {
    return "Core compatibility checks passed, but review warnings before using this in a formula.";
  }
  return "One or more required checks failed.";
}

function renderResult({ status, title, summary, checks }) {
  const panel = document.getElementById("resultPanel");
  const titleEl = document.getElementById("resultTitle");
  const summaryEl = document.getElementById("resultSummary");
  const checksEl = document.getElementById("resultChecks");

  panel.classList.remove("hidden");
  titleEl.textContent = title;
  titleEl.className = status;
  summaryEl.textContent = summary;

  checksEl.innerHTML = "";
  for (const check of checks) {
    const item = document.createElement("li");
    item.className = check.status;
    item.textContent = check.message;
    checksEl.appendChild(item);
  }
}

function renderBridgeFailure() {
  renderResult({
    status: "fail",
    title: "Ruby runtime unavailable",
    summary: "The Ruby WebAssembly bridge did not initialize.",
    checks: [
      {
        status: "fail",
        message:
          "Confirm the ruby.wasm CDN script is reachable and loaded before app.js executes.",
      },
    ],
  });
}

waitForBridge();
