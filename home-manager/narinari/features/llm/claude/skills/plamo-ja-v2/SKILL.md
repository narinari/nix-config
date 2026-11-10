---
name: plamo-ja-v2
description: Japanese display mode using a MessageDisplay hook. Claude writes in English, and a hook translates each paragraph with the local PLaMo 3 Translate server (localhost:8000) while the message streams. Use only when the user runs /plamo-ja-v2.
argument-hint: "[on|off|reset]"
disable-model-invocation: true
hooks:
  MessageDisplay:
    - hooks:
        - type: command
          command: |
            python3 -I -c "$(awk '/^```python hook.py$/{f=1;next} f&&/^```$/{exit} f' "$HOME/.claude/skills/plamo-ja-v2/SKILL.md")"
          timeout: 60
---

# plamo-ja-v2: Japanese display through a MessageDisplay hook

Argument given: `$ARGUMENTS` (empty means `on`).

This skill registers a `MessageDisplay` hook for the rest of the session. The hook changes **only
what is displayed**: the transcript and Claude's context keep the English text. The hook can't be
unregistered, so on/off is a flag file:

- `on` or empty: if `~/.cache/plamo-ja/v2/sessions/${CLAUDE_SESSION_ID}.off` exists (mode was turned off earlier),
  delete it. Otherwise run no command. Then follow the rules below.
- `off`: run `mkdir -p ~/.cache/plamo-ja/v2/sessions && touch ~/.cache/plamo-ja/v2/sessions/${CLAUDE_SESSION_ID}.off`.
  Stop following the rules below and reply normally.
- `reset`: clear the translation history. Run
  `python3 -I -c "$(awk '/^```python hook.py$/{f=1;next} f&&/^```$/{exit} f' ${CLAUDE_SKILL_DIR}/SKILL.md)" --session ${CLAUDE_SESSION_ID} --reset`

If the earlier `plamo-ja` skill (v1, Bash translation) is active in this session, stop following it now.
The hook replaces it.

## Rules while on

1. Write **all** user-facing text in English: progress notes and final replies. Don't run a
   translation command, and don't write Japanese yourself. The hook translates each paragraph as it streams.
2. Write so that it translates well: use plain, complete sentences, and avoid idioms and fragments.
   Separate paragraphs with blank lines. The hook translates each streamed batch of lines immediately,
   so keep every line a complete sentence or list item.
   Put code, commands, and paths in backticks or fenced blocks. Fenced blocks are shown unchanged.
3. The user writes in Japanese. Read it directly.
4. AskUserQuestion and other tool UIs are not covered by the hook. Before calling AskUserQuestion,
   translate the question and labels with:
   `python3 -I -c "$(awk '/^```python hook.py$/{f=1;next} f&&/^```$/{exit} f' ${CLAUDE_SKILL_DIR}/SKILL.md)" --session ${CLAUDE_SESSION_ID} <<'PLAMO_EOF'`
   …`PLAMO_EOF`, and use the Japanese it prints.
5. Confirm activation with a short English sentence (for example, "Japanese display mode is on.").

## Reference

- State: history `~/.cache/plamo-ja/v2/sessions/<session>.jsonl`, per-message stream state `~/.cache/plamo-ja/v2/msg/`.
- History: earlier (English, Japanese) pairs are sent as PLaMo translation history, about 8000 chars
  at most (`PLAMO_BUDGET`). When the history is over the limit, it is cut to half in one step, so the
  prompt prefix stays the same and llama-server's KV cache (with a pinned `id_slot`) keeps working.
- Optional: `~/.cache/plamo-ja/glossary.json`, `PLAMO_FORM=plain|polite`, `PLAMO_URL`.
- Each streamed batch is translated immediately, using the earlier pairs as history (so a paragraph
  split across batches keeps its context). If the server fails, that batch is shown in English.

