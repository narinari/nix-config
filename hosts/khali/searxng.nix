# SearXNG — hermes-agent の web_search バックエンド (localhost only)
#
# hermes-agent (v2026.5+) はネイティブで SearXNG を search backend として
# サポートする。SEARXNG_URL を渡し web.search_backend = "searxng" を設定すれば
# /search?format=json を直接叩いて結果を返す。
#
# テスト:
#   curl -s 'http://127.0.0.1:8888/search?q=nixos&format=json' | jq '.results | length'
_: {
  services.searx = {
    enable = true;
    # configureNginx は使わないが options 上必須なのでダミー指定。
    domain = "localhost";

    # built-in HTTP server (uwsgi 不使用) を localhost:8888 で起動。
    settings = {
      use_default_settings = true;

      server = {
        port = 8888;
        bind_address = "127.0.0.1";
        # localhost only ゆえハードコード可。他ホストへ公開する場合は
        # services.searx.environmentFile + "$SEARX_SECRET_KEY" 形式に置き換える。
        secret_key = "khali-local-searxng-not-a-secret";
        limiter = false; # rate limiter は redis 必須 + localhost なら不要
        image_proxy = true;
      };

      # hermes-agent / curl からの叩き用に JSON フォーマットを有効化する。
      # デフォルトは [ "html" ] のみで /search?format=json が 403 を返す。
      search.formats = [
        "html"
        "json"
      ];
    };
  };
}
