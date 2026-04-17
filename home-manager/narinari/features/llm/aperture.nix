# Tailscale Aperture (AI Gateway) クライアント設定
#
# Aperture は Tailscale のマネージドAIゲートウェイで、tailnet 内のデバイスから
# http://ai 経由で LLM API にアクセスできる。
# 事前に aperture.tailscale.com でセットアップし、プロバイダーの API キーを登録すること。
#
# テスト (Anthropic):
#   curl -s http://ai/v1/messages \
#     -H "Content-Type: application/json" \
#     -d '{"model":"claude-haiku-4-5-20251001","max_tokens":25,"messages":[{"role":"user","content":"hello"}]}'
#
# テスト (OpenAI):
#   curl -s http://ai/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model":"gpt-4o","messages":[{"role":"user","content":"hello"}]}'
{ lib, pkgs, ... }:

{
  home.sessionVariables = {
    # AI API リクエストを Aperture 経由でルーティング
    # ANTHROPIC_BASE_URL = "http://ai"; # Claude Code
    OPENAI_BASE_URL = "http://ai/v1"; # Codex CLI / OpenAI SDK
  };

  # Claude Code: Aperture 経由では Tailscale identity で認証するためダミーキーを設定
  # features/llm/default.nix が settings.json をデプロイした後に apiKeyHelper をパッチ
  # home.activation.claudeApertureSettings = lib.hm.dag.entryAfter [ "claudeSettings" ] ''
  #   settings="$HOME/.claude/settings.json"
  #   if [ -f "$settings" ]; then
  #     run ${pkgs.jq}/bin/jq --arg helper "echo '-'" '. + {apiKeyHelper: $helper}' "$settings" > "''${settings}.aperture.tmp"
  #     run mv "''${settings}.aperture.tmp" "$settings"
  #   fi
  # '';
}
