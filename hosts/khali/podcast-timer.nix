# Hermes daily-podcast — 状態ディレクトリの整備と、Hermes 内蔵 cron への
# daily ジョブ登録を担当する。
#
# 定期実行は Hermes cron の --no-agent モードを使う:
#   hermes cron create '0 22 * * *' --no-agent --script daily-podcast-generate-all.py --name <name>
#
# --no-agent はエージェント LLM を完全にスキップし、スクリプトの stdout を
# そのまま配信する。ジョブは「固定ツールを 1 回呼ぶ」だけの決定的処理で、
# エージェント会話 (27B が全ツール定義込み ~27k tokens を読む) は純粋な
# オーバーヘッドだったため v0.21 移行時に廃止した。エピソード内部の LLM
# (採点・要約) はプラグイン側でそのまま動く。
#
# 初回 seed では:
# 1. /var/lib/hermes-podcast の作成
# 2. topics.toml と static/cover.png を seed (無い場合のみ)
# 3. runner スクリプトを ~/.hermes/scripts/ へインストール (毎回上書き)
# 4. --no-agent cron job (hermes-daily-podcast-noagent) が無ければ、旧 LLM
#    駆動 job (hermes-daily-podcast-default) を削除して作成 (冪等)
#
# トピック追加で cron を増やす必要はない: generate_all_today_episodes が
# topics.toml の全 topic を毎晩巡回するため。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  podcastStateDir = "/var/lib/hermes-podcast";
in
{
  systemd = {
    tmpfiles.rules = [
      "d ${podcastStateDir} 0750 hermes hermes -"
      "d ${podcastStateDir}/episodes 0755 hermes hermes -"
    ];

    services = {
      # hermes-agent.service は ProtectSystem=strict /
      # ReadWritePaths=/var/lib/hermes の sandbox で動いている。podcastStateDir
      # はそのままだと read-only に見え、SQLite が WAL ファイル
      # (state.sqlite-wal / -shm) を作れずに `unable to open database file` で
      # 死ぬ。ReadWritePaths を append して episode mp3 / RSS / DB の write を
      # 許可する。
      hermes-agent.serviceConfig.ReadWritePaths = lib.mkAfter [ podcastStateDir ];

      hermes-daily-podcast-seed = {
        description = "Seed topics.toml + cover + Hermes cron job for daily-podcast";
        wantedBy = [ "multi-user.target" ];
        after = [ "hermes-agent.service" ];
        requires = [ "hermes-agent.service" ];
        path = [ pkgs.imagemagick ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
        };
        script = ''
          set -eu

          # ── topics.toml: 無ければ既定をコピー ──
          dst=${podcastStateDir}/topics.toml
          if [ ! -f "$dst" ]; then
            ${pkgs.coreutils}/bin/install -m 0640 -o hermes -g hermes \
              ${./topics.toml.default} "$dst"
          fi

          # ── static/cover.png: 無ければ ImageMagick で生成 ──
          static=${podcastStateDir}/static
          ${pkgs.coreutils}/bin/install -d -m 0755 -o hermes -g hermes "$static"
          cover="$static/cover.png"
          if [ ! -f "$cover" ]; then
            magick -size 1400x1400 \
              gradient:'#3b82f6'-'#1e3a8a' \
              -fill white -gravity center \
              -font DejaVu-Sans-Bold -pointsize 220 \
              -annotate +0-220 'Daily' \
              -pointsize 180 -annotate +0+40 'Podcast' \
              -pointsize 110 -annotate +0+260 'hermes-agent' \
              "$cover"
            ${pkgs.coreutils}/bin/chown hermes:hermes "$cover"
            ${pkgs.coreutils}/bin/chmod 0644 "$cover"
          fi

          # ── --no-agent runner スクリプト: 常に最新へ上書き ──
          scripts=/var/lib/hermes/.hermes/scripts
          ${pkgs.coreutils}/bin/install -d -m 0755 -o hermes -g hermes "$scripts"
          ${pkgs.coreutils}/bin/install -m 0755 -o hermes -g hermes \
            ${./podcast-generate-all.py} "$scripts/daily-podcast-generate-all.py"

          # ── Hermes 内蔵 cron に --no-agent daily job を登録 (冪等) ──
          # 22:00 JST。hermes は OS の TZ で解釈するため khali の timezone
          # (Asia/Tokyo を期待) に合わせる。旧 LLM 駆動 job からの移行:
          # 新 job が無ければ旧 job を削除してから作成する。
          OLD_JOB_NAME="hermes-daily-podcast-default"
          JOB_NAME="hermes-daily-podcast-noagent"
          cd ${podcastStateDir}
          if ! ${pkgs.sudo}/bin/sudo -u hermes -E \
            ${config.services.hermes-agent.package}/bin/hermes cron list 2>/dev/null \
            | grep -q "$JOB_NAME"; then
            ${pkgs.sudo}/bin/sudo -u hermes -E \
              ${config.services.hermes-agent.package}/bin/hermes cron remove "$OLD_JOB_NAME" \
              2>/dev/null || true
            echo "[seed] registering Hermes cron job: $JOB_NAME (--no-agent)"
            ${pkgs.sudo}/bin/sudo -u hermes -E \
              ${config.services.hermes-agent.package}/bin/hermes cron create \
                '0 22 * * *' \
                --name "$JOB_NAME" \
                --no-agent \
                --script daily-podcast-generate-all.py \
              || echo "[seed] cron create failed — register manually via Discord cronjob toolset"
          else
            echo "[seed] Hermes cron job $JOB_NAME already exists; skipping"
          fi
        '';
      };

    };
  };
}
