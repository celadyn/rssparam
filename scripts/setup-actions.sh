#!/usr/bin/env bash
# Idempotent local setup for GitHub Actions feedback + Cloudflare Worker dev preview.
# Usage: ./scripts/setup-actions.sh [check|gh|extension|auth|fetch|all]

set -euo pipefail

REPO="celadyn/rssparam"
GH_INSTALL_DIR="${HOME}/.local/bin"

###############################################################################
# Helpers
###############################################################################

add_to_path() {
  case ":${PATH}:" in
    *":${GH_INSTALL_DIR}:"*) ;;
    *) export PATH="${GH_INSTALL_DIR}:${PATH}" ;;
  esac
}

detect_arch() {
  local arch
  arch=$(uname -m)
  case "${arch}" in
    x86_64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;;
  esac
}

find_gh() {
  if command -v gh >/dev/null 2>&1; then
    command -v gh
    return 0
  fi
  if [[ -x "${GH_INSTALL_DIR}/gh" ]]; then
    add_to_path
    echo "${GH_INSTALL_DIR}/gh"
    return 0
  fi
  return 1
}

find_vscode_cli() {
  local name c path_names=()

  for name in code code-insiders cursor windsurf trae; do
    if command -v "${name}" >/dev/null 2>&1; then
      command -v "${name}"
      return 0
    fi
    path_names+=(
      "/Applications/${name}.app/Contents/Resources/app/bin/${name}"
      "${HOME}/Applications/${name}.app/Contents/Resources/app/bin/${name}"
    )
  done

  # common names with spaces / mixed casing
  path_names+=(
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    "${HOME}/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code-insiders"
    "${HOME}/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code-insiders"
  )

  for c in "${path_names[@]}"; do
    if [[ -x "${c}" ]]; then
      echo "${c}"
      return 0
    fi
  done

  return 1
}

###############################################################################
# Stages
###############################################################################

stage_check() {
  echo "[check] Environment check"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "  Warning: script is tuned for macOS but will attempt to continue."
  fi

  if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
    echo "  Error: curl and unzip are required." >&2
    return 1
  fi

  if xcodebuild -license check >/dev/null 2>&1; then
    echo "  Xcode license accepted."
  else
    echo "  WARNING: Xcode license not accepted. Run: sudo xcodebuild -license accept"
    echo "           (git commands will fail until you do)."
  fi

  echo "  OK"
}

stage_gh() {
  echo "[gh] GitHub CLI"

  local gh_bin
  if gh_bin=$(find_gh 2>/dev/null); then
    echo "  Already available: ${gh_bin}"
    "${gh_bin}" --version | head -n1
    return 0
  fi

  echo "  gh not found. Installing into ${GH_INSTALL_DIR}..."
  mkdir -p "${GH_INSTALL_DIR}"

  local arch tag version asset url tmp tmpbin
  arch=$(detect_arch)
  tmp=$(mktemp -d)
  tmpbin=$(mktemp -d)

  tag=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -o '"tag_name": "[^"]*"' | head -1 | sed 's/.*: "//;s/"$//')
  if [[ -z "${tag}" ]]; then
    echo "  Error: could not determine latest gh release." >&2
    return 1
  fi

  version=${tag#v}
  asset="gh_${version}_macOS_${arch}.zip"
  url="https://github.com/cli/cli/releases/download/${tag}/${asset}"

  echo "  Downloading ${url}..."
  curl -fsSL -o "${tmp}/${asset}" "${url}"

  echo "  Extracting..."
  unzip -q "${tmp}/${asset}" -d "${tmpbin}"

  cp "${tmpbin}/gh_${version}_macOS_${arch}/bin/gh" "${GH_INSTALL_DIR}/gh"
  chmod +x "${GH_INSTALL_DIR}/gh"

  rm -rf "${tmp}" "${tmpbin}"

  add_to_path

  # Persist to shell PATH (idempotent)
  local shell_rc="${HOME}/.zshrc"
  if [[ -n "${SHELL:-}" && "${SHELL}" == *bash ]]; then
    shell_rc="${HOME}/.bashrc"
    [[ -f "${shell_rc}" ]] || shell_rc="${HOME}/.bash_profile"
  fi
  if [[ -f "${shell_rc}" ]] && ! grep -qF "export PATH=\"${GH_INSTALL_DIR}:\$PATH\"" "${shell_rc}"; then
    echo "export PATH=\"${GH_INSTALL_DIR}:\$PATH\"" >> "${shell_rc}"
    echo "  Added ${GH_INSTALL_DIR} to PATH in ${shell_rc}"
  fi

  echo "  Installed: $(${GH_INSTALL_DIR}/gh --version | head -n1)"
}

