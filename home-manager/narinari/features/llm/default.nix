{
  config,
  lib,
  pkgs,
  ...
}:

let
  claude-notify = pkgs.writeShellScript "claude-notify" ''
    # 標準入力からhookのInputデータを読み取り
    INPUT=$(cat)

    # 現在のセッションディレクトリ名を取得（hooksはsessionと同じディレクトリで実行される）
    SESSION_DIR=$(basename "$(pwd)")

    # transcript_pathを抽出
    TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')

    # transcript_pathが存在する場合、最新のassistantメッセージを取得
    if [ -f "$TRANSCRIPT_PATH" ]; then
        # 最後の10行から assistant のメッセージを抽出し、最新のもの（最後）を取得
        # 改行を削除して60文字に制限
        MSG=$(tail -10 "$TRANSCRIPT_PATH" | \
              jq -r 'select(.message.role == "assistant") | .message.content[0].text' | \
              tail -1 | \
              tr '\n' ' ' | \
              cut -c1-500)

        # メッセージが取得できない場合のフォールバック
        MSG=''${"MSG:-" "Task completed"}
    else
        MSG="Task completed"
    fi

    # ncで送信
    echo "{\"title\":\"$SESSION_DIR\",\"message\":\"$MSG\"}" | nc -N localhost 60000
  '';
in
{
  home.file.".local/bin/claude-notify.sh".source = claude-notify;

  home.packages = with pkgs; [
    uv # for serena
    goose-cli
    claude-code
  ];
}
