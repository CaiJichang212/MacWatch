#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.codex/openspec-runtime"
MANAGER_DIR="$ROOT_DIR/.codex/openspec"
LOCAL_CODEX_HOME="$MANAGER_DIR/codex-home"
MANAGED_PROMPTS_DIR="$LOCAL_CODEX_HOME/prompts"
MANAGED_SKILLS_DIR="$MANAGER_DIR/skills"
ACTIVE_SKILLS_DIR="$ROOT_DIR/.codex/skills"
BACKUP_PROMPTS_DIR="$MANAGER_DIR/backups/prompts"
GLOBAL_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
GLOBAL_PROMPTS_DIR="$GLOBAL_CODEX_HOME/prompts"
OPEN_SPEC_BIN="$RUNTIME_DIR/node_modules/.bin/openspec"
PACKAGE_NAME="@fission-ai/openspec@latest"

usage() {
  cat <<'EOF'
用法:
  ./scripts/openspec.sh install
  ./scripts/openspec.sh enable [--profile core]
  ./scripts/openspec.sh disable
  ./scripts/openspec.sh status
  ./scripts/openspec.sh update [--profile core]

说明:
  install   仅安装或更新仓库内的 OpenSpec CLI runtime
  enable    生成并激活当前仓库的 OpenSpec skill / prompt
  disable   一键关闭当前仓库注入到 Codex 的 OpenSpec skill / prompt
  status    查看当前仓库 OpenSpec 安装与启用状态
  update    更新本地 runtime，并刷新当前仓库的 OpenSpec 产物
EOF
}

log() {
  printf '[openspec] %s\n' "$*"
}

warn() {
  printf '[openspec] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[openspec] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || die "缺少依赖命令: $command_name"
}

ensure_directories() {
  mkdir -p "$ACTIVE_SKILLS_DIR" "$MANAGED_SKILLS_DIR" "$BACKUP_PROMPTS_DIR"
}

managed_skill_path() {
  local name="$1"
  printf '%s/%s' "$MANAGED_SKILLS_DIR" "$name"
}

backup_prompt_path() {
  local name="$1"
  printf '%s/%s' "$BACKUP_PROMPTS_DIR" "$name"
}

