#!/usr/bin/env bash
# verify.sh —— 功能级验证：补全系统「真的生效了吗」
#
# 与 probe.sh 的分工:
#   probe.sh   看**声明与资产的静态对账**（清单里有什么、装机上有什么、文件在不在）
#   verify.sh  看**运行时行为**（补全能不能补、高亮有没有挂上、虚影有没有画出来）
#              两者都通过，才算这一项真的交付了。
#
# 用法:
#   verify.sh            跑全部检查
#   verify.sh --help
#
# 只读：不修改任何配置，不安装任何东西，不执行 chmod。
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
ASSETS_DIR="$SKILL_DIR/manifest/assets"
SITE_FUNCS="$HOME/.local/share/zsh/site-functions"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; NC=$'\033[0m'
PASS=0; FAIL=0; SKIP=0
pass()    { printf '  %s %s\n' "${GREEN}✓${NC}" "$*"; PASS=$((PASS + 1)); }
fail()    { printf '  %s %s\n' "${RED}✗${NC}" "$*"; FAIL=$((FAIL + 1)); }
skip()    { printf '  %s %s\n' "${YELLOW}–${NC}" "$*"; SKIP=$((SKIP + 1)); }
section() { printf '\n%s\n' "${GREEN}▸${NC} $*"; }

case "${1:-}" in
  --help|-h|help)
    awk 'NR > 1 && /^set -uo pipefail/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
  "") ;;
  *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
esac

# ---------- 便携超时（macOS 无 timeout(1)）----------
# 用法: run_limited <秒> <cmd...>  ；超时返回 124，被杀的进程不会残留
run_limited() {
  local secs="$1"; shift
  local outerr="$TMPOUT"
  "$@" </dev/null >"$outerr.out" 2>"$outerr.err" &
  local pid=$! i=0 max=$((secs * 10))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge "$max" ]; then
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1; i=$((i + 1))
  done
  wait "$pid"
  return $?
}
TMP="$(mktemp -d "${TMPDIR:-/tmp}/env-verify.XXXXXX")"
TMPOUT="$TMP/o"
trap 'case "$TMP" in */env-verify.*) /bin/rm -rf "$TMP" ;; esac' EXIT

# ---------- 0. 前置：四件套的 brew 源是否落地 ----------
section "0. brew 源文件（snippet 里 source 的路径必须真实存在）"
declare -a SRC=(
  "$BREW_PREFIX/share/zsh-completions"
  "$BREW_PREFIX/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"
  "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
)
missing_src=0
for p in "${SRC[@]}"; do
  if [ -e "$p" ]; then pass "${p#"$BREW_PREFIX"/}"
  else fail "缺失：$p"; missing_src=1; fi
done

