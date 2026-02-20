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
  const currentEl = document.getElementById("currentVersion");
  const targetEl = document.getElementById("targetVersion");
  const checkBtn = document.getElementById("checkBtn");

  checkBtn.addEventListener("click", async () => {
    const formulaName = formulaEl.value.trim();
    const sourceUrl = urlEl.value.trim();
    const currentOverride = currentEl.value.trim();
    const targetVersionInput = targetEl.value.trim();

    if (!sourceUrl) {
      renderResult({
        status: "fail",
        title: "Source URL required",
        summary: "Enter a source URL to run Homebrew logic.",
        checks: [{ status: "fail", message: "No URL provided." }],
        detectedVersion: null,
        generatedUrl: null,
      });
      return;
    }

    if (!targetVersionInput) {
      renderResult({
        status: "fail",
        title: "Target version required",
        summary: "Enter the target version you want to bump to.",
        checks: [{ status: "fail", message: "No target version provided." }],
        detectedVersion: null,
        generatedUrl: null,
      });
      return;
    }

    checkBtn.disabled = true;
    checkBtn.textContent = "Generating...";

    try {
      const checks = [];
      let generatedUrl = null;

      const detectedVersion = bridge.detectVersion(sourceUrl);
      if (detectedVersion) {
        checks.push({
          status: "ok",
          message: `Detected current version from URL: ${detectedVersion}`,
        });
      } else {
        checks.push({
          status: "warn",
          message: "Could not auto-detect current version from URL.",
        });
      }

      const secure = sourceUrl.startsWith("https://");
      checks.push({
        status: secure ? "ok" : "warn",
        message: secure
          ? "Source URL uses HTTPS."
          : "Source URL does not use HTTPS. Homebrew/core usually requires secure URLs.",
      });

      checks.push({
        status: allowedArchivePattern.test(sourceUrl) ? "ok" : "warn",
        message: allowedArchivePattern.test(sourceUrl)
          ? "Source URL looks like a common archive format."
          : "Source URL extension is uncommon for source archives.",
      });

      const targetVersion = bridge.parseVersion(targetVersionInput);
      if (!targetVersion) {
        checks.push({
          status: "fail",
          message: "Target version is not parseable by Homebrew version logic.",
        });
      } else {
        checks.push({
          status: "ok",
          message: `Target version accepted: ${targetVersion}`,
        });
      }

      let currentVersion = null;
      if (currentOverride) {
        currentVersion = bridge.parseVersion(currentOverride);
        if (!currentVersion) {
          checks.push({
            status: "fail",
            message: "Current version override is not parseable by Homebrew version logic.",
          });
        } else {
          checks.push({
            status: "ok",
            message: `Using manual current version override: ${currentVersion}`,
          });

          if (detectedVersion && bridge.compareVersions(currentVersion, detectedVersion) !== 0) {
            checks.push({
              status: "warn",
              message: `Manual current version (${currentVersion}) differs from URL-detected version (${detectedVersion}).`,
            });
          }
        }
      } else if (detectedVersion) {
        currentVersion = detectedVersion;
        checks.push({
          status: "ok",
          message: "Using URL-detected current version for Homebrew URL rewrite.",
        });
      } else {
        checks.push({
          status: "fail",
          message: "Cannot generate bumped URL without a current version. Enter a current version override.",
        });
      }

      if (currentVersion && targetVersion) {
        const progression = bridge.compareVersions(currentVersion, targetVersion);
        if (progression === null || progression === undefined) {
          checks.push({
            status: "warn",
            message: "Could not compare current and target versions.",
          });
        } else if (progression < 0) {
          checks.push({
            status: "ok",
            message: `Target version (${targetVersion}) is newer than current (${currentVersion}).`,
          });
        } else if (progression === 0) {
          checks.push({
            status: "warn",
            message: "Target version equals current version. URL may remain unchanged.",
          });
        } else {
          checks.push({
            status: "warn",
            message: `Target version (${targetVersion}) is older than current (${currentVersion}).`,
          });
        }

        generatedUrl = bridge.updateUrl(sourceUrl, currentVersion, targetVersion);

        if (!generatedUrl) {
          checks.push({
            status: "fail",
            message: "Homebrew URL rewrite failed.",
          });
        } else if (generatedUrl === sourceUrl) {
          checks.push({
            status: "warn",
            message:
              "Homebrew URL rewrite produced the same URL. This usually needs manual bump handling.",
          });
        } else {
          checks.push({
            status: "ok",
            message: "Generated a new URL using Homebrew's bump-formula-pr update_url logic.",
          });
        }
      }

      if (formulaName && targetVersion) {
        const formulaCheck = await compareAgainstStableFormula(bridge, formulaName, targetVersion);
        checks.push(formulaCheck);
      }

      const status = overallStatus(checks);
      renderResult({
        status,
        title: statusTitle(status),
        summary: buildSummary(status, targetVersion),
        checks,
        detectedVersion,
        generatedUrl,
      });
    } catch (error) {
      renderResult({
        status: "fail",
        title: "Check failed",
        summary: "Unexpected error while running checks.",
        checks: [{ status: "fail", message: String(error) }],
        detectedVersion: null,
        generatedUrl: null,
      });
    } finally {
      checkBtn.disabled = false;
      checkBtn.textContent = "Generate and Check";
    }
  });
}

async function compareAgainstStableFormula(bridge, formulaName, targetVersion) {
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

    const cmp = bridge.compareVersions(targetVersion, stableVersion);
    if (cmp === null || cmp === undefined) {
      return {
        status: "warn",
        message: `Could not compare target version with '${formulaName}' stable (${stableVersion}).`,
      };
    }

    if (cmp === 0) {
      return {
        status: "ok",
        message: `Target version matches current stable '${formulaName}' version (${stableVersion}).`,
      };
    }

    if (cmp < 0) {
      return {
        status: "warn",
        message: `Target version (${targetVersion}) is older than '${formulaName}' stable (${stableVersion}).`,
      };
    }

    return {
      status: "warn",
      message: `Target version (${targetVersion}) is newer than '${formulaName}' stable (${stableVersion}).`,
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
  if (status === "ok") return "Ready";
  if (status === "warn") return "Needs Review";
  return "Not Ready";
}

function buildSummary(status, targetVersion) {
  if (status === "ok") {
    return `Checks passed for manual target version ${targetVersion}.`;
  }
  if (status === "warn") {
    return "URL/version generation succeeded with warnings. Review the checks before using it in a formula bump.";
  }
  return "One or more required checks failed.";
}

function renderResult({ status, title, summary, checks, detectedVersion, generatedUrl }) {
  const panel = document.getElementById("resultPanel");
  const titleEl = document.getElementById("resultTitle");
  const summaryEl = document.getElementById("resultSummary");
  const checksEl = document.getElementById("resultChecks");
  const detectedVersionValue = document.getElementById("detectedVersionValue");
  const generatedUrlValue = document.getElementById("generatedUrlValue");

  panel.classList.remove("hidden");
  titleEl.textContent = title;
  titleEl.className = status;
  summaryEl.textContent = summary;

  detectedVersionValue.textContent = detectedVersion || "Not detected from URL";
  generatedUrlValue.textContent = generatedUrl || "No generated URL (check inputs/warnings)";

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
    detectedVersion: null,
    generatedUrl: null,
  });
}

waitForBridge();
