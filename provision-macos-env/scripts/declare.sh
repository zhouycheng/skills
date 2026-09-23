#!/usr/bin/env bash
# declare.sh —— 把包写入 / 移出 manifest/Brewfile 的对应分类段
#
# 用法:
#   declare.sh <包名> --section "<分类>"        加入清单（分类必须已存在）
#   declare.sh <包名> --section "<分类>" --new-section   分类不存在时顺带新建
#   declare.sh <包名> --cask --section "<分类>"  强制按 cask 声明
#   declare.sh --remove <包名>                  从清单移除声明
#   declare.sh --list-sections                  列出已有分类
#   declare.sh --help
#
# 行为约定:
#   - 幂等：已声明则报告并退出 0，不重复插入
#   - 同分类内按名称字典序插入，保持清单整洁、diff 最小
#   - 写前备份到状态目录；写前用 `brew bundle list` 校验语法，校验不过不落盘
#   - **只改声明，不安装也不卸载**。安装/卸载一律走对账协商流程
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BREWFILE="$SKILL_DIR/manifest/Brewfile"
STATE_DIR="${ENV_STATE_DIR:-$HOME/.local/state/env}"
STAMP="$(date +%Y%m%d-%H%M%S)"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; NC=$'\033[0m'
info() { printf '%s\n' "$*"; }
ok()   { printf '%s\n' "${GREEN}✓${NC} $*"; }
warn() { printf '%s\n' "${YELLOW}!${NC} $*"; }
err()  { printf '%s\n' "${RED}✗${NC} $*" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/env-declare.XXXXXX")"
trap 'case "$TMP" in */env-declare.*) rm -rf "$TMP" ;; esac' EXIT

list_sections() { sed -n 's/^# ==== \(.*\) ====$/\1/p' "$BREWFILE" 2>/dev/null; }

# 清单中已声明的全部条目名（忽略注释）
declared_names() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*(brew|cask|tap|mas)[[:space:]]/ {
      rest = $0
      sub(/^[^"]*"/, "", rest); sub(/".*$/, "", rest)
      if (rest != "") print rest
    }
  ' "$BREWFILE" 2>/dev/null
}

usage() {
  awk 'NR > 1 && /^set -uo pipefail/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
  info ""
  info "现有分类："
  list_sections | sed 's/^/  · /'
}

# 校验候选 Brewfile 的语法；通过返回 0
validate() {
  brew bundle list --file="$1" --all >/dev/null 2>&1
}

backup() {
  mkdir -p "$STATE_DIR/backup" || return 1
  cp "$BREWFILE" "$STATE_DIR/backup/Brewfile.$STAMP.bak" || return 1
  info "已备份: ${STATE_DIR/#$HOME/~}/backup/Brewfile.$STAMP.bak"
}

# ---------- 解析参数 ----------
ACTION=""
PKG=""
SECTION=""
NEW_SECTION=false
FORCE_CASK=false

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --list-sections) list_sections; exit 0 ;;
    --remove) ACTION="remove"; shift; PKG="${1:-}"; shift ;;
    --section) ACTION="${ACTION:-add}"; SECTION="${2:-}"; shift 2 ;;
    --new-section) NEW_SECTION=true; shift ;;
    --cask) FORCE_CASK=true; shift ;;
    -*) err "未知选项: $1"; usage; exit 2 ;;
    *) [ -z "$PKG" ] && { ACTION="${ACTION:-add}"; PKG="$1"; } || { err "多余参数: $1"; exit 2; }; shift ;;
  esac
done

[ -f "$BREWFILE" ] || { err "清单不存在: $BREWFILE"; exit 1; }
[ -n "$PKG" ] || { err "缺少包名"; usage; exit 2; }

# 保证文件以换行结尾，避免插入错位
if [ -s "$BREWFILE" ] && [ -n "$(tail -c 1 "$BREWFILE")" ]; then
  printf '\n' >> "$BREWFILE"
fi

# ---------- 判定类型 ----------
resolve_type() {
  if [ "$FORCE_CASK" = "true" ]; then echo "cask"; return; fi
  if brew list --cask 2>/dev/null | grep -Fxq "$PKG"; then echo "cask"; return; fi
  echo "brew"
}

