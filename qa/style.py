"""Code style for the Sterling Lua files (see docs/DEVELOPMENT.md, "Code style").

Formatting only. It changes whitespace and line breaks and never the order of anything:
    1. 4 spaces per indent level (the code was written with 2).
    2. A multi-line table's opening { goes on its own line ("local t =" then "{").
    3. A short statement that was split over a few lines is joined back onto one (up to 160 characters).
    4. A blank line after the end of every multi-line block (end, }, until), unless more closing follows.
    5. Lines in the same block are grouped by how they start (local, if, return, a call, an assignment...),
       with a blank line between groups. A comment stays with the code below it.

    python3 qa/style.py Sterling/*.lua          rewrites the files
    python3 qa/style.py --check Sterling/*.lua  only reports files that aren't formatted (exit 1)
    --from2 also moves 2-space indents to 4 (used once, for the move to this style)

A formatted file compiles to exactly the same bytes as before: luac5.1 -s strips line numbers and local names.
qa/t_style.py checks that for every add-on file.
"""
import re
import sys

MAX = 160
OPENERS = "({["
CLOSERS = ")}]"
BLOCK_OPEN = {"function", "do", "then", "repeat"}
BLOCK_CLOSE = {"end", "until", "elseif"}
CLOSING_START = re.compile(r"^(end\b|else\b|elseif\b|until\b|[)}\]])")
CONTINUES = {"=", ",", "(", "{", "[", "..", "+", "-", "*", "/", "%", "^", "<", ">", "<=", ">=", "==", "~="}
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


class Line:
    def __init__(self, text):
        self.text = text
        self.indent = len(text) - len(text.lstrip(" "))
        self.body = text.strip()
        self.code = ""          # the line without its trailing comment, stripped
        self.comment = False    # the line is only a comment
        self.has_comment = False
        self.in_long = False    # starts inside a long string or comment
        self.ends_long = False  # ends inside a long string or comment
        self.tokens = []        # (kind, value, column)
        self.stack_start = []   # open constructs at the start of the line: (kind, opener line index)
        self.stack_end = []


def scan(lines):
    """Tokenise every line and record which brackets and blocks are open at each line start."""
    stack = []
    long_close = None
    for i, ln in enumerate(lines):
        s = ln.text
        ln.stack_start = list(stack)
        ln.in_long = long_close is not None
        pos = 0
        code_end = len(s)
        if long_close:
            j = s.find(long_close)
            if j < 0:
                ln.ends_long = True
                continue
            pos = j + len(long_close)
            long_close = None
        while pos < len(s):
            c = s[pos]
            if c in " \t":
                pos += 1
                continue
            if s.startswith("--", pos):
                m = re.match(r"--\[(=*)\[", s[pos:])
                if m:
                    close = "]" + m.group(1) + "]"
                    j = s.find(close, pos + len(m.group(0)))
                    if j < 0:
                        long_close = close
                        ln.ends_long = True
                        code_end = pos
                        break
                    pos = j + len(close)
                    ln.has_comment = True
                    continue
                code_end = pos
                ln.has_comment = True
                break
            m = re.match(r"\[(=*)\[", s[pos:])
            if m:
                close = "]" + m.group(1) + "]"
                j = s.find(close, pos + len(m.group(0)))
                if j < 0:
                    long_close = close
                    ln.ends_long = True
                    ln.tokens.append(("str", "[[", pos))
                    break
                ln.tokens.append(("str", s[pos:j + len(close)], pos))
                pos = j + len(close)
                continue
            if c in "'\"":
                j = pos + 1
                while j < len(s) and s[j] != c:
                    j += 2 if s[j] == "\\" else 1
                ln.tokens.append(("str", s[pos:j + 1], pos))
                pos = j + 1
                continue
            m = IDENT.match(s, pos)
            if m:
                w = m.group(0)
                ln.tokens.append(("name", w, pos))
                if w in BLOCK_CLOSE:
                    while stack and stack[-1][0] != "block":
                        stack.pop()     # never happens in valid code; keeps the stack sane
                    if stack:
                        stack.pop()
                if w in BLOCK_OPEN:
                    stack.append(("block", i))
                pos = m.end()
                continue
            m = re.match(r"\d[\w.]*|\.\d+[\w]*", s[pos:])
            if m:
                ln.tokens.append(("num", m.group(0), pos))
                pos += len(m.group(0))
                continue
            m = re.match(r"\.\.\.|\.\.|==|~=|<=|>=|.", s[pos:])
            op = m.group(0)
            ln.tokens.append(("op", op, pos))
            if op in OPENERS:
                stack.append(("bracket", i))
            elif op in CLOSERS and stack:
                stack.pop()
            pos += len(op)
        ln.code = s[:code_end].strip()
        ln.comment = ln.code == "" and ln.has_comment and not ln.in_long
        ln.stack_end = list(stack)
    return lines


def key(ln):
    """What kind of statement a line starts: lines of the same kind are kept together."""
    if ln.comment:
        return "comment"
    names = ln.tokens
    if not names:
        return "other"
    k, w, _ = names[0]
    if k == "name":
        if w == "local":
            return "function" if len(names) > 1 and names[1][1] == "function" else "local"
        if w == "function":
            return "function"
        if w == "if":
            return "if"
        if w in ("for", "while", "repeat"):
            return "loop"
        if w in ("return", "break", "goto"):
            return "return"
        if w == "do":
            return "do"
    depth = 0
    for k, v, _ in names:
        if k != "op":
            continue
        if v in OPENERS:
            depth += 1
        elif v in CLOSERS:
            depth -= 1
        elif v == "=" and depth == 0:
            return "assign"
    return "call"