is_symlink_to_dir() {
  local link_path="$1"
  local target_dir="$2"

  [ -L "$link_path" ] || return 1

  local link_target
  link_target="$(readlink "$link_path")"
  case "$link_target" in
    "$target_dir"/*) return 0 ;;
    *) return 1 ;;
  esac
}

remove_managed_skill_symlinks() {
  ensure_directories

  local skill_path
  shopt -s nullglob
  for skill_path in "$ACTIVE_SKILLS_DIR"/openspec-*; do
    if is_symlink_to_dir "$skill_path" "$MANAGED_SKILLS_DIR"; then
      rm -f "$skill_path"
    fi
  done
  shopt -u nullglob
}

remove_managed_prompt_symlinks() {
  local prompt_path
  shopt -s nullglob
  for prompt_path in "$GLOBAL_PROMPTS_DIR"/opsx-*.md; do
    if is_symlink_to_dir "$prompt_path" "$MANAGED_PROMPTS_DIR"; then
      rm -f "$prompt_path"
    fi
  done
  shopt -u nullglob
}

install_runtime() {
  require_command npm
  mkdir -p "$RUNTIME_DIR"
  log "安装或更新仓库内 OpenSpec runtime"
  npm install --prefix "$RUNTIME_DIR" "$PACKAGE_NAME"
}

ensure_runtime() {
  if [ ! -x "$OPEN_SPEC_BIN" ]; then
    install_runtime
  fi
}

openspec_version() {
  [ -f "$RUNTIME_DIR/node_modules/@fission-ai/openspec/package.json" ] || return 1
  node -p "require('$RUNTIME_DIR/node_modules/@fission-ai/openspec/package.json').version"
}

prepare_generated_paths() {
  rm -rf "$LOCAL_CODEX_HOME"
  mkdir -p "$LOCAL_CODEX_HOME"
  remove_managed_skill_symlinks
}

generate_artifacts() {
  local profile="${1:-core}"

  ensure_runtime
  ensure_directories
  prepare_generated_paths

  log "生成 OpenSpec 指令文件"
  CODEX_HOME="$LOCAL_CODEX_HOME" "$OPEN_SPEC_BIN" init --tools codex --profile "$profile" --force
}

sync_generated_skills_into_manager() {
  ensure_directories

  local skill_path
  shopt -s nullglob
  for skill_path in "$ACTIVE_SKILLS_DIR"/openspec-*; do
    local name
    name="$(basename "$skill_path")"
    local managed_path
    managed_path="$(managed_skill_path "$name")"

    rm -rf "$managed_path"
    mv "$skill_path" "$managed_path"
  done
  shopt -u nullglob
}

backup_global_prompt_if_needed() {
  local prompt_name="$1"
  local global_path="$GLOBAL_PROMPTS_DIR/$prompt_name"
  local backup_path
  backup_path="$(backup_prompt_path "$prompt_name")"

  if [ -e "$global_path" ] && [ ! -L "$global_path" ] && [ ! -e "$backup_path" ]; then
    mkdir -p "$BACKUP_PROMPTS_DIR"
    mv "$global_path" "$backup_path"
  fi
}

restore_global_prompt_backup_if_present() {
  local prompt_name="$1"
  local global_path="$GLOBAL_PROMPTS_DIR/$prompt_name"
  local backup_path
  backup_path="$(backup_prompt_path "$prompt_name")"

  if [ ! -e "$global_path" ] && [ -e "$backup_path" ]; then
    mkdir -p "$GLOBAL_PROMPTS_DIR"
    mv "$backup_path" "$global_path"
  fi
}

activate_skills() {
  ensure_directories

  local managed_path
  shopt -s nullglob
  for managed_path in "$MANAGED_SKILLS_DIR"/openspec-*; do
    local name
    name="$(basename "$managed_path")"
    local active_path="$ACTIVE_SKILLS_DIR/$name"

    if [ -e "$active_path" ] && ! is_symlink_to_dir "$active_path" "$MANAGED_SKILLS_DIR"; then
      die "检测到未托管的技能目录冲突: $active_path"
    fi

    rm -f "$active_path"
    ln -s "$managed_path" "$active_path"
  done
  shopt -u nullglob
}

activate_prompts() {
  mkdir -p "$GLOBAL_PROMPTS_DIR"

  local prompt_path
  shopt -s nullglob
  for prompt_path in "$MANAGED_PROMPTS_DIR"/opsx-*.md; do
    local name
    name="$(basename "$prompt_path")"
    local global_path="$GLOBAL_PROMPTS_DIR/$name"

    if [ -e "$global_path" ] && ! is_symlink_to_dir "$global_path" "$MANAGED_PROMPTS_DIR"; then
      backup_global_prompt_if_needed "$name"
    fi

    if [ -e "$global_path" ] && ! is_symlink_to_dir "$global_path" "$MANAGED_PROMPTS_DIR"; then
      die "检测到未托管的全局 prompt 冲突: $global_path"
    fi

    rm -f "$global_path"
    ln -s "$prompt_path" "$global_path"
  done
  shopt -u nullglob
}

enable_openspec() {
  local profile="${1:-core}"

  generate_artifacts "$profile"
  sync_generated_skills_into_manager
  activate_skills
  activate_prompts

  log "OpenSpec 已启用"
  status_openspec
}

disable_openspec() {
  remove_managed_skill_symlinks
  remove_managed_prompt_symlinks

  local backup_path
  shopt -s nullglob
  for backup_path in "$BACKUP_PROMPTS_DIR"/opsx-*.md; do
    restore_global_prompt_backup_if_present "$(basename "$backup_path")"
  done
  shopt -u nullglob

  log "OpenSpec 已关闭"
  status_openspec
}

status_openspec() {
  local runtime_state="missing"
  local version="n/a"
  local config_state="missing"
  local managed_skill_count=0
  local active_skill_count=0
  local managed_prompt_count=0
  local active_prompt_count=0

  if [ -x "$OPEN_SPEC_BIN" ]; then
    runtime_state="installed"
    version="$(openspec_version || printf 'unknown')"
  fi

  if [ -f "$ROOT_DIR/openspec/config.yaml" ]; then
    config_state="present"
  fi

  if [ -d "$MANAGED_SKILLS_DIR" ]; then
    managed_skill_count="$(find "$MANAGED_SKILLS_DIR" -maxdepth 1 -mindepth 1 -name 'openspec-*' -type d | wc -l | tr -d ' ')"
  fi

  if [ -d "$ACTIVE_SKILLS_DIR" ]; then
    local skill_path
    shopt -s nullglob
    for skill_path in "$ACTIVE_SKILLS_DIR"/openspec-*; do
      if is_symlink_to_dir "$skill_path" "$MANAGED_SKILLS_DIR"; then
        active_skill_count=$((active_skill_count + 1))
      fi
    done
    shopt -u nullglob
  fi

  if [ -d "$MANAGED_PROMPTS_DIR" ]; then
    managed_prompt_count="$(find "$MANAGED_PROMPTS_DIR" -maxdepth 1 -mindepth 1 -name 'opsx-*.md' -type f | wc -l | tr -d ' ')"
  fi

  if [ -d "$GLOBAL_PROMPTS_DIR" ]; then
    local prompt_path
    shopt -s nullglob
    for prompt_path in "$GLOBAL_PROMPTS_DIR"/opsx-*.md; do
      if is_symlink_to_dir "$prompt_path" "$MANAGED_PROMPTS_DIR"; then
        active_prompt_count=$((active_prompt_count + 1))
      fi
    done
    shopt -u nullglob
  fi

  local enabled_state="disabled"
  if [ "$managed_skill_count" -gt 0 ] && [ "$managed_skill_count" -eq "$active_skill_count" ] && [ "$managed_prompt_count" -gt 0 ] && [ "$managed_prompt_count" -eq "$active_prompt_count" ]; then
    enabled_state="enabled"
  elif [ "$active_skill_count" -gt 0 ] || [ "$active_prompt_count" -gt 0 ]; then
    enabled_state="partial"
  fi

  cat <<EOF
OpenSpec 状态
  runtime: $runtime_state
  version: $version
  openspec config: $config_state
  managed skills: $managed_skill_count
  active skills: $active_skill_count
  managed prompts: $managed_prompt_count
  active prompts: $active_prompt_count
  mode: $enabled_state
  global prompts dir: $GLOBAL_PROMPTS_DIR
EOF
}

parse_profile_flag() {
  local default_profile="core"

  if [ "${1:-}" = "--profile" ]; then
    [ -n "${2:-}" ] || die "--profile 缺少值"
    printf '%s' "$2"
    return 0
  fi

  printf '%s' "$default_profile"
}

main() {
  local command="${1:-status}"
  shift || true

  case "$command" in
    install)
      install_runtime
      ;;
    enable|on)
      enable_openspec "$(parse_profile_flag "${1:-}" "${2:-}")"
      ;;
    disable|off)
      disable_openspec
      ;;
    status)
      status_openspec
      ;;
    update)
      install_runtime
      enable_openspec "$(parse_profile_flag "${1:-}" "${2:-}")"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage
      die "未知命令: $command"
      ;;
  esac
}

main "$@"
