#!/usr/bin/env bash
# T3 Code fork 版本管理：將 ez/patches 疊上官方 stable tag。
# 指令：status | sync [ref] | verify <tag> | promote <tag> | pr <編號>
# 永遠唔會 push；promote 之前 ez/patches 都唔會郁。
set -euo pipefail

PATCH_BRANCH="ez/patches"
PATCH_LIMIT=15
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
PARENT="$(dirname "$ROOT")"
g() { git -C "$ROOT" "$@"; }

die() { echo "❌ $*" >&2; exit 1; }

fetch_upstream() {
  g fetch -q upstream main --tags
  # main 只做官方鏡像；唔係 fast-forward 就即刻講
  if [ "$(g branch --show-current)" != "main" ]; then
    g fetch -q upstream main:main || echo "⚠️ 本地 main 同上游分叉咗，main 應該係純鏡像，請檢查" >&2
  fi
}

latest_stable() {
  g tag -l 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1
}

current_base() { g merge-base "$PATCH_BRANCH" upstream/main; }

sync_branch() { echo "ez/sync-$1"; }
sync_tree() { echo "$PARENT/t3code-sync-$1"; }

# 改到官方檔案嘅 patch 先係衝突來源；fork/ 同 ez/ 係自己嘅地方
upstream_files_touched() {
  g diff --name-only "$(current_base)" "$PATCH_BRANCH" |
    grep -vE '^(fork/|apps/web/src/ez/)' || true
}

cmd_status() {
  fetch_upstream
  local base latest count files
  base="$(current_base)"
  latest="$(latest_stable)"
  count="$(g rev-list --count "$base..$PATCH_BRANCH")"
  files="$(upstream_files_touched)"

  echo "底座：$(g describe --tags --always "$base")"
  echo "最新 stable：${latest}（$(g merge-base --is-ancestor "$latest" "$base" && echo '已跟上' || echo "落後 $(g rev-list --count "$base..$latest") commits")）"
  echo "main 距離上游 stable 之後：$(g rev-list --count "$latest..upstream/main") commits 未 release"
  echo
  echo "Patches（$count / 上限 ${PATCH_LIMIT}）："
  g log --reverse --format='  %h %s' "$base..$PATCH_BRANCH"
  [ "$count" -gt "$PATCH_LIMIT" ] && echo "⚠️ 超過上限，揀啲刪走或者送返上游"
  echo
  echo "改到嘅官方檔案（衝突面）："
  if [ -n "$files" ]; then echo "$files" | sed 's/^/  /'; else echo "  冇"; fi
  if echo "$files" | grep -qE 'persistence/Migrations'; then
    echo "⚠️ Patch 改到 DB migration，會同上游撞號"
  fi
  local trees
  trees="$(g worktree list --porcelain | grep -E '^branch refs/heads/ez/sync-' || true)"
  [ -z "$trees" ] || { echo; echo "未完成嘅 sync："; echo "$trees" | sed 's#branch refs/heads/#  #'; }
}

