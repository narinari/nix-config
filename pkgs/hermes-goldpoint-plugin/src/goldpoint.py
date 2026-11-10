"""GOLD POINT CARD+ 明細取得 (ログイン → CSV fetch → ログアウト)。

サイト仕様 (2026-09-27 実機確認、リバースエンジニアリング済みの確定情報。
変更禁止):

- ログインページ: https://secure.goldpoint.co.jp/gpm/authentication/index.html
  フォーム: <form id="form" action=".../gpm/authentication/login.html" method="post">
- ID欄 `#authenticateDO\\.authKey` はページロード直後 type=hidden で、サイトの
  JS が後から type=text に書き換える (bot 対策)。type が text かつ
  offsetWidth>0 になるまで poll してから値を入れること。
- パスワード欄 `#authenticateDO\\.password` (type=password)。
- 送信は `#loginButton` (input type=image) の click()。
- hidden に乱数16進名トークン2つ + serializedBase64 があり、サイトの JS が
  埋める。HTTP直叩きでの再現は不可 — 実ブラウザ (Chromium + CDP) で
  フォーム入力する必要がある。JS での値代入による送信は headless / headed とも
  "Access Denied" になる (2026-11-10 確認)。既定は headless で、検出対策は下記と
  cdp.py (起動フラグ・永続プロファイル) を参照。GOLDPOINT_HEADED=1 で Xvfb 上の headed。
- 値の入力は CDP Input ドメインの実イベントで行う (human_input.py)。JS での value 代入は
  Akamai に Access Denied にされる (2026-11-10 確認)。旧方式: el.value 代入 + input/change を
  dispatchEvent する。
- ログイン成功時は https://secure.goldpoint.co.jp/gpm/membertop.html に遷移する。
- 明細ページ: https://secure.goldpoint.co.jp/memx/web_meisai/top/index.html?p01=YYYYMM
  を先に開いてから (Referer / セッション文脈のため) CSV API を叩くこと。
- CSV API: GET https://secure.goldpoint.co.jp/memapi/jaxrs/dl/web_meisai/
  web_meisai_csv_exec/v1?downloadKey=1&seikyuym=YYYYMM&sk=&downloadtype=csv&mk=1
  をページ内 `fetch(url, {credentials:"include"})` で叩くと 200 が返る
  (content-type: application/force-download;charset=Windows-31J)。
  戻り値は arrayBuffer → Uint8Array → 0x8000 要素ずつ chunk して
  String.fromCharCode.apply → btoa で base64 化し、CDP の Runtime.evaluate
  戻り値として受け取る (大きい CSV でも引数過多にならないための chunk 単位)。
- CSV は Shift_JIS (Windows-31J) / CRLF。1行目はカード名義ヘッダ。
  変換せず、そのままバイト列で保存する。
- 請求月セレクタ (id は変わる: 2026-11 時点 `#vp-view-VC0501002_RS0001_p01`) に
  直近18ヶ月分の YYYYMM が入っている。明細ページは JS で後から描画される。
  fetch_statements_csv() はページ上の select から YYYYMM の option 値を集める。未確定の月 (当月など) は CSV API が 200 + 空ボディを返す。
- ログアウトは https://secure.goldpoint.co.jp/gpm/logout.html への遷移のみ。

セキュリティ: password / CSV バイト列は、ここでは戻り値にも例外メッセージ
にもログにも出さない。ログイン失敗時の CDP 例外 (exceptionDetails.text) は
入力値混入のリスクがあるため、下位の生メッセージをそのまま伝播させず
自前の汎用メッセージに変換する。
"""

from __future__ import annotations

import asyncio
import contextlib
import base64
import json
import logging
import re
from typing import AsyncIterator, Callable

from . import cdp
from . import human_input

logger = logging.getLogger(__name__)

