# Hermes daily-podcast — 状態ディレクトリの整備と、Hermes 内蔵 cron への
# daily ジョブ登録を担当する。
#
# 定期実行は Hermes 自身の cron 機能を使う:
#   hermes cron create '0 22 * * *' 'generate_all_today_episodes ツールを呼んで...' --name <name>
#
# これにより:
# - systemd timer は不要 (Nix 編集なしで Discord 経由の cronjob toolset で
#   追加・編集・削除ができる)
# - 結果を Discord 等に直接 deliver させる選択肢が増える (`--deliver discord`)
# - hermes-agent.service が常駐していれば自動で tick される
#
# 初回 seed では:
# 1. /var/lib/hermes-podcast の作成
# 2. topics.toml と static/cover.png を seed
# 3. 既定の cron job (hermes-daily-podcast-default) が無ければ作成 (冪等)
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

          # ── Hermes 内蔵 cron に daily job を登録 (冪等) ──
          # 22:00 JST = 13:00 UTC。hermes は OS の TZ で解釈するため、khali の
          # timezone (Asia/Tokyo を期待) に合わせる。
          JOB_NAME="hermes-daily-podcast-default"
          cd ${podcastStateDir}
          if ! ${pkgs.sudo}/bin/sudo -u hermes -E \
            ${config.services.hermes-agent.package}/bin/hermes cron list 2>/dev/null \
            | grep -q "$JOB_NAME"; then
            echo "[seed] registering Hermes cron job: $JOB_NAME"
            ${pkgs.sudo}/bin/sudo -u hermes -E \
              ${config.services.hermes-agent.package}/bin/hermes cron create \
                '0 22 * * *' \
                'generate_all_today_episodes ツールを呼んで、登録されている全 topic で今日の episode を一括生成してください。結果のサマリだけ返してください。' \
                --name "$JOB_NAME" || echo "[seed] cron create failed — register manually via Discord cronjob toolset"
          else
            echo "[seed] Hermes cron job $JOB_NAME already exists; skipping"
          fi
        '';
      };

      # ── 手動で 1 topic だけ再生成したいとき用の oneshot template ──
      # `systemctl start hermes-daily-podcast@<slug>` で呼べる。
      # Discord 経由なら直接 generate_daily_episode tool を叩いた方が早い。
      "hermes-daily-podcast@" = {
        description = "Generate today's hermes-daily-podcast episode for %i (manual one-shot)";
        after = [
          "hermes-agent.service"
          "network-online.target"
        ];
        wants = [
          "hermes-agent.service"
          "network-online.target"
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "hermes";
          Group = "hermes";
          WorkingDirectory = podcastStateDir;
          ExecStart = "${config.services.hermes-agent.package}/bin/hermes chat -q '%i トピックの今日の episode を生成して、結果の audio_url と feed_url を返してください' -Q -t daily-podcast --max-turns 5";
          TimeoutStartSec = "1800s";
        };
      };
    };
  };
}