```python hook.py
# plamo-ja-v2 hook v2
# MessageDisplay hook: translate Claude's English text to Japanese with a local PLaMo 3 Translate
# server while the message streams. Every batch of lines is translated as soon as it arrives
# (nothing is held back). Earlier batches are already in the translation history, so a paragraph
# split across batches is still translated with context. Fenced code passes through untouched. Also usable from the shell:
#   python3 -c "$(awk ...)" --session ID < english.txt   -> prints Japanese
import fcntl, json, os, re, sys, time, urllib.request, zlib

BASE = os.path.expanduser("~/.cache/plamo-ja/v2")
URL = os.environ.get("PLAMO_URL", "http://localhost:8000")
BUDGET = int(os.environ.get("PLAMO_BUDGET", "8000"))
STOP = ["<|plamo:tag|>", "<|plamo:bos|>"]
CONTEXT = ("Replies from an AI coding assistant (Claude Code) to a Japanese software "
           "developer in a terminal. Technical terms, file paths, commands and code stay as-is.")
FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
JA = re.compile(r"[぀-ヿ㐀-鿿ｦ-ﾟ]")
ALPHA = re.compile(r"[A-Za-z]")


def sess_paths(sid):
    sid = re.sub(r"[^A-Za-z0-9_.-]", "_", sid or "default")
    d = os.path.join(BASE, "sessions")
    os.makedirs(d, exist_ok=True)
    return sid, os.path.join(d, sid + ".jsonl"), os.path.join(d, sid + ".start"), os.path.join(d, sid + ".off")


def load_history(path):
    try:
        with open(path, encoding="utf-8") as f:
            return [json.loads(l) for l in f if l.strip()]
    except OSError:
        return []


def window(hist, state_path):
    """Start index only jumps in big steps (cut to half the budget), so the prompt prefix stays
    identical between jumps and llama-server's prefix KV cache keeps hitting."""
    try:
        start = min(int(open(state_path).read()), len(hist))
    except (OSError, ValueError):
        start = 0
    size = lambda i: sum(len(h["en"]) + len(h["ja"]) for h in hist[i:])
    if size(start) > BUDGET:
        while start < len(hist) and size(start) > BUDGET // 2:
            start += 1
        with open(state_path, "w") as f:
            f.write(str(start))
    return hist[start:]


def slot_for(sid):
    try:
        with urllib.request.urlopen(URL + "/props", timeout=3) as r:
            n = max(1, int(json.load(r).get("total_slots", 1)))
    except Exception:
        n = 1
    return zlib.crc32(sid.encode()) % n


def call(msgs, en, slot):
    kw = {"source_lang": "en", "target_lang": "ja", "context": CONTEXT}
    gpath = os.path.expanduser("~/.cache/plamo-ja/glossary.json")
    if os.path.exists(gpath):
        kw["glossary"] = json.load(open(gpath, encoding="utf-8"))
    form = os.environ.get("PLAMO_FORM")
    if form in ("plain", "polite"):
        kw["form"] = form
    body = {"model": "plamo-3-translate", "messages": msgs + [{"role": "user", "content": en}],
            "temperature": 0, "max_tokens": min(8192, len(en) * 3 + 256), "stop": STOP,
            "cache_prompt": True, "id_slot": slot, "chat_template_kwargs": kw}
    req = urllib.request.Request(URL + "/v1/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=50) as r:
        ja = json.load(r)["choices"][0]["message"]["content"]
    for s in STOP:
        ja = ja.replace(s, "")
    return ja.strip()


def looks_wrong(en, ja):
    prose = re.sub(r"`[^`]*`", "", en)
    if len(ALPHA.findall(prose)) >= 40 and len(JA.findall(ja)) < 5:
        return True
    return len(ja) > 3 * len(en) + 200


def translate(sid, en):
    """Translate one paragraph with session history; returns Japanese (or the English on error)."""
    body = en.rstrip("\n")
    tail = en[len(body):]
    if not ALPHA.search(body) or len(JA.findall(body)) * 3 > len(ALPHA.findall(body)):
        return en  # nothing to translate, or already Japanese
    sid, hpath, spath, _ = sess_paths(sid)
    hist = load_history(hpath)
    msgs = []
    for h in window(hist, spath):
        msgs += [{"role": "user", "content": h["en"]}, {"role": "assistant", "content": h["ja"]}]
    try:
        slot = slot_for(sid)
        ja = call(msgs, body, slot)
        if looks_wrong(body, ja):
            ja = call([], body, slot)
    except Exception as e:
        print(f"plamo-ja-v2: {e}", file=sys.stderr)
        return en
    with open(hpath, "a", encoding="utf-8") as f:
        f.write(json.dumps({"en": body, "ja": ja}, ensure_ascii=False) + "\n")
    return ja + (tail or "")


def process(sid, st, lines, final):
    """Feed complete lines through the paragraph/fence state machine; return text to display."""
    out = []

    def flush():
        if st["pending"]:
            out.append(translate(sid, "".join(st["pending"])))
            st["pending"] = []

    for line in lines:
        if st["fence"]:
            out.append(line)
            s = line.strip()
            if s and set(s) == {st["fence"][0]} and len(s) >= len(st["fence"]):
                st["fence"] = None
            continue
        m = FENCE.match(line)
        if m:
            flush(); out.append(line); st["fence"] = m.group(1); continue
        if not line.strip():
            flush(); out.append(line); continue
        st["pending"].append(line)
    flush()  # translate this batch now; earlier parts of the paragraph are in the history
    return "".join(out)


def hook():
    ev = json.load(sys.stdin)
    sid = ev.get("session_id", "default")
    _, _, _, offpath = sess_paths(sid)
    if os.path.exists(offpath):
        return  # mode is off: show the original
    mdir = os.path.join(BASE, "msg")
    os.makedirs(mdir, exist_ok=True)
    mid = re.sub(r"[^A-Za-z0-9_-]", "_", ev.get("message_id", "x"))
    mpath = os.path.join(mdir, mid + ".json")
    with open(os.path.join(BASE, "lock"), "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)  # batches of a message must be processed in order, once
        try:
            st = json.load(open(mpath))
        except (OSError, ValueError):
            st = {"pending": [], "fence": None, "done": {}}
        key = str(ev.get("index", 0))
        if key in st["done"]:  # same batch delivered twice (e.g. the skill was invoked twice)
            disp = st["done"][key]
        else:
            delta, final = ev.get("delta", ""), bool(ev.get("final"))
            disp = process(sid, st, delta.splitlines(keepends=True), final)
            st["done"][key] = disp
            with open(mpath, "w") as f:
                json.dump(st, f, ensure_ascii=False)
    # housekeeping: drop message state older than a day
    for n in os.listdir(mdir):
        p = os.path.join(mdir, n)
        if time.time() - os.path.getmtime(p) > 86400:
            os.remove(p)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "MessageDisplay",
                                             "displayContent": disp}}, ensure_ascii=False))


def cli():
    sid = sys.argv[sys.argv.index("--session") + 1] if "--session" in sys.argv else "default"
    if "--reset" in sys.argv:
        _, hpath, spath, _ = sess_paths(sid)
        for p in (hpath, spath):
            if os.path.exists(p):
                os.remove(p)
        print("plamo-ja-v2: history cleared", file=sys.stderr)
        return
    st = {"pending": [], "fence": None}
    sys.stdout.write(process(sid, st, sys.stdin.read().splitlines(keepends=True), True))


if __name__ == "__main__":
    (cli if len(sys.argv) > 1 else hook)()
```
