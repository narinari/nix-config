# Hermes goldpoint-meisai — 状態ディレクトリの整備と、Hermes 内蔵 cron への
# 月次ジョブ登録を担当する。
#
# 定期実行は Hermes cron の --no-agent モードを使う:
#   hermes cron create '0 9 11 * *' --no-agent --script goldpoint-fetch-statement.py --name <name>
#
# --no-agent はエージェント LLM を完全にスキップし、スクリプトの stdout を
# そのまま配信する。ジョブは「固定ツールを 1 回呼ぶ」だけの決定的処理で、
# エージェント会話 (27B が全ツール定義込み ~27k tokens を読む) は純粋な
# オーバーヘッドなので daily-podcast と同じ方針で --no-agent にする。
#
# スケジュール: 毎月11日 09:00 JST — 明細は毎月10日に確定するため。
#
# 初回 seed では:
# 1. /var/lib/hermes-goldpoint (+ csv/) の作成
# 2. runner スクリプトを ~/.hermes/scripts/ へインストール (毎回上書き)
# 3. --no-agent cron job (hermes-goldpoint-meisai-noagent) が無ければ作成 (冪等)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  goldpointStateDir = "/var/lib/hermes-goldpoint";
in
{
  systemd = {
    tmpfiles.rules = [
      "d ${goldpointStateDir} 0750 hermes hermes -"
      "d ${goldpointStateDir}/csv 0755 hermes hermes -"
    ];

    services = {
      # hermes-agent.service は ProtectSystem=strict /
      # ReadWritePaths=/var/lib/hermes の sandbox で動いている。goldpointStateDir
      # はそのままだと read-only に見え、CSV 保存や gdrive_token.json の書き込みが
      # 失敗する。ReadWritePaths を append して write を許可する
      # (podcast-timer.nix の podcastStateDir と同じ理由)。
      hermes-agent.serviceConfig.ReadWritePaths = lib.mkAfter [ goldpointStateDir ];

      hermes-goldpoint-seed = {
        description = "Seed Hermes cron job for goldpoint-meisai";
        wantedBy = [ "multi-user.target" ];
        after = [ "hermes-agent.service" ];
        requires = [ "hermes-agent.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
        };
        script = ''
          set -eu

          # ── --no-agent runner スクリプト: 常に最新へ上書き ──
          scripts=/var/lib/hermes/.hermes/scripts
          ${pkgs.coreutils}/bin/install -d -m 0755 -o hermes -g hermes "$scripts"
          ${pkgs.coreutils}/bin/install -m 0755 -o hermes -g hermes \
            ${./goldpoint-fetch-statement.py} "$scripts/goldpoint-fetch-statement.py"

          # ── Hermes 内蔵 cron に --no-agent 月次 job を登録 (冪等) ──
          # 毎月11日 09:00 JST — 明細は毎月10日に確定するため。
          JOB_NAME="hermes-goldpoint-meisai-noagent"
          cd ${goldpointStateDir}
          if ! ${pkgs.sudo}/bin/sudo -u hermes -E \
            ${config.services.hermes-agent.package}/bin/hermes cron list 2>/dev/null \
            | grep -q "$JOB_NAME"; then
            echo "[seed] registering Hermes cron job: $JOB_NAME (--no-agent)"
            ${pkgs.sudo}/bin/sudo -u hermes -E \
              ${config.services.hermes-agent.package}/bin/hermes cron create \
                '0 9 11 * *' \
                --name "$JOB_NAME" \
                --no-agent \
                --script goldpoint-fetch-statement.py \
              || echo "[seed] cron create failed — register manually via Discord cronjob toolset"
          else
            echo "[seed] Hermes cron job $JOB_NAME already exists; skipping"
          fi
        '';
      };
    };
  };
}