stage_extension() {
  echo "[extension] GitHub Actions VS Code extension"

  local cli
  if ! cli=$(find_vscode_cli); then
    echo "  No VS Code-family CLI found in PATH or common app locations."
    echo "  Install the extension manually: open the Extensions panel and search 'GitHub Actions' by GitHub."
    return 0
  fi

  echo "  Installing extension via: ${cli}"
  "${cli}" --install-extension GitHub.vscode-github-actions || {
    echo "  Extension install command failed (it may already be installed)."
  }
}

stage_auth() {
  echo "[auth] Authenticate gh"

  local gh_bin
  if ! gh_bin=$(find_gh); then
    echo "  Error: gh not installed. Run: ./scripts/setup-actions.sh gh" >&2
    return 1
  fi

  if "${gh_bin}" auth status >/dev/null 2>&1; then
    echo "  Already authenticated."
    return 0
  fi

  echo "  gh is not authenticated."
  if [[ -t 0 ]]; then
    echo "  Starting interactive login (opens browser/device flow)..."
    "${gh_bin}" auth login || {
      echo "  Login failed. If you have a token, run:" >&2
      echo "    echo YOUR_TOKEN | ${gh_bin} auth login --with-token" >&2
      return 1
    }
  else
    echo "  Non-interactive shell. Set a token and run:" >&2
    echo "    echo YOUR_TOKEN | ${gh_bin} auth login --with-token" >&2
    return 1
  fi
}

stage_fetch() {
  echo "[fetch] GitHub Actions data for ${REPO}"

  local gh_bin
  if ! gh_bin=$(find_gh); then
    echo "  Error: gh not installed." >&2
    return 1
  fi

  if ! "${gh_bin}" auth status >/dev/null 2>&1; then
    echo "  Skipped: gh is not authenticated. Run: ./scripts/setup-actions.sh auth" >&2
    return 1
  fi

  echo
  echo "== Workflows =="
  "${gh_bin}" workflow list --repo "${REPO}" || true

  echo
  echo "== Recent runs (event = trigger, status/ conclusion = result) =="
  if command -v jq >/dev/null 2>&1; then
    "${gh_bin}" run list --repo "${REPO}" --limit 15 \
      --json name,event,headBranch,status,conclusion,url,createdAt,runNumber | jq -C .
  else
    "${gh_bin}" run list --repo "${REPO}" --limit 15
  fi

  echo
  echo "== Latest run details =="
  local run_id
  run_id=$("${gh_bin}" run list --repo "${REPO}" --limit 1 --json databaseId 2>/dev/null | jq -r '.[0].databaseId' 2>/dev/null || true)
  if [[ -n "${run_id}" && "${run_id}" != "null" ]]; then
    "${gh_bin}" run view "${run_id}" --repo "${REPO}" || true
  fi

  echo
  echo "== Useful follow-ups =="
  echo "  View logs:   ${gh_bin} run view <run-id> --repo ${REPO} --log"
  echo "  View .yml:   ${gh_bin} workflow view deploy.yml --repo ${REPO}"
}

###############################################################################
# Entry point
###############################################################################

run_all() {
  stage_check
  stage_gh
  stage_extension
  stage_auth
  stage_fetch
}

usage() {
  echo "Usage: $0 [check|gh|extension|auth|fetch|all]"
  echo "  check     - environment check"
  echo "  gh        - install/update GitHub CLI"
  echo "  extension - install GitHub Actions VS Code extension"
  echo "  auth      - log in to GitHub CLI"
  echo "  fetch     - list workflows, runs, triggers, and results"
  echo "  all       - run all stages (default)"
}

main() {
  local stage="${1:-all}"
  case "${stage}" in
    check)     stage_check ;;
    gh)        stage_gh ;;
    extension) stage_extension ;;
    auth)      stage_auth ;;
    fetch)     stage_fetch ;;
    all)       run_all ;;
    -h|--help|help) usage ;;
    *)
      echo "Unknown stage: ${stage}" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
