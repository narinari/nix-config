# herdr + Ghostty

AI コーディングエージェント向けマルチプレクサ [herdr](https://herdr.dev) と、その外側の端末 Ghostty の設定メモ。

| ファイル | 内容 |
|---|---|
| `home-manager/narinari/features/essentials/herdr.nix` | herdr 本体と `~/.config/herdr/config.toml`（全ホスト。tmux と同じ場所） |
| `home-manager/narinari/features/desktop/common/ghostty.nix` | Ghostty の設定（デスクトップのホストだけ） |
| `hosts/common/darwin/homebrew.nix` | macOS の Ghostty は cask で入れる（HM 側は `package = null`） |
| `overlays/default.nix` の `herdr-overlay` | herdr 0.9.x を lld でリンクする回避策 |

## 運用

- **herdr は Ghostty の中で使う。** wezterm の leader も `Ctrl+Q` なので、wezterm の中では herdr の prefix が wezterm に取られる
- 既定の端末（niri/Hyprland の Mod+Return）は wezterm のまま
- Ghostty は `keybind = clear` で既定のキーを全部外している（wezterm の `disable_default_key_bindings` と同じ）。
  Ctrl+Tab・Alt+英字などは herdr までそのまま届く。残しているのはコピー/ペースト・新規ウィンドウ・フォントサイズだけ
- macOS は `macos-option-as-alt = true`（herdr の `alt+l/u/e` 用）

## agent integration（claude / codex / hermes）

`herdr integration install <agent>` は各エージェントの設定ファイルを直接書き換える。
しかし、それらは nix が管理していて switch のたびに上書きされるので、使わない。
herdr の config.toml も read-only なので、`onboarding = false` にして初回の画面を出さない
（出すと "failed to save onboarding setting: Read-only file system" になる）。

`pkgs/herdr-integrations` が、空の HOME で `herdr integration install` をビルド時に実行し、生成されたスクリプトと plugin を取り出す。
フックの登録は各 nix ファイルで宣言する:

| agent | スクリプト / plugin | 登録 |
|---|---|---|
| claude | `~/.claude/hooks/herdr-agent-state.sh`（home.file） | `features/llm/default.nix` の `hooks.SessionStart` |
| codex | `~/.codex/herdr-agent-state.sh`（home.file） | `features/llm/codex.nix` の `[features] hooks = true` と `hooks.json` |
| hermes | `services.hermes-agent.extraPlugins`（`nix-managed-herdr-agent-state`） | `hosts/khali/hermes-agent.nix` の `plugins.enabled` |

herdr を更新すると integration のバージョン（claude v10 など）も変わる。そのときは
`herdr integration install` の出力と nix 側の登録内容（matcher・コマンド）がずれていないか確認する。
`herdr integration status` で `current` と出れば最新。

## バージョンの違い

| flake | nixpkgs | herdr | 備考 |
|---|---|---|---|
| workstations（khali, hail-mary） | nixpkgs-unstable | 0.9.1 | キャッシュに無い。Linux は ld.bfd のリンクエラー（`.eh_frame_hdr refers to overlapping FDEs`）を lld で回避 |
| infra（rin, jarvis, friday, silk 等） | nixos-unstable | 0.7.1 | キャッシュ済み。overlay は当てない。`herdr config check` が無い。0.9 系の設定キーが通らない可能性がある |

設定の検証（0.9 系）: `herdr config check`。存在しないアクション名も不正なキーも報告される。
不正な値は起動時に警告を出し、既定値に戻る。

## tmux → herdr のキー対応

herdr の用語: セッション → **workspace**、ウィンドウ → **tab**、ペイン → **pane**。prefix は tmux と同じ `Ctrl+Q`。

| tmux | herdr のアクション | herdr のキー |
|---|---|---|
| `\|` 左右分割 | `split_vertical` | `prefix+\|`、`prefix+v` |
| `-` 上下分割 | `split_horizontal` | `prefix+minus` |
| `h/j/k/l` ペイン移動 | `focus_pane_*` | `prefix+h/j/k/l`（既定のまま） |
| `H/J/K/L` リサイズ | `resize_pane_*` | `prefix+shift+h/j/k/l`（既定の `swap_pane_*` は外した） |
| `C-h` / `C-l` ウィンドウ移動 | `previous_tab` / `next_tab` | `prefix+ctrl+h` / `prefix+ctrl+l`（`prefix+p/n` も可） |
| `C-S-Tab` / `C-Tab`（prefix 無し） | `previous_tab` / `next_tab` | `ctrl+shift+tab` / `ctrl+tab` |
| `,` ウィンドウ名変更 | `rename_tab` | `prefix+comma`、`prefix+shift+t` |
| `&` ウィンドウを閉じる | `close_tab` | `prefix+ampersand`、`prefix+shift+x` |
| `c` / `n` / `p` / `1..9` / `x` / `z` / `[` | new_tab / next_tab / previous_tab / switch_tab / close_pane / zoom / copy_mode | 既定のまま（tmux と同じ） |
| `r` 設定リロード | `reload_config` | `prefix+r`（`resize_mode` は `prefix+shift+r` に移した） |
| `d` デタッチ | `detach` | `prefix+d` |
| `M-S-C` 新規セッション | `new_workspace` | `alt+shift+c` |
| `M-l` / `M-u` セッション移動 | `next_workspace` / `previous_workspace` | `alt+l` / `alt+u` |
| `M-e` table1（ツリー・セッション選択） | `goto` | `alt+e`（キーテーブルは無いので 1 キーにした） |
| `C-j` fzf セッションジャンプ | `workspace_picker` | `prefix+ctrl+j`、`prefix+w` |
| `g` go_dev | `[[keys.command]]` pane | `prefix+g` |
| `m` メニュー | `[[keys.command]]` popup | `prefix+m` |

### 再現していないもの

| tmux | 理由 |
|---|---|
| `G`（ssh ホスト名を聞いて新規ウィンドウ） | herdr に入力プロンプトが無い。リモートは herdr 自身の machine 接続（`herdr --remote`）を使う |
| `e`（synchronize-panes） | herdr に相当機能が無い。`prefix+e` は既定の `edit_scrollback` のまま |
| `F12`（入れ子用に prefix を無効化） | 相当機能が無い |
| `C-q` を中のアプリに送る（emacs の quoted-insert） | herdr に send-prefix のアクションが無い。prefix を 2 回押した場合の挙動は未確認 |
| prod/stg/other ウィンドウの背景色フック | フック機構が無い |
| resurrect / continuum | herdr のサーバーがセッションを保持する（detach/reattach） |

## 未確認（実機で確かめること）

- `prefix+|`（Shift を伴う記号）が実際に反応するか。`config check` は通る
- Ghostty → herdr で `ctrl+tab` / `alt+l` が届くか
- Claude Code の通知フック（`features/llm/claude/notify.ts` の OSC 777/9）が herdr を通って Ghostty の通知になるか。
  届かなければ herdr の `[ui.toast]` の delivery（`"terminal"` / `"system"`）を検討する