cmd_sync() {
  fetch_upstream
  local target base branch tree
  target="${1:-$(latest_stable)}"
  g rev-parse -q --verify "$target^{commit}" >/dev/null || die "搵唔到 $target"
  base="$(current_base)"
  if g merge-base --is-ancestor "$target" "$base"; then
    echo "✅ 已經跟上 ${target}，唔使 sync"
    return 0
  fi
  branch="$(sync_branch "$target")"
  tree="$(sync_tree "$target")"
  g rev-parse -q --verify "refs/heads/$branch" >/dev/null && die "$branch 已存在；喺 $tree 繼續，或者先清走"

  echo "上游 $(g describe --tags --always "$base") → ${target}：$(g rev-list --count "$base..$target") commits"
  g worktree add -q -b "$branch" "$tree" "$PATCH_BRANCH"
  local rebase_status=0
  git -C "$tree" rebase --onto "$target" "$base" --empty=drop >/dev/null 2>&1 || rebase_status=$?
  # rerere 全部解晒嘅衝突唔使人手：繼續行，直到真係有未解嘅
  while [ "$rebase_status" -ne 0 ]; do
    if [ -n "$(git -C "$tree" diff --name-only --diff-filter=U)" ]; then
      echo "⚠️ 有衝突，停喺 ${tree}："
      git -C "$tree" diff --name-only --diff-filter=U | sed 's/^/  /'
      echo "撞到嘅 patch：$(git -C "$tree" log -1 --format='%h %s' REBASE_HEAD)"
      echo "解完：git -C \"$tree\" add <檔案> && git -C \"$tree\" rebase --continue"
      exit 2
    fi
    [ -d "$(git -C "$tree" rev-parse --git-dir)/rebase-merge" ] || die "Rebase 失敗，唔係衝突，請睇 $tree"
    rebase_status=0
    GIT_EDITOR=true git -C "$tree" rebase --continue >/dev/null 2>&1 || rebase_status=$?
  done
  echo "✅ Rebase 順利，$(git -C "$tree" rev-list --count "$target..HEAD") 個 patch 喺 $tree"
  echo "Patch 變化（range-diff）："
  g range-diff "$base..$PATCH_BRANCH" "$target..$branch" || true
  echo "下一步：fork/sync.sh verify ${target}，然後 fork/sync.sh promote $target"
}

cmd_verify() {
  local target="${1:?要 tag，例如 v0.1.8}" tree
  tree="$(sync_tree "$target")"
  [ -d "$tree" ] || die "冇 ${tree}，先行 sync"
  command -v vp >/dev/null || die "未裝 vp，驗證冇跑（裝法見 README.md「Install vp」）"
  (cd "$tree" && vp i && vp run check:changed "$target")
}

cmd_promote() {
  local target="${1:?要 tag，例如 v0.1.8}" branch tree backup
  branch="$(sync_branch "$target")"
  tree="$(sync_tree "$target")"
  g rev-parse -q --verify "refs/heads/$branch" >/dev/null || die "冇 $branch"
  [ -z "$(git -C "$tree" status --porcelain)" ] || die "$tree 未清（有未 commit 或者 rebase 未完）"
  [ ! -d "$(git -C "$tree" rev-parse --git-dir)/rebase-merge" ] || die "$tree 嘅 rebase 未完"
  g merge-base --is-ancestor "$target" "$branch" || die "$branch 唔包含 $target"

  backup="ez/backup-$(date +%Y%m%d-%H%M%S)"
  g tag "$backup" "$PATCH_BRANCH"
  g worktree remove "$tree"
  if [ "$(g branch --show-current)" = "$PATCH_BRANCH" ]; then
    # --keep：有未 commit 嘅改動會打架就拒絕，唔會蓋走
    g reset -q --keep "$branch" || die "主 checkout 有改動擋住；舊版喺 tag $backup"
  else
    g branch -f "$PATCH_BRANCH" "$branch"
  fi
  g branch -q -D "$branch"
  echo "✅ $PATCH_BRANCH 已經喺 $target 之上；舊版留低 tag $backup"
  echo "同步 GitHub（要改寫遠端，自己行）：git push --force-with-lease origin $PATCH_BRANCH"
}

cmd_pr() {
  local n="${1:?要 PR 編號}"
  [[ "$n" =~ ^[0-9]+$ ]] || die "PR 編號要係數字"
  g fetch -q upstream "+pull/$n/head:refs/heads/ez/pr-$n"
  echo "PR #$n 嘅 commits（merge-base 之後）："
  g log --reverse --format='  %h %s' "$(g merge-base "ez/pr-$n" upstream/main)..ez/pr-$n"
  echo "試用：git cherry-pick <commit>，然後記入 fork/PATCHES.md"
}

case "${1:-status}" in
  status) cmd_status ;;
  sync) cmd_sync "${2:-}" ;;
  verify) cmd_verify "${2:-}" ;;
  promote) cmd_promote "${2:-}" ;;
  pr) cmd_pr "${2:-}" ;;
  *) die "用法：fork/sync.sh status | sync [ref] | verify <tag> | promote <tag> | pr <編號>" ;;
esac
