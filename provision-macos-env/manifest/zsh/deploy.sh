#!/usr/bin/env bash
# deploy.sh —— 把 manifest 的 shell 声明落到本机
#
# 用法:
#   deploy.sh            部署：对齐 ~/.zshrc 的补全块 + 落位 assets/
#   deploy.sh --check    只读：报告差异，不做任何改动
#   deploy.sh --help
#
# 写入范围（仅这两处，写前均备份到状态目录）:
#   ~/.zshrc                                  仅从标记行起到文件末尾的块
#   ~/.local/share/zsh/site-functions/        无主资产的落点
#
# 边界:
#   - 本脚本**不安装任何 brew 包**。装包属于对账协商流程，由 Agent 在用户逐项确认后执行
#   - 不 rm。任何移除走 ~/.Trash
#   - 写 ~/.zshrc 前先 /bin/zsh -n 校验，不过则不落盘
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$SKILL_DIR/manifest"
ASSETS_DIR="$MANIFEST/assets"
SNIPPET="$MANIFEST/zsh/zshrc.snippet"
ZSHRC="${ZSHRC_OVERRIDE:-$HOME/.zshrc}"
SITE_FUNCS="$HOME/.local/share/zsh/site-functions"
STATE_DIR="${ENV_STATE_DIR:-$HOME/.local/state/env}"
MARKER='# ---- zsh 补全系统'
STAMP="$(date +%Y%m%d-%H%M%S)"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; NC=$'\033[0m'
info() { printf '%s\n' "$*"; }
ok()   { printf '%s\n' "${GREEN}✓${NC} $*"; }
warn() { printf '%s\n' "${YELLOW}!${NC} $*"; }
err()  { printf '%s\n' "${RED}✗${NC} $*" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/env-deploy.XXXXXX")"
trap 'case "$TMP" in */env-deploy.*) /bin/rm -rf "$TMP" ;; esac' EXIT

current_block() { [ -f "$ZSHRC" ] && awk -v m="$MARKER" 'index($0, m) == 1 { f = 1 } f { print }' "$ZSHRC"; }

case "${1:-deploy}" in
  --help|-h|help)
    awk 'NR > 1 && /^set -uo pipefail/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
  --check|check) CHECK=true ;;
  deploy) CHECK=false ;;
  *) err "未知子命令: $1"; info "可用: deploy | --check | --help"; exit 2 ;;
esac

[ -f "$SNIPPET" ] || { err "缺失配置片段: $SNIPPET"; exit 1; }

# 守卫：snippet 首行必须自带标记行。否则 current_block() 永远匹配不到，
# 后续会走「追加」分支，把同一段配置重复写进 ~/.zshrc（真实踩过：84 行双块）。
if ! grep -qF "$MARKER" "$SNIPPET"; then
  err "zshrc.snippet 缺少标记行 '$MARKER'，拒绝执行（否则将对齐失败并追加重复块）"
  exit 1
fi

changes=0

# ---------- 1. 对齐 ~/.zshrc ----------
info "${GREEN}▸${NC} shell 配置块"
cur="$(current_block)"
want="$(cat "$SNIPPET")"
if [ -z "$cur" ]; then
  warn "~/.zshrc 中无配置块（将追加）"; changes=$((changes + 1))
elif [ "$cur" = "$want" ]; then
  ok "已与 zshrc.snippet 一致，跳过"
else
  warn "与 zshrc.snippet 不一致（将对齐）"; changes=$((changes + 1))
fi

if [ "$changes" -gt 0 ] && [ "$CHECK" != "true" ]; then
  mkdir -p "$STATE_DIR/backup" || { err "无法创建备份目录"; exit 1; }
  if [ -f "$ZSHRC" ]; then
    cp "$ZSHRC" "$STATE_DIR/backup/zshrc.$STAMP.bak" || { err "备份失败，中止"; exit 1; }
    info "  已备份: ${STATE_DIR/#$HOME/~}/backup/zshrc.$STAMP.bak"
  fi
  # 截断到标记行之前；命令替换顺带剥掉尾部空行
  prev="$(awk -v m="$MARKER" 'index($0, m) == 1 { exit } { print }' "$ZSHRC" 2>/dev/null)"
  newf="$TMP/zshrc.new"
  if [ -n "$prev" ]; then printf '%s\n\n' "$prev" > "$newf"; else : > "$newf"; fi
  cat "$SNIPPET" >> "$newf"

  if ! /bin/zsh -n "$newf" 2>"$TMP/zshrc.err"; then
    err "生成的新配置语法检查未通过，已放弃写入："
    sed 's/^/    /' "$TMP/zshrc.err" >&2
    exit 1
  fi
  mv "$newf" "$ZSHRC" || { err "写入 $ZSHRC 失败"; exit 1; }
  ok "已对齐 ~/.zshrc（标记块: '$MARKER' 起至文件末尾）"
fi

# ---------- 2. 落位无主资产 ----------
info ""
info "${GREEN}▸${NC} 无主资产 → ${SITE_FUNCS/#$HOME/~}"
if [ ! -d "$ASSETS_DIR" ] || [ -z "$(ls -A "$ASSETS_DIR" 2>/dev/null)" ]; then
  info "  无 assets，跳过"
else
  for f in "$ASSETS_DIR"/*; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    t="$SITE_FUNCS/$b"
    if [ -e "$t" ] && cmp -s "$f" "$t"; then
      ok "已落位且一致: $b"; continue
    fi
    changes=$((changes + 1))
    if [ "$CHECK" = "true" ]; then
      if [ -e "$t" ]; then warn "内容不同，待落位: $b"; else warn "未落位: $b"; fi
      continue
    fi
    mkdir -p "$SITE_FUNCS" || { err "无法创建落点目录: $SITE_FUNCS"; exit 1; }
    cp "$f" "$t" || { err "落位失败: $b"; exit 1; }
    chmod 0644 "$t"
    ok "已落位: $b"
  done
fi

# ---------- 汇总 ----------
info ""
if [ "$CHECK" = "true" ]; then
  if [ "$changes" -eq 0 ]; then
    ok "无差异。"
  else
    warn "$changes 处差异待处理。执行 $0 以落位。"
  fi
else
  ok "完成。新开终端（或 exec zsh）后生效。"
  info "复核: $SKILL_DIR/scripts/probe.sh"
fi
