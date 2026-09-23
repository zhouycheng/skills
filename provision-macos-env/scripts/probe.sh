#!/usr/bin/env bash
# probe.sh —— macOS 环境对账的只读扫描入口
#
# 用法:
#   probe.sh            完整三分报告
#   probe.sh --brief    只看汇总（供快速判断）
#   probe.sh --help
#
# 安全约定:
#   - 完全只读：不安装、不卸载、不改 ~/.zshrc、不写仓库内任何文件
#   - 唯一的写操作是把报告快照存到仓库外的状态目录（可用 ENV_STATE_DIR 覆盖）
#   - 输出是给 Agent 与用户共同阅读的事实，不含任何"已自动处理"的动作
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$SKILL_DIR/manifest"
BREWFILE="$MANIFEST/Brewfile"
ASSETS_DIR="$MANIFEST/assets"
SNIPPET="$MANIFEST/zsh/zshrc.snippet"
ZSHRC="${ZSHRC_OVERRIDE:-$HOME/.zshrc}"
STATE_DIR="${ENV_STATE_DIR:-$HOME/.local/state/env}"
SITE_FUNCS="$HOME/.local/share/zsh/site-functions"
MARKER='# ---- zsh 补全系统'

PY="$(command -v python3 || echo /usr/bin/python3)"
BRIEF=false
[ "${1:-}" = "--brief" ] && BRIEF=true

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  awk 'NR > 1 && /^set -uo pipefail/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/env-probe.XXXXXX")"
trap 'case "$TMP" in */env-probe.*) /bin/rm -rf "$TMP" ;; esac' EXIT

hr() { printf '%s\n' "────────────────────────────────────────────────────────────"; }
head2() { printf '\n%s\n' "【$1】$2"; }

