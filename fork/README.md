# Ez 嘅 T3 Code fork

官方版做底座，自己嘅改動維持成一疊細 patch，定期疊上官方新 stable tag。

## 分支

| Ref              | 用途                                    | 規矩                       |
| ---------------- | --------------------------------------- | -------------------------- |
| `main`           | 官方鏡像                                | 永遠唔直接改               |
| `ez/patches`     | 我哋嘅版本：官方 stable tag + patches   | 每個 commit 係一個獨立改動 |
| `ez/sync-<tag>`  | 每次更新嘅試驗場，喺 `../t3code-sync-<tag>` | promote 之後自動清走       |
| `ez/backup-*` 舊版 tag | 每次 promote 之前嘅 `ez/patches`  | 想退返去就靠佢             |

## 跟上游

```sh
fork/sync.sh status           # 底座、落後幾多、patch 清單、衝突面
fork/sync.sh sync             # 喺獨立 worktree rebase 上最新 stable tag
fork/sync.sh verify v0.1.8    # 跑 check:changed（要裝咗 vp）
fork/sync.sh promote v0.1.8   # 留 backup tag，再更新 ez/patches
```

急 fix 可以 `fork/sync.sh sync <commit>` 跟 stable 以外嘅版本，或者只 cherry-pick 嗰個 commit。
試上游未 merge 嘅 PR：`fork/sync.sh pr 31611`，揀 commit cherry-pick，再記入 `PATCHES.md`。

## 加自己嘅組件

1. 新組件放 `apps/web/src/ez/`，呢個目錄上游冇，唔會有衝突。
2. 官方檔案只加最少嘅接駁，行尾標 `// ez:mount <組件名>`，方便 rebase 時認得。
3. 一個組件一個 commit，訊息用 `ez(<組件名>): ...`；之後修改用 `git commit --fixup` 壓返入去，唔好疊新 commit。
4. 喺 `PATCHES.md` 加一行。

Agent 工具優先做 MCP tool 或者 Claude Code mod，咁就完全唔使改 fork。

唔好掂：`apps/server/src/persistence/Migrations`（上游順序編號，會撞）同 `packages/contracts`（一改牽連所有 client）。真係要改先問過。

## 開發同日常使用

- 開發：喺 worktree 跑 `vp run dev`，資料係真 DB 嘅 copy。永遠唔好指住 `~/.t3/userdata`。
- 日常：未有值得用嘅 patch 之前繼續用官方 app。
- 轉用自己嘅版本：先 backup `~/.t3/userdata`，再 `vp run dist:desktop:dmg:arm64`。新 build 可能會升級 DB，舊 app 未必讀到，所以要留低上一版 DMG。