if [ "$ACTION" = "remove" ]; then
  if ! declared_names | grep -Fxq "$PKG"; then
    warn "清单中未声明 ${PKG}，无需移除。"
    exit 0
  fi
  backup || { err "备份失败，中止"; exit 1; }
  awk -v p="$PKG" '
    found == 0 && $0 ~ ("^[[:space:]]*(brew|cask)[[:space:]]+\"" p "\"") { found = 1; next }
    { print }
  ' "$BREWFILE" > "$TMP/new"
  if ! validate "$TMP/new"; then
    err "移除后语法校验未通过，已放弃写入（原文件未动）"
    exit 1
  fi
  cp "$TMP/new" "$BREWFILE"
  ok "已从清单移除声明: $PKG"
  info ""
  info "${YELLOW}注意：本脚本只改声明，不卸载。${NC}是否真的卸载 $PKG 需在对账协商中单独确认。"
  exit 0
fi

# ---------- 加入 ----------
TYPE="$(resolve_type)"
LINE="$TYPE \"$PKG\""

if declared_names | grep -Fxq "$PKG"; then
  warn "$PKG 已在清单中，无需重复添加。"
  exit 0
fi

if [ -z "$SECTION" ]; then
  err "缺少 --section \"<分类>\"。分类是清单可读性的关键，不接受默认值。"
  info ""
  info "现有分类："
  list_sections | sed 's/^/  · /'
  info ""
  info "要新建分类，加 --new-section"
  exit 2
fi

if grep -qF "# ==== $SECTION ====" "$BREWFILE"; then
  :
elif [ "$NEW_SECTION" = "true" ]; then
  printf '\n# ==== %s ====\n' "$SECTION" >> "$BREWFILE"
  ok "已新建分类: $SECTION"
else
  err "分类不存在: $SECTION"
  info ""
  info "现有分类："
  list_sections | sed 's/^/  · /'
  info ""
  info "确认要新建则重跑并加 --new-section"
  exit 2
fi

# 定位插入行号：分类标题行之后、下一个分类标题之前，按名称字典序
start="$(grep -nF "# ==== $SECTION ====" "$BREWFILE" | head -1 | cut -d: -f1)"
nextsec="$(awk -v s="$start" 'NR > s && /^[[:space:]]*#[[:space:]]*====/ { print NR; exit }' "$BREWFILE")"
[ -n "$nextsec" ] || nextsec=$(( $(wc -l < "$BREWFILE") + 1 ))

ins="$(awk -v s="$start" -v e="$nextsec" -v n="$PKG" '
  NR > s && NR < e && /^[[:space:]]*(brew|cask|tap|mas)[[:space:]]*"/ {
    line = $0; sub(/^[^"]*"/, "", line); sub(/".*$/, "", line)
    if (tolower(line) > tolower(n)) { print NR; exit }
  }
' "$BREWFILE")"
[ -n "$ins" ] || ins="$nextsec"

backup || { err "备份失败，中止"; exit 1; }

head -n $(( ins - 1 )) "$BREWFILE" > "$TMP/new"
printf '%s\n' "$LINE" >> "$TMP/new"
tail -n +"$ins" "$BREWFILE" >> "$TMP/new"

if ! validate "$TMP/new"; then
  err "语法校验未通过，已放弃写入（原文件未动）"
  brew bundle list --file="$TMP/new" --all 2>&1 | head -6 >&2
  exit 1
fi

cp "$TMP/new" "$BREWFILE"
ok "已声明: ${LINE}   （分类: ${SECTION}）"
info ""
repo="$(git -C "$SKILL_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SKILL_DIR")"
rel="${SKILL_DIR#$repo/}"
info "${YELLOW}下一步：${NC}"
info "  1. 复核改动   git -C ${repo} diff -- ${rel}/manifest/Brewfile"
info "  2. 确认无误后自行提交（本脚本不自动 commit）"
info "  3. 若该包尚未安装，它会在下次 probe.sh 的「清单内·未安装」中出现"