# ---------- 声明侧：解析 manifest/Brewfile ----------
# 输出: <type>\t<section>\t<name>
parse_brewfile() {
  awk '
    /^[[:space:]]*#[[:space:]]*====/ {
      s = $0
      sub(/^[[:space:]]*#[[:space:]]*====[[:space:]]*/, "", s)
      sub(/[[:space:]]*====[[:space:]]*$/, "", s)
      sec = s; next
    }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*(brew|cask|tap|mas)[[:space:]]/ {
      t = $1; rest = $0
      sub(/^[^"]*"/, "", rest)
      sub(/".*$/, "", rest)
      if (rest != "") print t "\t" sec "\t" rest
    }
  ' "$BREWFILE" 2>/dev/null
}

# ---------- 实际侧：本机已装的 formula（含版本、日期、是否顶层） ----------
# 输出: <name>\t<version>\t<date>\t<on_request 1/0>
observed_formulae() {
  brew info --json=v2 --installed 2>/dev/null | "$PY" -c '
import json, sys, datetime
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for f in d.get("formulae", []):
    inst = (f.get("installed") or [{}])[0]
    if not inst:
        continue
    t = inst.get("time")
    date = datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d") if t else "-"
    onreq = "1" if inst.get("installed_on_request") else "0"
    print("%s\t%s\t%s\t%s" % (f.get("name", "-"), inst.get("version", "-"), date, onreq))
'
}

# ---------- 主流程 ----------
NOW="$(date '+%Y-%m-%d %H:%M:%S')"
REPORT="$TMP/report.txt"

if command -v brew >/dev/null 2>&1; then
  BREW_OK=true
  BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
  BREW_VER="$(brew --version 2>/dev/null | head -1)"
else
  BREW_OK=false
  BREW_PREFIX="/opt/homebrew"
  BREW_VER="未安装"
fi

if [ -d "$STATE_DIR" ]; then MODE="增量对账"; STATE_MARK="存在"; else MODE="全新供给"; STATE_MARK="不存在"; fi

{
hr
printf '%s\n' "provision-macos-env · 对账报告（只读）"
printf '生成时间: %s\n' "$NOW"
hr
} > "$REPORT"

head2 0 "机器状态" >> "$REPORT"
printf '  brew          %s   (%s)\n' "$BREW_PREFIX" "$BREW_VER" >> "$REPORT"
printf '  状态目录      %s   [%s]\n' "${STATE_DIR/#$HOME/~}" "$STATE_MARK" >> "$REPORT"
printf '  本次模式      %s\n' "$MODE" >> "$REPORT"

if [ "$BREW_OK" != "true" ]; then
  printf '\n%s\n' "  ⚠️ brew 未安装 —— 属于「全新机器」。此场景需要你本人先执行：" >> "$REPORT"
  printf '%s\n' "      xcode-select --install" >> "$REPORT"
  printf '%s\n' '      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >> "$REPORT"
  printf '%s\n' "      （该脚本必须交互输入 sudo 密码，Agent 环境无法执行）" >> "$REPORT"
  printf '%s\n' "  扫描到此停止：无 brew 时其余分区无意义。" >> "$REPORT"
  cat "$REPORT"
  exit 0
fi

if [ ! -f "$BREWFILE" ]; then
  printf '\n  ⚠️ 清单缺失：%s\n' "${BREWFILE/#$HOME/~}" >> "$REPORT"
  cat "$REPORT"; exit 1
fi

# --- 收集两侧数据 ---
parse_brewfile > "$TMP/declared"
awk -F'\t' '$1=="brew"{print $3}' "$TMP/declared" | sort -u > "$TMP/decl_formulae"
awk -F'\t' '$1=="cask"{print $3}' "$TMP/declared" | sort -u > "$TMP/decl_casks"
awk -F'\t' '$1=="tap"{print $3}'  "$TMP/declared" | sort -u > "$TMP/decl_taps"

observed_formulae > "$TMP/obs"
cut -f1 "$TMP/obs" | sort -u > "$TMP/obs_all"
awk -F'\t' '$4=="1"{print $1}' "$TMP/obs" | sort -u > "$TMP/obs_top"
brew list --cask 2>/dev/null | sort -u > "$TMP/obs_casks"

comm -23 "$TMP/decl_formulae" "$TMP/obs_all"   > "$TMP/missing_f"
comm -23 "$TMP/decl_casks"    "$TMP/obs_casks" > "$TMP/missing_c"
comm -12 "$TMP/decl_formulae" "$TMP/obs_all"   > "$TMP/ok_f"
comm -12 "$TMP/decl_casks"    "$TMP/obs_casks" > "$TMP/ok_c"
comm -13 "$TMP/decl_formulae" "$TMP/obs_top"   > "$TMP/extra_f"
comm -13 "$TMP/decl_casks"    "$TMP/obs_casks" > "$TMP/extra_c"

n_missing_f=$(wc -l < "$TMP/missing_f" | tr -d ' ')
n_missing_c=$(wc -l < "$TMP/missing_c" | tr -d ' ')
n_ok_f=$(wc -l < "$TMP/ok_f" | tr -d ' ')
n_ok_c=$(wc -l < "$TMP/ok_c" | tr -d ' ')
n_extra_f=$(wc -l < "$TMP/extra_f" | tr -d ' ')
n_extra_c=$(wc -l < "$TMP/extra_c" | tr -d ' ')
n_dep=$(( $(wc -l < "$TMP/obs_all" | tr -d ' ') - $(wc -l < "$TMP/obs_top" | tr -d ' ') ))
n_missing=$((n_missing_f + n_missing_c))
n_ok=$((n_ok_f + n_ok_c))
n_extra=$((n_extra_f + n_extra_c))

# --- 1. 清单内 · 未安装（按分类分组） ---
head2 1 "清单内 · 未安装  ($n_missing)" >> "$REPORT"
if [ "$n_missing" -eq 0 ]; then
  printf '%s\n' "  无。声明已全部落地。" >> "$REPORT"
else
  awk -F'\t' -v mf="$TMP/missing_f" -v mc="$TMP/missing_c" '
    BEGIN {
      while ((getline l < mf) > 0) miss_f[l] = 1
      while ((getline l < mc) > 0) miss_c[l] = 1
    }
    {
      type = $1; sec = $2; name = $3
      hit = (type == "brew" && (name in miss_f)) || (type == "cask" && (name in miss_c))
      if (!hit) next
      if (sec != last) { printf "  [%s]\n", (sec == "" ? "未分类" : sec); last = sec }
      printf "    · %-30s %s\n", name, type
    }
  ' "$TMP/declared" >> "$REPORT"
  printf '\n  → 已声明但尚未落地的意图。需逐个询问用户是否安装。\n' >> "$REPORT"
fi

# --- 2. 清单外 · 已直接安装 ---
head2 2 "清单外 · 已直接安装  ($n_extra)" >> "$REPORT"
if [ "$n_extra" -eq 0 ]; then
  printf '%s\n' "  无。已装项与声明完全一致。" >> "$REPORT"
else
  if [ "$n_extra_f" -gt 0 ]; then
    printf '  %s\n' "— formula —" >> "$REPORT"
    while read -r name; do
      [ -n "$name" ] || continue
      meta="$(awk -F'\t' -v n="$name" '$1==n {printf "%s  装机 %s", $2, $3}' "$TMP/obs")"
      printf '    · %-30s %s\n' "$name" "$meta" >> "$REPORT"
    done < "$TMP/extra_f"
  fi
  if [ "$n_extra_c" -gt 0 ]; then
    printf '  %s\n' "— cask —" >> "$REPORT"
    while read -r name; do
      [ -n "$name" ] || continue
      d="$(stat -f '%Sm' -t '%Y-%m-%d' "/opt/homebrew/Caskroom/$name" 2>/dev/null || echo '-')"
      printf '    · %-30s 装机 %s\n' "$name" "$d" >> "$REPORT"
    done < "$TMP/extra_c"
  fi
  printf '\n  → 你主动装了但未声明的项。每项需判断：纳入清单 / 卸载 / 保持不变。\n' >> "$REPORT"
fi

# --- 3. 清单内 · 已安装 ---
head2 3 "清单内 · 已安装  ($n_ok)" >> "$REPORT"
if [ "$n_ok" -eq 0 ]; then
  printf '%s\n' "  无。" >> "$REPORT"
else
  printf '  %s 项全部一致，不需动作。\n' "$n_ok" >> "$REPORT"
  if [ "$BRIEF" != "true" ]; then
    cat "$TMP/ok_f" "$TMP/ok_c" | sed 's/^/    · /' >> "$REPORT"
  fi
fi

# --- 4. 作为依赖装入（信息） ---
head2 4 "作为依赖装入  ($n_dep)" >> "$REPORT"
printf '  非用户意图，仅作信息展示，不参与任何建议。\n' >> "$REPORT"

# --- 5. 无主资产 + shell 启动健壮性 ---
head2 5 "环境事实" >> "$REPORT"
printf '  %s\n' "【无主资产】" >> "$REPORT"
n_asset=0; n_asset_ok=0
if [ -d "$ASSETS_DIR" ]; then
  for f in "$ASSETS_DIR"/*; do
    [ -f "$f" ] || continue
    n_asset=$((n_asset + 1))
    b="$(basename "$f")"
    t="$SITE_FUNCS/$b"
    if [ ! -e "$t" ]; then
      printf '    · %-34s %s\n' "$b" "未落位" >> "$REPORT"
    elif cmp -s "$f" "$t"; then
      n_asset_ok=$((n_asset_ok + 1))
      printf '    · %-34s %s\n' "$b" "已落位且内容一致" >> "$REPORT"
    else
      printf '    · %-34s %s\n' "$b" "已落位但内容不同" >> "$REPORT"
    fi
  done
else
  printf '%s\n' "  无 assets/ 目录。" >> "$REPORT"
fi
printf '    落点: %s\n' "${SITE_FUNCS/#$HOME/~}" >> "$REPORT"

# shell 启动健壮性：fpath 中存在组/其他可写目录会让 compinit 阻塞或静默放弃
printf '  %s\n' "【shell 启动健壮性】" >> "$REPORT"
if command -v zsh >/dev/null 2>&1; then
  insecure="$(/bin/zsh -c "fpath=('$BREW_PREFIX/share/zsh-completions' \$fpath); autoload -Uz compaudit; compaudit" 2>/dev/null </dev/null)"
  if [ -n "$insecure" ]; then
    printf '    %s\n' "⚠️ compinit 不安全目录（会阻塞非交互调用或使补全静默失效）:" >> "$REPORT"
    printf '%s\n' "$insecure" | sed 's/^/        /' >> "$REPORT"
    printf '    修复（须你本人执行，本脚本不代跑 chmod）: chmod go-w %s/share\n' "$BREW_PREFIX" >> "$REPORT"
    printf '    说明: 配置已用 compinit -i 兜底，因此不会阻塞；但补全可能被整目录丢弃。\n' >> "$REPORT"
  else
    printf '    %s\n' "无。compinit 权限检查通过。" >> "$REPORT"
  fi
fi
# 缓存卫生：zsh 重建补全缓存时会先写 .zcompdump.<host>.<pid> 再改名；若改名失败，
# 临时文件就留在 $HOME。
# 源码定位（zsh 5.9，/usr/share/zsh/5.9/functions/compdump）：
#   L21  _d_file=${_comp_dumpfile}.$HOST.$$      ← 临时文件名
#   L36  exec {_d_fd}>$_d_file                   ← 创建并写满（残留件都是完整尺寸）
#   L138 mv -f $_d_file ${_d_file%.$HOST.$$}     ← 改名成正主（断点就在这句）
# 触发链：Agent 沙箱挡住 $HOMEBREW_PREFIX/share/ 下的补全目录 → fpath 实扫数
#   1162→967 → compinit L486 判定 dump 失效 → 每个 shell 都重建 → L138 的 mv 命中
#   PATH 前置的 brokered-bin 垫片被文件策略拒绝 → 临时件原地留下。
# 已根治：zshrc.snippet 改为 `compinit -i -C`（-C 令 _i_check 为空，直接 source 现有
#   dump，不比对不重建）。故本分区现应长期为 0；若又出现，说明该修复被绕过。
# 它们是可再生的缓存、不是配置，因此只报告不代删（本脚本只读契约）。
printf '  %s\n' "【缓存卫生】" >> "$REPORT"
n_zd=0
for f in "$HOME"/.zcompdump.*; do
  [ -e "$f" ] || continue
  n_zd=$((n_zd + 1))
done
if [ "$n_zd" -eq 0 ]; then
  printf '    %s\n' "无残留（仅主 .zcompdump）。" >> "$REPORT"
else
  printf '    %s\n' "⚠️ 残留 ${n_zd} 个 PID 后缀补全缓存（可再生，可安全清理）:" >> "$REPORT"
  printf '    %s\n' '    清理: /bin/rm -f "$HOME"/.zcompdump.*   （用绝对路径，避免 Agent 宿主垫片）' >> "$REPORT"
fi

# --- 6. shell 配置块 ---
head2 6 "shell 配置块" >> "$REPORT"
if [ ! -f "$SNIPPET" ]; then
  printf '    %s\n' "无 zsh/zshrc.snippet，跳过。" >> "$REPORT"
elif [ ! -f "$ZSHRC" ]; then
  printf '    %s\n' "~/.zshrc 不存在。" >> "$REPORT"
else
  cur="$(awk -v m="$MARKER" 'index($0, m) == 1 { f = 1 } f { print }' "$ZSHRC")"
  want="$(cat "$SNIPPET")"
  if [ -z "$cur" ]; then
    printf '    %s\n' "~/.zshrc 中无配置块（标记: ${MARKER}）" >> "$REPORT"
  elif [ "$cur" = "$want" ]; then
    printf '    %s\n' "与 zshrc.snippet 完全一致" >> "$REPORT"
  else
    printf '    %s\n' "与 zshrc.snippet 不一致" >> "$REPORT"
  fi
  printf '    %s\n' "标记: $MARKER  |  块约定位置: 文件末尾" >> "$REPORT"
fi

# --- 7. 汇总 ---
head2 7 "汇总" >> "$REPORT"
printf '  清单内未安装 %s  |  清单外已直接安装 %s  |  清单内已安装 %s  |  依赖 %s\n' \
  "$n_missing" "$n_extra" "$n_ok" "$n_dep" >> "$REPORT"
printf '  无主资产 %s/%s 已落位\n' "$n_asset_ok" "$n_asset" >> "$REPORT"
printf '\n  下一步（由 Agent 执行，不得跳步）：\n' >> "$REPORT"
printf '    · 对分区 2 的每项给出判断与依据，交用户裁决\n' >> "$REPORT"
printf '    · 对分区 1 按分类分组询问是否安装\n' >> "$REPORT"
printf '    · 仅在用户逐项确认后才执行；涉及 sudo/chmod 的步骤交用户本人\n' >> "$REPORT"
hr >> "$REPORT"

mkdir -p "$STATE_DIR" 2>/dev/null && cp "$REPORT" "$STATE_DIR/probe-last.txt" 2>/dev/null

cat "$REPORT"