LOGIN_URL = "https://secure.goldpoint.co.jp/gpm/authentication/index.html"
MEMBER_TOP_URL = "https://secure.goldpoint.co.jp/gpm/membertop.html"
MEISAI_PAGE_URL_TMPL = (
    "https://secure.goldpoint.co.jp/memx/web_meisai/top/index.html?p01={seikyuym}"
)
CSV_API_URL_TMPL = (
    "https://secure.goldpoint.co.jp/memapi/jaxrs/dl/web_meisai/"
    "web_meisai_csv_exec/v1?downloadKey=1&seikyuym={seikyuym}&sk=&downloadtype=csv&mk=1"
)
LOGOUT_URL = "https://secure.goldpoint.co.jp/gpm/logout.html"
# 請求月は「option 値が YYYYMM の select」から読む。select の id はサイト側で
# 変わる (2026-09: vp-view-VC0502-003_RS0001_p01 → 2026-11: vp-view-VC0501002_RS0001_p01)
# ため id には依存しない。
SEIKYUYM_VALUE_PATTERN = re.compile(r"^\d{6}$")

LOGIN_FIELD_POLL_TIMEOUT_SECONDS = 15
LOGIN_NAV_TIMEOUT_SECONDS = 20
LOGIN_FAILURE_TEXT_LIMIT = 300  # 診断用エラー文言の最大長
# 明細ページ (JS で後から描画) の請求月セレクタに選択肢が入るまで待つ上限。
MONTH_SELECT_POLL_TIMEOUT_SECONDS = 30
# ボット対策 JS がページ上の計測を送り終えるまで、入力前に滞在する時間。
LOGIN_DWELL_RANGE_SECONDS = (4.0, 7.0)
# 欄の移動やボタンを押す前の「考える」間。
FIELD_GAP_RANGE_SECONDS = (0.6, 1.4)
# 大きい CSV でも `String.fromCharCode.apply` が引数過多で落ちないための chunk 単位。
CSV_FETCH_CHUNK_SIZE = 0x8000


class GoldpointError(Exception):
    """ログイン失敗 / CSV 取得失敗など。パスワードや CSV 内容は含めない。"""


def fetch_statement_csv(*, auth_key: str, password: str, seikyuym: str) -> bytes:
    """ログイン → 明細ページ → CSV fetch → ログアウト を行い、CSV の生バイト列を返す。

    handler は sync なので asyncio.run() でラップする。
    """
    return asyncio.run(
        _fetch_statement_csv_async(
            auth_key=auth_key, password=password, seikyuym=seikyuym
        )
    )


async def _fetch_statement_csv_async(
    *, auth_key: str, password: str, seikyuym: str
) -> bytes:
    async with _logged_in_session(auth_key=auth_key, password=password) as session:
        await session.goto(MEISAI_PAGE_URL_TMPL.format(seikyuym=seikyuym))
        csv_bytes = await _fetch_csv_via_page(session, seikyuym=seikyuym)

    if csv_bytes is None:
        raise GoldpointError("CSV API returned no data")
    return csv_bytes


def fetch_statements_csv(
    *,
    auth_key: str,
    password: str,
    current_seikyuym: str,
    wanted: Callable[[list[str]], list[str]],
) -> dict[str, bytes | None]:
    """1 セッションで、取得可能な月のうち wanted() が選んだ月の CSV をまとめて取得する。

    戻り値は seikyuym -> CSV バイト列。API が 200 + 空ボディ (未確定) の月は None。
    """
    return asyncio.run(
        _fetch_statements_csv_async(
            auth_key=auth_key,
            password=password,
            current_seikyuym=current_seikyuym,
            wanted=wanted,
        )
    )


async def _fetch_statements_csv_async(
    *,
    auth_key: str,
    password: str,
    current_seikyuym: str,
    wanted: Callable[[list[str]], list[str]],
) -> dict[str, bytes | None]:
    results: dict[str, bytes | None] = {}
    async with _logged_in_session(auth_key=auth_key, password=password) as session:
        await session.goto(MEISAI_PAGE_URL_TMPL.format(seikyuym=current_seikyuym))
        available = await _read_available_months(session)
        for seikyuym in wanted(available):
            await session.goto(MEISAI_PAGE_URL_TMPL.format(seikyuym=seikyuym))
            results[seikyuym] = await _fetch_csv_via_page(session, seikyuym=seikyuym)
    return results


