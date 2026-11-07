"""CLI 全体で使う例外。終了コードとの対応は cli.py で行う。"""


class InputError(Exception):
    """入力 (ファイル・引数・用語集) の不備。終了コード 1。"""


class ServerUnreachable(Exception):
    """llama-server に接続できない。終了コード 2。"""


class ServerError(Exception):
    """サーバーは応答したが、そのリクエストは成功しなかった (単位ごとの失敗)。"""
