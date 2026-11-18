"""Finds every local variable in a Lua file and every place it is used, so locals can be renamed safely.

    python3 qa/scopes.py Sterling/Core.lua          lists the locals (line, name, uses)

Used for the readability pass: a rename touches only the declaration and the uses this finds, and
qa/bytecode.sh then proves the file still compiles to the same code.
"""
import sys

import style

KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not",
            "or", "repeat", "return", "then", "true", "until", "while", "goto"}


class Decl:
    def __init__(self, name, kind, line, tok, func):
        self.name = name
        self.kind = kind        # local, param, for, function
        self.line = line
        self.tok = tok          # index into the token list
        self.func = func        # the declaration index of the enclosing function's name, or None
        self.uses = []          # token indexes
        self.fields = set()     # x.field / x:method seen on it
        self.init = ""          # source text after "=" on the declaring line (locals), or the for iterator
        self.scope_end = None   # token index where its scope ends
        self.inner = set()      # names visible somewhere inside its scope (for collision checks)


def tokens_of(src):
    lines = style.scan([style.Line(t) for t in src.split("\n")])
    toks = []

    for li, ln in enumerate(lines):
        for k, v, col in ln.tokens:
            toks.append((k, v, li, col))

    return lines, toks


def analyse(src):
    lines, toks = tokens_of(src)
    decls = []
    scopes = [[]]             # each scope: list of declaration indexes
    pending = []              # (decl index, line, bracket depth) locals that become visible after their statement
    brackets = []
    funcs = []                # stack of (scope depth, decl index or None)
    blockstack = []           # what each open block is: "function", "do", "then", "repeat", "for", "while"
    n = len(toks)
    i = 0

    def visible(name):
        for sc in reversed(scopes):
            for d in reversed(sc):
                if decls[d].name == name:
                    return d

        return None

    def declare(name, kind, ti, scope=None):
        d = Decl(name, kind, toks[ti][2], ti, funcs[-1][1] if funcs else None)
        decls.append(d)
        (scopes[-1] if scope is None else scope).append(len(decls) - 1)
        return len(decls) - 1

    def flush(ti):
        # locals become visible once their statement has ended: a later line, a ";", or the next statement's keyword
        keep = []
        k, v = toks[ti][0], toks[ti][1]
        starts = (k == "op" and v == ";") or (k == "name" and v in ("if", "for", "while", "local", "return", "repeat", "break", "do"))

        for d, li, depth, sc, blocks in pending:
            if (toks[ti][2] > li or starts) and len(brackets) <= depth and len(blockstack) <= blocks:
                sc.append(d)
            else:
                keep.append((d, li, depth, sc, blocks))

        pending[:] = keep

    def close_scope(ti):
        sc = scopes.pop()

        for d in sc:
            decls[d].scope_end = ti

    while i < n:
        k, v, li, col = toks[i]
        flush(i)
        prev = toks[i - 1] if i else None

        if k == "op":
            if v in "({[":
                brackets.append(v)
            elif v in ")}]" and brackets:
                brackets.pop()

            i += 1
            continue

        if k != "name":
            i += 1
            continue

        if v == "local" and i + 1 < n and toks[i + 1][1] == "function":
            declare(toks[i + 2][1], "function", i + 2)
            i += 1
            continue

        if v == "local":
            j = i + 1
            names = []

            while j < n and toks[j][0] == "name" and toks[j][1] not in KEYWORDS:
                names.append(j)

                if j + 1 < n and toks[j + 1][1] == ",":
                    j += 2
                else:
                    break

            init = ""

            if j + 1 < n and toks[j + 1][1] == "=":
                src_line = lines[toks[j + 1][2]].text
                init = src_line[toks[j + 1][3] + 1:].strip()

            for t in names:
                d = Decl(toks[t][1], "local", li, t, funcs[-1][1] if funcs else None)
                d.init = init
                decls.append(d)
                pending.append((len(decls) - 1, li, len(brackets), scopes[-1], len(blockstack)))

            i = (names[-1] + 1) if names else i + 1
            continue

        if v == "function":
            # function name (if any), then parameters in a new scope
            fname = None
            j = i + 1

            if j < n and toks[j][0] == "name":
                while j < n and (toks[j][0] == "name" or toks[j][1] in (".", ":")):
                    j += 1

            for d in range(len(decls) - 1, -1, -1):
                if decls[d].tok == i + 1 and decls[d].kind == "function":
                    fname = d
                    break

            # "function a.b(" : a is a reference
            if toks[i + 1][0] == "name" and toks[i + 1][1] not in KEYWORDS and fname is None:
                ref = visible(toks[i + 1][1])

                if ref is not None:
                    decls[ref].uses.append(i + 1)

            while j < n and toks[j][1] != "(":
                j += 1

            scopes.append([])
            funcs.append((len(scopes), fname))
            blockstack.append("function")
            j += 1

            while j < n and toks[j][1] != ")":
                if toks[j][0] == "name" and toks[j][1] not in KEYWORDS:
                    declare(toks[j][1], "param", j)

                j += 1

            i = j + 1
            continue

        if v == "for":
            j = i + 1
            names = []

            while j < n and toks[j][1] not in ("=", "in"):
                if toks[j][0] == "name":
                    names.append(j)

                j += 1

            # the loop variables live in the body, which starts at the matching "do"
            depth = 0
            m = j

            while m < n:
                if toks[m][1] in ("(", "{", "["):
                    depth += 1
                elif toks[m][1] in (")", "}", "]"):
                    depth -= 1
                elif toks[m][1] == "do" and depth == 0:
                    break

                m += 1

            src_line = lines[toks[j][2]].text
            init = src_line[toks[j][3] + len(toks[j][1]):].split(" do")[0].strip()
            # process the iterator expression first (it can't see the loop variables)
            k2 = j

            while k2 < m:
                kk, vv, _, _ = toks[k2]

                if kk == "name" and vv not in KEYWORDS:
                    pv = toks[k2 - 1]

                    if not (pv[0] == "op" and pv[1] in (".", ":")):
                        ref = visible(vv)

                        if ref is not None:
                            decls[ref].uses.append(k2)
                            nx = toks[k2 + 1] if k2 + 1 < n else None

                            if nx and nx[1] in (".", ":") and k2 + 2 < n:
                                decls[ref].fields.add(toks[k2 + 2][1])

                elif kk == "op" and vv in "({[":
                    brackets.append(vv)
                elif kk == "op" and vv in ")}]" and brackets:
                    brackets.pop()

                k2 += 1

            scopes.append([])
            blockstack.append("for")

            for t in names:
                d = declare(toks[t][1], "for", t)
                decls[d].init = init

            i = m + 1
            continue

        if v in ("do", "then", "repeat"):
            scopes.append([])
            blockstack.append(v)
            i += 1
            continue

        if v in ("elseif", "else"):
            close_scope(i)

            if v == "else":
                scopes.append([])
            else:
                blockstack.pop()

            i += 1
            continue

        if v == "end":
            close_scope(i)
            kind = blockstack.pop() if blockstack else None

            if kind == "function":
                funcs.pop()

            i += 1
            continue

        if v == "until":
            # the condition still sees the loop body's locals: close the scope at the end of the line
            blockstack.pop()
            j = i + 1

            while j < n and toks[j][2] == li:
                kk, vv, _, _ = toks[j]

                if kk == "name" and vv not in KEYWORDS and toks[j - 1][1] not in (".", ":"):
                    ref = visible(vv)

                    if ref is not None:
                        decls[ref].uses.append(j)

                j += 1

            close_scope(j - 1)
            i = j
            continue

        if v in KEYWORDS:
            i += 1
            continue

        # a name: field access, table key, or a reference
        if prev and prev[0] == "op" and prev[1] in (".", ":"):
            i += 1
            continue

        nxt = toks[i + 1] if i + 1 < n else None

        if brackets and brackets[-1] == "{" and nxt and nxt[1] == "=" and prev and prev[1] in ("{", ",", ";"):
            i += 1
            continue

        ref = visible(v)

        if ref is not None:
            decls[ref].uses.append(i)

            if nxt and nxt[1] in (".", ":") and i + 2 < n:
                decls[ref].fields.add(toks[i + 2][1])

        i += 1

    while scopes:
        close_scope(n)

    return lines, toks, decls