@contextlib.asynccontextmanager
async def _logged_in_session(
    *, auth_key: str, password: str
) -> AsyncIterator[cdp.CdpSession]:
    """ログイン済みセッションを返し、抜けるとき (例外時も) 必ずログアウトする。

    プロファイルを使い回すため、前回の失敗でログイン cookie が残っていると
    ログインページにフォームが出ない。最初にログアウトして状態を揃える。
    """
    async with cdp.CdpSession() as session:
        await _logout_best_effort(session)
        await session.goto(LOGIN_URL)
        human = human_input.HumanInput(session)
        await _fill_login_form(session, human, auth_key=auth_key, password=password)
        await _submit_login(human)
        await _wait_for_login_success(session)
        try:
            yield session
        finally:
            await _logout_best_effort(session)


def parse_available_months(raw_values: list[object]) -> list[str]:
    """セレクタの option 値から YYYYMM だけを残し、重複を除いて昇順に並べる。"""
    valid = {v for v in raw_values if isinstance(v, str) and SEIKYUYM_VALUE_PATTERN.match(v)}
    return sorted(valid)


async def _read_available_months(session: cdp.CdpSession) -> list[str]:
    """請求月セレクタの option 値を読む。明細ページは JS で後から描画されるため poll する。"""
    expr = (
        "(() => {"
        "const vals = Array.from(document.querySelectorAll('select'))"
        ".flatMap(s => Array.from(s.options).map(o => o.value))"
        ".filter(v => /^\\d{6}$/.test(v));"
        "return vals.length ? vals : null;"
        "})()"
    )
    try:
        raw = await session.poll_js(expr, timeout=MONTH_SELECT_POLL_TIMEOUT_SECONDS)
    except cdp.CdpError:
        raw = None
    months = parse_available_months(raw) if isinstance(raw, list) else []
    if not months:
        where = await _describe_meisai_page(session)
        raise GoldpointError(
            "statement month selector not found (site markup may have changed) "
            f"[{where}]"
        )
    return months


async def _describe_meisai_page(session: cdp.CdpSession) -> str:
    """診断: 現在のパス・タイトルと、ページ上の select 要素の id 一覧 (値は読まない)。"""
    expr = (
        "(() => location.pathname + ' title=' + document.title + ' selects='"
        " + Array.from(document.querySelectorAll('select')).map(s => s.id || '?')"
        f".join(',').slice(0, {LOGIN_FAILURE_TEXT_LIMIT}))()"
    )
    try:
        value = await session.eval_js(expr)
    except cdp.CdpError:
        return "page state unavailable"
    return str(value) if value else "page state unavailable"


async def _logout_best_effort(session: cdp.CdpSession) -> None:
    # ログアウトはベストエフォート。失敗しても取得済み CSV は返す。
    try:
        await session.goto(LOGOUT_URL)
    except cdp.CdpError:
        logger.warning("goldpoint: logout navigation failed (non-fatal)")