def reindent(lines):
    """One-time move from 2 to 4 spaces per level. Lines lined up under a bracket or continuing the line above
    move by the same amount as the line they hang from, so the alignment survives."""
    out = []
    last = None
    for ln in lines:
        if ln.in_long:
            out.append(ln.text)
            continue
        if ln.body == "":
            out.append("")
            continue
        top = ln.stack_start[-1] if ln.stack_start else None
        hang = None
        if top and top[0] == "bracket":
            opener = lines[top[1]]
            if ln.indent % 2 or (ln.indent > opener.indent + 2 and not CLOSING_START.match(ln.body)):
                hang = opener
        elif ln.indent % 2 and last is not None:
            hang = last
        out.append(" " * (ln.indent + hang.indent if hang else ln.indent * 2) + ln.body)
        last = ln
    return out


def glue(a, b):
    """Joins two pieces of one statement with the spacing the code already uses: f(a, b) and { a, b }."""
    if a.endswith("{"):
        return a + " " + b
    if a.endswith(("(", "[")) or b.startswith((")", "]", ",")):
        return a + b
    return a + " " + b


def join_short(lines):
    """Rule 5: a bracket opened at the end of a line and closed within a few lines is joined if it fits."""
    out = []
    i = 0
    n = len(lines)
    while i < n:
        ln = lines[i]
        opened = len(ln.stack_end) - len(ln.stack_start)
        if ln.in_long or ln.ends_long or ln.has_comment or opened != 1 or ln.stack_end[-1][0] != "bracket" or ln.body == "{":
            out.append(ln.text)
            i += 1
            continue
        target = len(ln.stack_start)
        j = i + 1
        ok = False
        while j < n and j - i <= 6:
            lj = lines[j]
            if lj.in_long or lj.ends_long or lj.has_comment or lj.body == "":
                break
            if any(t[0] == "name" and t[1] in ("function", "if", "for", "while", "do", "repeat", "local", "return", "end") for t in lj.tokens):
                break
            if len(lj.stack_end) < target or (len(lj.stack_end) == target and lj.stack_end != ln.stack_start):
                break
            if len(lj.stack_end) == target:
                ok = True
                break
            j += 1
        if ok:
            joined = ln.text.rstrip()
            for k in range(i + 1, j + 1):
                joined = glue(joined, lines[k].body)
            if len(joined) <= MAX:
                out.append(joined)
                i = j + 1
                continue
        out.append(ln.text)
        i += 1
    return out


def brace_lines(lines):
    """Rule 3: an opening { is never the last thing on a line; it moves to its own line."""
    out = []
    for ln in lines:
        code = ln.code
        if not ln.in_long and not ln.ends_long and code.endswith("{") and code != "{" and len(ln.stack_end) > len(ln.stack_start):
            last = [t for t in ln.tokens if t[0] == "op" and t[1] == "{"][-1]
            head = ln.text[:last[2]].rstrip()
            rest = ln.text[last[2]:]
            if head.strip():
                out.append(head)
                out.append(" " * ln.indent + rest.strip())
                continue
        out.append(ln.text)
    return out


def spacing(lines):
    """Rules 4 and 6: blank line after a multi-line block, and between groups of different kinds of line."""
    out = []
    for i, ln in enumerate(lines):
        if out and ln.body and not ln.in_long and out[-1].strip():
            prev = lines[i - 1]
            blank = False
            closes = prev.body and not prev.in_long and not prev.comment and re.match(r"^(end\b|until\b|[}\])])", prev.code or "")
            # the closing line ends something opened on an earlier line
            if closes and len(prev.stack_end) < len(prev.stack_start) and prev.stack_start[-1][1] < i - 1:
                blank = not CLOSING_START.match(ln.body)
            elif (not prev.in_long and not prev.ends_long and prev.stack_end == ln.stack_start and ln.stack_start == prev.stack_start
                  and (not ln.stack_start or ln.stack_start[-1][0] == "block") and ln.indent == prev.indent and not CLOSING_START.match(ln.body)):
                kp, kn = key(prev), key(ln)
                if kp != "comment" and kn != kp:
                    blank = True
            # never split a statement that carries on from the line above ("local t =" then "{")
            last = prev.tokens[-1] if prev.tokens and not prev.ends_long else None
            if last and ((last[0] == "op" and last[1] in CONTINUES) or (last[0] == "name" and last[1] in ("and", "or", "not", "return", "local", "in"))):
                blank = False
            if ln.body.startswith(("{", "(", "[")):
                blank = False
            if blank:
                out.append("")
        out.append(ln.text)
    return out


def fmt(src, from2=False):
    nl_end = src.endswith("\n")
    text = src.split("\n")
    if nl_end:
        text = text[:-1]
    passes = [reindent] if from2 else []
    passes += [
        lambda L: join_short(L),
        lambda L: brace_lines(L),
        lambda L: spacing(L),
    ]
    cur = text
    for p in passes:
        cur = p(scan([Line(t) for t in cur]))
    cur = [t.rstrip() for t in cur]
    # never more than one blank line in a row
    res = []
    for t in cur:
        if t == "" and res and res[-1] == "":
            continue
        res.append(t)
    return "\n".join(res) + ("\n" if nl_end else "")


def main(argv):
    check = "--check" in argv
    from2 = "--from2" in argv
    files = [a for a in argv if not a.startswith("--")]
    bad = 0
    for f in files:
        src = open(f, encoding="utf-8").read()
        new = fmt(src, from2)
        if new != src:
            bad += 1
            if check:
                print("not formatted:", f)
            else:
                open(f, "w", encoding="utf-8", newline="\n").write(new)
                print("formatted:", f)
    if check:
        print("STYLE OK" if not bad else "STYLE: %d file(s) need qa/style.py" % bad)
    return 1 if (check and bad) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