def names_in_range(toks, a, b):
    """Every plain name used between two token indexes (to check a new name won't collide)."""
    out = set()

    for t in range(a, min(b, len(toks))):
        k, v = toks[t][0], toks[t][1]

        if k == "name" and not (t and toks[t - 1][0] == "op" and toks[t - 1][1] in (".", ":")):
            out.add(v)

    return out


def rename(src, plan):
    """plan: {(line, old name): new name} for declarations. Returns the new source and what was renamed."""
    lines, toks, decls = analyse(src)
    text = src.split("\n")
    edits = []
    done = []

    for d in decls:
        new = plan.get((d.line + 1, d.name))

        if not new or new == d.name:
            continue

        # never collide with anything already named so within the variable's reach
        used = names_in_range(toks, d.tok, d.scope_end if d.scope_end is not None else len(toks))

        if new in used or new in KEYWORDS:
            done.append((d.line + 1, d.name, new, "SKIPPED: name already used here"))
            continue

        for t in [d.tok] + d.uses:
            edits.append((toks[t][2], toks[t][3], d.name, new))

        done.append((d.line + 1, d.name, new, "%d uses" % len(d.uses)))

    # apply right to left so columns stay valid
    for li, col, old, new in sorted(edits, key=lambda e: (e[0], e[1]), reverse=True):
        s = text[li]
        assert s[col:col + len(old)] == old, (li, col, old, s)
        text[li] = s[:col] + new + s[col + len(old):]

    return "\n".join(text), done


if __name__ == "__main__":
    src = open(sys.argv[1], encoding="utf-8").read()
    lines, toks, decls = analyse(src)

    for d in decls:
        print("%5d %-8s %-14s uses=%-3d fields=%s init=%s" % (d.line + 1, d.kind, d.name, len(d.uses), ",".join(sorted(d.fields))[:60], d.init[:70]))