async def _fill_login_form(
    session: cdp.CdpSession,
    human: human_input.HumanInput,
    *,
    auth_key: str,
    password: str,
) -> None:
    # bot 対策: authKey 欄は type=hidden で始まり、サイト JS が type=text に
    # 書き換えるまで待つ必要がある (offsetWidth>0 で「表示された」を判定)。
    ready_expr = (
        "(() => {"
        "const el = document.getElementById('authenticateDO.authKey');"
        "return !!el && el.type === 'text' && el.offsetWidth > 0;"
        "})()"
    )
    try:
        await session.poll_js(ready_expr, timeout=LOGIN_FIELD_POLL_TIMEOUT_SECONDS)
        await human.pause(*LOGIN_DWELL_RANGE_SECONDS)
        await human.click_element("authenticateDO.authKey")
        await human.type_text(auth_key)
        await human.pause(*FIELD_GAP_RANGE_SECONDS)
        await human.click_element("authenticateDO.password")
        await human.type_text(password)
        await human.pause(*FIELD_GAP_RANGE_SECONDS)
    except (cdp.CdpError, human_input.InputError):
        # exceptionDetails.text に入力値の一部が混入するリスクがあるため、
        # 元例外の文字列は伝播させず汎用メッセージに変換する。
        # 代わりに、入力値を読まない診断 (パス・タイトル・エラー表示) を付ける。
        where = await _describe_login_failure(session)
        raise GoldpointError(
            f"failed to fill login form (site markup may have changed) [{where}]"
        ) from None


async def _submit_login(human: human_input.HumanInput) -> None:
    try:
        await human.click_element("loginButton")
    except (cdp.CdpError, human_input.InputError):
        raise GoldpointError("failed to click login button") from None


async def _wait_for_login_success(session: cdp.CdpSession) -> None:
    try:
        await session.poll_js(
            f"location.href.indexOf({json.dumps(MEMBER_TOP_URL)}) === 0",
            timeout=LOGIN_NAV_TIMEOUT_SECONDS,
        )
    except cdp.CdpError:
        where = await _describe_login_failure(session)
        raise GoldpointError(
            "login failed: did not reach membertop.html "
            f"(auth key/password mismatch, or site markup changed) [{where}]"
        ) from None


async def _describe_login_failure(session: cdp.CdpSession) -> str:
    """失敗時の診断: 現在のパスとエラー表示らしき要素の文言だけを返す。

    入力欄の値は読まない (エラー表示要素の innerText のみ、長さも制限する)。
    """
    expr = (
        "(() => {"
        "const errs = Array.from(document.querySelectorAll("
        "'[class*=error], [class*=Error], [id*=error], [id*=Error], .alert'))"
        ".map(e => (e.innerText || '').trim()).filter(t => t).join(' / ');"
        "return location.pathname + ' title=' + document.title"
        f" + ' errors=' + errs.slice(0, {LOGIN_FAILURE_TEXT_LIMIT});"
        "})()"
    )
    try:
        value = await session.eval_js(expr)
    except cdp.CdpError:
        return "page state unavailable"
    return str(value) if value else "page state unavailable"


async def _fetch_csv_via_page(
    session: cdp.CdpSession, *, seikyuym: str
) -> bytes | None:
    """CSV を取得する。200 + 空ボディ (未確定月) は None、非 200 は GoldpointError。"""
    url = CSV_API_URL_TMPL.format(seikyuym=seikyuym)
    result = await session.eval_js(_csv_fetch_js(url))
    if not isinstance(result, dict) or not result.get("ok"):
        status = result.get("status") if isinstance(result, dict) else None
        raise GoldpointError(f"CSV API request failed (status={status})")
    b64 = result.get("data_base64")
    if not isinstance(b64, str) or not b64:
        return None
    return base64.b64decode(b64)


def _csv_fetch_js(url: str) -> str:
    """ページ内 fetch → arrayBuffer → base64 化 (0x8000 要素ずつ chunk)。"""
    return (
        "(async () => {"
        f"const res = await fetch({json.dumps(url)}, {{credentials: 'include'}});"
        "if (!res.ok) { return {ok: false, status: res.status}; }"
        "const buf = await res.arrayBuffer();"
        "const bytes = new Uint8Array(buf);"
        f"const chunkSize = {CSV_FETCH_CHUNK_SIZE};"
        "let binary = '';"
        "for (let i = 0; i < bytes.length; i += chunkSize) {"
        "  const chunk = bytes.subarray(i, i + chunkSize);"
        "  binary += String.fromCharCode.apply(null, chunk);"
        "}"
        "return {ok: true, status: res.status, data_base64: btoa(binary)};"
        "})()"
    )