section "0b. 无主资产落点"
if [ -d "$ASSETS_DIR" ] && [ -n "$(ls -A "$ASSETS_DIR" 2>/dev/null)" ]; then
  for f in "$ASSETS_DIR"/*; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"; t="$SITE_FUNCS/$b"
    if [ -e "$t" ] && cmp -s "$f" "$t"; then pass "已落位且一致：$b"
    else fail "未落位或内容不同：$b"; fi
  done
else
  skip "manifest/assets 为空，无可验证资产"
fi

# ---------- 1. 非交互冷启动稳健性 ----------
# 这一项是 compinit insecure-directories 事故的直接回归测试：
# 修复前，无 tty 的 zsh -i 会静默放弃 compinit（rc 仍为 0），有 tty 则永久挂起。
section "1. 非交互冷启动（无 tty；超时保护 8s）"
if [ ! -f "$HOME/.zshrc" ]; then
  skip "无 ~/.zshrc"
else
  run_limited 8 /bin/zsh -i -c 'exit 0'
  rc=$?
  if [ "$rc" -eq 124 ]; then
    fail "启动挂起（>8s）—— 极可能是 compinit 的 insecure directories 交互式询问"
  elif [ "$rc" -ne 0 ]; then
    fail "退出码 ${rc}（应为 0）"
    sed 's/^/      /' "$TMPOUT.err" | head -5
  else
    pass "8s 内正常退出，rc=0"
  fi
  # stderr 三级分类：
  #   全空 → pass；
  #   仅含「宿主环境已知噪音」→ skip（附原因）；其余 → fail。
  #
  # 已知噪音 1（fzf）：fzf --zsh 用 options=(...) 全量快照 zsh 选项再 eval 回填，
  #   快照含 zle 选项而 zsh 拒绝回设。上游 issue #2219/#2262 定性为使用侧问题、不修；
  #   根修 = ~/.zshrc 的 [[ -t 0 && -o interactive ]] 条件加载（非交互场景本就不该加载按键绑定）。
  # 已知噪音 2（宿主垫片）：zsh 重建补全缓存时，compdump 最后一步要做
  #   `mv <临时件> ~/.zcompdump`（见 references/zsh-completion.md），而 Agent 宿主的
  #   PATH 前置了 brokered-bin 垫片，其 mv 会按文件策略拒绝该次改名并打印
  #   "Brokered host rename source refused by file policy"。这是宿主环境行为，
  #   与 ~/.zshrc 配置无关；用户自己终端里不出现。
  KNOWN_NOISE_1="can't change option: zle"
  KNOWN_NOISE_2="Brokered host rename source refused by file policy"
  errsz="$(wc -c < "$TMPOUT.err" | tr -d ' ')"
  if [ "$errsz" -eq 0 ]; then
    pass "stderr 为空（启动无杂音）"
  else
    ther="$(grep -vF -e "$KNOWN_NOISE_1" -e "$KNOWN_NOISE_2" "$TMPOUT.err" || true)"
    if [ -z "$ther" ]; then
      skip "仅宿主环境已知噪音（fzf 选项回填 / 垫片拒绝改名），非配置问题："
      grep -F -e "$KNOWN_NOISE_1" -e "$KNOWN_NOISE_2" "$TMPOUT.err" | sed 's/^/      /' | head -4
    else
      fail "stderr 非空（已排除 2 类已知噪音后仍有内容）："
      printf '%s\n' "$ther" | sed 's/^/      /' | head -8
    fi
  fi
  # 初始化是否真的完成：这比「没报错」强，因为它能抓住「静默失效」
  run_limited 8 /bin/zsh -i -c 'exit $(( ${+_comps[brew]} ? 0 : 9 ))'
  rc=$?
  if [ "$rc" -eq 0 ]; then pass "非交互路径下 _comps[brew] 已注册"
  elif [ "$rc" -eq 9 ]; then fail "非交互路径下补全**静默失效**（compinit 未完成初始化）"
  else fail "非交互注册检查异常，rc=${rc}"; fi
fi

# ---------- 2/3. pty 运行时行为 ----------
section "2. pty 运行时注册（补全 / fzf-tab / fzf / 高亮 / 虚影）"
PY=""
for c in python3 /usr/bin/python3; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
  skip "未找到 python3，跳过 pty 探针（虚拟终端测试需要它）"
else
  if ! "$PY" "$SKILL_DIR/scripts/_pty_probe.py" >"$TMPOUT.pty" 2>"$TMPOUT.ptyerr"; then
    fail "pty 探针执行失败"
    sed 's/^/      /' "$TMPOUT.ptyerr" | head -5
  else
    pv() { grep -m1 "^$1=" "$TMPOUT.pty" 2>/dev/null | cut -d= -f2-; }
    if [ "$(pv startup_ready)" = "1" ]; then
      pass "交互式 shell 已在 pty 中就绪（握手耗时 $(pv startup_wait)s）"
    else
      fail "pty 中 shell 未就绪（探针无应答，等待 $(pv startup_wait)s），后续结论不可信"
      printf '      原始尾部: %s\n' "$(pv startup_raw_tail)" | head -3
      printf '      %s\n' "提示: 若在 Agent 会话里偶发，多为沙箱/负载导致启动过慢；"
      printf '      %s\n' "      请在你自己的终端重跑一次 verify.sh 复核（那里的结论才算数）。"
    fi

    chk1() { # key 描述
      if [ "$(pv "$1")" = "1" ]; then pass "$2"
      else fail "$2（探针返回 '$(pv "$1")'）"; fi
    }
    chk1 p_comps_brew      "_comps[brew] 已注册（brew 补全可用）"
    chk1 p_widget_fzftab   "widgets[fzf-tab-complete] 存在（Tab 弹 fzf 选择器）"
    chk1 p_widget_fzf_hist "widgets[fzf-history-widget] 存在（Ctrl+R 历史搜索，fzf 条件加载的回归项）"
    chk1 p_widget_autosug  "widgets[autosuggest-accept] 存在（虚影已加载）"
    chk1 p_widget_predraw  "widgets[zle-line-pre-redraw] 存在（语法高亮已挂钩）"
    if printf '%s' "$(pv p_fn_zsh_highlight)" | grep -q 'function'; then
      pass "_zsh_highlight 已定义为函数"
    else
      fail "_zsh_highlight 未定义（得到 '$(pv p_fn_zsh_highlight)'）"
    fi
    n="$(pv p_n_autosug_widgets)"
    if [ "$n" = "9" ]; then pass "9 个 autosuggest 交互 widget 齐备"
    elif [ -n "$n" ] && [ "$n" -ge 7 ] 2>/dev/null; then skip "autosuggest widget 数=${n}（期望 9，版本差异可接受）"
    else fail "autosuggest widget 数=${n}（期望 9）"; fi
  fi
fi

section "3. 虚影（ghost text）回显证据"
if [ -z "$PY" ]; then
  skip "同 §2，未执行"
else
  g="$(grep -m1 '^p_ghost_text=' "$TMPOUT.pty" 2>/dev/null | cut -d= -f2-)"
  d="$(grep -m1 '^p_ghost_dimmed=' "$TMPOUT.pty" 2>/dev/null | cut -d= -f2-)"
  if [ "$g" = "1" ]; then
    pass "输入 'git stat' 后终端画出了补全余下文本"
    if [ "$d" = "1" ]; then pass "该文本带暗淡着色（38;5;240，即真·虚影而非普通输出）"
    else skip "未捕获到暗淡着色序列（可能 TERM/主题差异，虚影本身已确认）"; fi
  else
    fail "未见虚影文本（期望余下片段）"
    printf '      原始尾部: %s\n' "$(grep -m1 '^p_ghost_raw_tail=' "$TMPOUT.pty" 2>/dev/null | cut -d= -f2-)" | head -3
  fi
fi

# ---------- 4. 权限事实 ----------
section "4. compinit 不安全目录（只报告，本脚本不代跑 chmod）"
ins="$(/bin/zsh -c "fpath=('$BREW_PREFIX/share/zsh-completions' \$fpath); autoload -Uz compaudit; compaudit" 2>/dev/null </dev/null)"
if [ -z "$ins" ]; then
  pass "fpath 无组/其他可写目录"
else
  skip "存在组/其他可写目录（用户待办，不阻断门禁）:"
  printf '%s\n' "$ins" | sed 's/^/      /'
  printf '      %s\n' "修复（须你本人执行）: chmod go-w ${BREW_PREFIX}/share"
  printf '      %s\n' "说明: compinit 已带 -i，因此不会阻塞也不会静默失效；"
  printf '      %s\n' "      但组可写目录仍属真实风险（同组账号可替换补全函数）。"
fi

# ---------- 汇总 ----------
printf '\n'
if [ "$missing_src" -ne 0 ]; then
  printf '%s\n' "${YELLOW}提示${NC}: 有 brew 源缺失 → 本机尚未装齐（或未装）。装包属于对账协商流程："
  printf '%s\n' "      先跑 scripts/probe.sh 出报告，再由 Agent 逐项向你确认。"
  printf '\n'
fi
printf '通过 %s%d%s  失败 %s%d%s  跳过 %s%d%s\n' \
  "$GREEN" "$PASS" "$NC" "$RED" "$FAIL" "$NC" "$YELLOW" "$SKIP" "$NC"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
