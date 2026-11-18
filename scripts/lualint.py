"""Small Lua 5.1/LuaJIT parser + scope linter (no deps), used to check Aire.

Usage:
    python scripts/lualint.py $(find . -name "*.lua" -not -path "./koreader/*")
    python scripts/lualint.py -u file.lua        # also unused / redeclared locals
    python scripts/lualint.py -t <files>         # top 10 functions by upvalue count


Reports: syntax errors, undefined global reads, global writes,
'...' outside vararg functions, '_' called while shadowed by a non-gettext local,
unused locals (with -u), duplicate locals in same scope (with -u)."""
import re, sys

KEYWORDS = set("""and break do else elseif end false for function goto if in local nil not or
repeat return then true until while""".split())

KNOWN_GLOBALS = set("""_G _VERSION assert collectgarbage dofile error getfenv getmetatable ipairs load
loadfile loadstring module next pairs pcall print rawequal rawget rawlen rawset require select setfenv
setmetatable tonumber tostring type unpack xpcall coroutine debug io math os package string table
bit jit ffi arg G_reader_settings G_defaults DLANDSCAPE_CLOCKWISE_ROTATION ANDROID_FONT_DIR
newproxy gcinfo""".split())

class LuaSyntaxError(Exception):
    pass

TOKEN_RE = re.compile(r"""
 (?P<ws>[ \t\r\f\v]+) |
 (?P<nl>\n) |
 (?P<longcomment>--\[(?P<lceq>=*)\[) |
 (?P<comment>--[^\n]*) |
 (?P<longstr>\[(?P<lseq>=*)\[) |
 (?P<num>0[xX][0-9a-fA-F]*(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?\d+)?(?:ULL|LL|ull|ll|i|I)?|
        (?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?(?:ULL|LL|ull|ll|i|I)?) |
 (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
 (?P<str>["']) |
 (?P<op>\.\.\.|\.\.|==|~=|<=|>=|::|[-+*/%^\#<>=(){}\[\];:,.])
""", re.X)

def tokenize(src):
    toks = []
    i, n, line = 0, len(src), 1
    if src.startswith("#!"):
        j = src.find("\n"); i = n if j < 0 else j
    while i < n:
        m = TOKEN_RE.match(src, i)
        if not m:
            raise LuaSyntaxError("línea %d: carácter inesperado %r" % (line, src[i]))
        k = m.lastgroup
        if k == "lceq": k = "longcomment"
        if k == "lseq": k = "longstr"
        if m.group("longcomment"):
            close = "]" + m.group("lceq") + "]"
            j = src.find(close, m.end())
            if j < 0: raise LuaSyntaxError("línea %d: comentario largo sin cerrar" % line)
            line += src[i:j].count("\n"); i = j + len(close); continue
        if m.group("longstr"):
            close = "]" + m.group("lseq") + "]"
            j = src.find(close, m.end())
            if j < 0: raise LuaSyntaxError("línea %d: cadena larga sin cerrar" % line)
            toks.append(("string", None, line))
            line += src[i:j].count("\n"); i = j + len(close); continue
        if m.group("ws") or m.group("comment"):
            i = m.end(); continue
        if m.group("nl"):
            line += 1; i = m.end(); continue
        if m.group("str"):
            q = m.group("str"); j = i + 1
            while True:
                if j >= n: raise LuaSyntaxError("línea %d: cadena sin cerrar" % line)
                c = src[j]
                if c == "\\":
                    if j + 1 < n and src[j+1] == "\n": line += 1
                    if src.startswith("z", j+1):
                        j += 2
                        while j < n and src[j] in " \t\r\n":
                            if src[j] == "\n": line += 1
                            j += 1
                        continue
                    j += 2; continue
                if c == "\n": raise LuaSyntaxError("línea %d: cadena sin cerrar" % line)
                if c == q: break
                j += 1
            toks.append(("string", None, line)); i = j + 1; continue
        if m.group("num"):
            toks.append(("number", None, line)); i = m.end(); continue
        if m.group("name"):
            v = m.group("name")
            toks.append(("kw" if v in KEYWORDS else "name", v, line)); i = m.end(); continue
        toks.append(("op", m.group("op"), line)); i = m.end()
    toks.append(("eof", None, line))
    return toks

class Binding:
    __slots__ = ("name", "line", "used", "kind", "func")
    def __init__(self, name, line, kind, func):
        self.name, self.line, self.used, self.kind, self.func = name, line, False, kind, func

UPV_REPORT = []

class Linter:
    def __init__(self, toks, fname):
        self.t, self.p, self.fname = toks, 0, fname
        self.scopes = []
        self.funcs = []  # stack of {'vararg': bool}
        self.issues = []
        self.all_bindings = []

    # --- token helpers
    def peek(self, o=0): return self.t[self.p + o]
    def nxt(self):
        tok = self.t[self.p]; self.p += 1; return tok
    def check(self, kind, val=None):
        tk = self.t[self.p]
        if val is None: return tk[0] == kind
        return tk[0] == kind and tk[1] == val
    def accept(self, kind, val=None):
        if self.check(kind, val): return self.nxt()
        return None
    def expect(self, kind, val=None, opener=None):
        if self.check(kind, val): return self.nxt()
        tk = self.peek()
        msg = "línea %d: se esperaba '%s' cerca de '%s'" % (tk[2], val or kind, tk[1] or tk[0])
        if opener: msg += " (para cerrar '%s' de la línea %d)" % opener
        raise LuaSyntaxError(msg)
    def isop(self, v): return self.check("op", v)
    def iskw(self, v): return self.check("kw", v)

    # --- scopes
    def push(self): self.scopes.append({})
    def pop(self):
        sc = self.scopes.pop()
    def declare(self, name, line, kind="local"):
        sc = self.scopes[-1]
        if name in sc and name != "_" and kind == "local" and sc[name].kind == "local":
            self.issues.append(("info", line, "local '%s' redeclarado en el mismo ámbito (antes l.%d)" % (name, sc[name].line)))
        b = Binding(name, line, kind, len(self.funcs))
        sc[name] = b
        self.all_bindings.append(b)
        return b
    def resolve(self, name):
        for sc in reversed(self.scopes):
            if name in sc: return sc[name]
        return None
    def use(self, name, line, write=False, call=False):
        b = self.resolve(name)
        if b is None:
            if write:
                self.issues.append(("warn", line, "asignación a global '%s'" % name))
            elif name not in KNOWN_GLOBALS:
                self.issues.append(("error", line, "global no definida '%s'" % name))
            return
        for i in range(b.func, len(self.funcs)):
            self.funcs[i].setdefault("upvals", set()).add(id(b))
        if not write: b.used = True
        else: b.used = b.used or False
        if name == "_" and call and b.kind in ("for", "multi"):
            self.issues.append(("error", line, "'_' llamado como gettext pero está sombreado por variable de bucle/multi (l.%d)" % b.line))

    # --- grammar
    def chunk(self):
        self.funcs.append({"vararg": True})
        self.push()
        self.block()
        self.expect("eof")
        self.pop()

    def block_end(self):
        tk = self.peek()
        return tk[0] == "eof" or (tk[0] == "kw" and tk[1] in ("end", "else", "elseif", "until"))

    def block(self):
        while not self.block_end():
            if self.iskw("return"):
                self.nxt()
                if not self.block_end() and not self.isop(";"):
                    self.explist()
                self.accept("op", ";")
                if not self.block_end():
                    tk = self.peek()
                    raise LuaSyntaxError("línea %d: código después de 'return'" % tk[2])
                return
            self.statement()

    def statement(self):
        tk = self.peek()
        line = tk[2]
        if self.accept("op", ";"): return
        if tk[0] == "kw":
            v = tk[1]
            if v == "if":
                self.nxt(); self.expr(); self.expect("kw", "then", ("if", line))
                self.push(); self.block(); self.pop()
                while self.iskw("elseif"):
                    self.nxt(); self.expr(); self.expect("kw", "then")
                    self.push(); self.block(); self.pop()
                if self.accept("kw", "else"):
                    self.push(); self.block(); self.pop()
                self.expect("kw", "end", ("if", line)); return
            if v == "while":
                self.nxt(); self.expr(); self.expect("kw", "do")
                self.push(); self.block(); self.pop()
                self.expect("kw", "end", ("while", line)); return
            if v == "do":
                self.nxt(); self.push(); self.block(); self.pop()
                self.expect("kw", "end", ("do", line)); return
            if v == "for":
                self.nxt()
                n1 = self.expect("name")
                if self.accept("op", "="):
                    self.expr(); self.expect("op", ","); self.expr()
                    if self.accept("op", ","): self.expr()
                    self.expect("kw", "do")
                    self.push(); self.declare(n1[1], n1[2], "for")
                    self.push(); self.block(); self.pop(); self.pop()
                else:
                    names = [n1]
                    while self.accept("op", ","): names.append(self.expect("name"))
                    self.expect("kw", "in"); self.explist(); self.expect("kw", "do")
                    self.push()
                    for nm in names: self.declare(nm[1], nm[2], "for")
                    self.push(); self.block(); self.pop(); self.pop()
                self.expect("kw", "end", ("for", line)); return
            if v == "repeat":
                self.nxt(); self.push(); self.block()
                self.expect("kw", "until", ("repeat", line)); self.expr(); self.pop(); return
            if v == "function":
                self.nxt()
                n = self.expect("name")
                is_method = False
                path = [n]
                while self.isop(".") or self.isop(":"):
                    sep = self.nxt()[1]
                    path.append(self.expect("name"))
                    if sep == ":": is_method = True; break
                if len(path) == 1: self.use(n[1], n[2], write=True)
                else: self.use(n[1], n[2])
                self.funcbody(line, is_method, name=".".join(p[1] for p in path)); return
            if v == "local":
                self.nxt()
                if self.accept("kw", "function"):
                    n = self.expect("name")
                    self.declare(n[1], n[2])
                    self.funcbody(line, False, name=n[1]); return
                names = [self.expect("name")]
                while self.accept("op", ","): names.append(self.expect("name"))
                if self.accept("op", "="): self.explist()
                kind = "multi" if len(names) > 1 else "local"
                for nm in names: self.declare(nm[1], nm[2], kind)
                return
            if v == "return":
                raise LuaSyntaxError("línea %d: return fuera de lugar" % line)
            if v == "break":
                self.nxt(); return
            if v == "goto":
                self.nxt(); self.expect("name"); return
            raise LuaSyntaxError("línea %d: palabra inesperada '%s'" % (line, v))
        if self.isop("::"):
            self.nxt(); self.expect("name"); self.expect("op", "::"); return
        # exprstat
        kind = self.suffixedexp()
        if self.isop("=") or self.isop(","):
            targets = [kind]
            while self.accept("op", ","):
                targets.append(self.suffixedexp())
            self.expect("op", "=")
            self.explist()
            for tgt in targets:
                if tgt[0] == "call":
                    raise LuaSyntaxError("línea %d: no se puede asignar a una llamada" % line)
                if tgt[0] == "name":
                    self.use(tgt[1], tgt[2], write=True)
        else:
            if kind[0] != "call":
                raise LuaSyntaxError("línea %d: sentencia incompleta (¿falta '=' o '('?)" % line)

    def funcbody(self, line, is_method, name=None):
        self.expect("op", "(")
        self.funcs.append({"vararg": False, "name": name, "upvals": set(), "line": line})
        self.push()
        if is_method: self.declare("self", line, "param").used = True
        if not self.isop(")"):
            while True:
                if self.accept("op", "..."):
                    self.funcs[-1]["vararg"] = True; break
                n = self.expect("name"); self.declare(n[1], n[2], "param")
                if not self.accept("op", ","): break
        self.expect("op", ")")
        self.block()
        self.expect("kw", "end", ("function", line))
        self.pop()
        f = self.funcs.pop()
        UPV_REPORT.append((len(f["upvals"]), line, self.fname))
        if len(f["upvals"]) > 60:
            self.issues.append(("error", line, "la función de la línea %d usa %d upvalues (LuaJIT admite 60 como máximo)" % (line, len(f["upvals"]))))
        elif len(f["upvals"]) > 54:
            self.issues.append(("warn", line, "la función de la línea %d usa %d upvalues (límite 60)" % (line, len(f["upvals"]))))

    def explist(self):
        self.expr()
        while self.accept("op", ","): self.expr()

    def primaryexp(self):
        tk = self.peek()
        if tk[0] == "name":
            self.nxt()
            return ("name", tk[1], tk[2])
        if self.accept("op", "("):
            self.expr(); self.expect("op", ")", ("(", tk[2]))
            return ("paren", None, tk[2])
        raise LuaSyntaxError("línea %d: símbolo inesperado '%s'" % (tk[2], tk[1] or tk[0]))

    def suffixedexp(self):
        prim = self.primaryexp()
        cur = prim
        first = True
        while True:
            tk = self.peek()
            if tk[0] == "op" and tk[1] == ".":
                if first and prim[0] == "name": self.use(prim[1], prim[2]); first = False
                self.nxt(); self.expect("name"); cur = ("index", None, tk[2])
            elif tk[0] == "op" and tk[1] == "[":
                if first and prim[0] == "name": self.use(prim[1], prim[2]); first = False
                self.nxt(); self.expr(); self.expect("op", "]"); cur = ("index", None, tk[2])
            elif tk[0] == "op" and tk[1] == ":":
                if first and prim[0] == "name": self.use(prim[1], prim[2]); first = False
                self.nxt(); self.expect("name"); self.callargs(); cur = ("call", None, tk[2])
            elif (tk[0] == "op" and tk[1] in ("(", "{")) or tk[0] == "string":
                if tk[0] == "op" and tk[1] == "(" and tk[2] != self.t[self.p-1][2]:
                    self.issues.append(("warn", tk[2], "llamada ambigua: '(' en línea nueva"))
                if first and prim[0] == "name": self.use(prim[1], prim[2], call=True); first = False
                self.callargs(); cur = ("call", None, tk[2])
            else:
                break
        if first and prim[0] == "name":
            # bare name: caller decides (read or write)
            return prim
        return cur

    def callargs(self):
        tk = self.peek()
        if tk[0] == "string": self.nxt(); return
        if self.isop("{"): self.table(); return
        self.expect("op", "(")
        if not self.isop(")"): self.explist()
        self.expect("op", ")", ("(", tk[2]))

    def table(self):
        open_tk = self.expect("op", "{")
        while not self.isop("}"):
            if self.isop("["):
                self.nxt(); self.expr(); self.expect("op", "]"); self.expect("op", "="); self.expr()
            elif self.check("name") and self.peek(1)[0] == "op" and self.peek(1)[1] == "=":
                self.nxt(); self.nxt(); self.expr()
            else:
                self.expr()
            if not (self.accept("op", ",") or self.accept("op", ";")): break
        self.expect("op", "}", ("{", open_tk[2]))

    BINPRI = {"or": (1, 1), "and": (2, 2), "<": (3, 3), ">": (3, 3), "<=": (3, 3), ">=": (3, 3),
              "~=": (3, 3), "==": (3, 3), "..": (5, 4), "+": (6, 6), "-": (6, 6), "*": (7, 7),
              "/": (7, 7), "%": (7, 7), "^": (10, 9)}
    UNARY = 8

    def simpleexp(self):
        tk = self.peek()
        if tk[0] in ("number", "string"): self.nxt(); return
        if tk[0] == "kw" and tk[1] in ("nil", "true", "false"): self.nxt(); return
        if tk[0] == "op" and tk[1] == "...":
            self.nxt()
            if not self.funcs[-1]["vararg"]:
                self.issues.append(("error", tk[2], "'...' usado fuera de una función con '...' (error de compilación en Lua)"))
            return
        if tk[0] == "op" and tk[1] == "{": self.table(); return
        if tk[0] == "kw" and tk[1] == "function":
            self.nxt(); self.funcbody(tk[2], False, name="<anon>"); return
        e = self.suffixedexp()
        if e[0] == "name": self.use(e[1], e[2])

    def expr(self, limit=0):
        tk = self.peek()
        if (tk[0] == "kw" and tk[1] == "not") or (tk[0] == "op" and tk[1] in ("-", "#")):
            self.nxt(); self.expr(self.UNARY)
        else:
            self.simpleexp()
        while True:
            tk = self.peek()
            op = tk[1] if tk[0] in ("op", "kw") else None
            if op not in self.BINPRI: break
            l, r = self.BINPRI[op]
            if l <= limit: break
            self.nxt(); self.expr(r)

def lint(path, unused=False):
    src = open(path, encoding="utf-8").read()
    try:
        L = Linter(tokenize(src), path)
        L.chunk()
    except LuaSyntaxError as e:
        return [("SYNTAX", 0, str(e))]
    out = list(L.issues)
    if unused:
        for b in L.all_bindings:
            if not b.used and not b.name.startswith("_") and b.kind in ("local", "multi") :
                out.append(("unused", b.line, "local '%s' no usado" % b.name))
    return sorted(out, key=lambda x: x[1])

if __name__ == "__main__":
    args = sys.argv[1:]
    unused = "-u" in args
    top = "-t" in args
    args = [a for a in args if a not in ("-u", "-t")]
    bad = 0
    for p in args:
        res = lint(p, unused)
        errs = [r for r in res if r[0] in ("SYNTAX", "error")]
        bad += bool(errs)
        print(("OK    " if not errs else "FALLO ") + p.replace("\\", "/").split("/")[-1])
        for lvl, ln, msg in res:
            print("   [%s] l.%d %s" % (lvl, ln, msg))
    if top:
        print("Funciones con más upvalues (LuaJIT admite 60):")
        for n, line, fname in sorted(UPV_REPORT, reverse=True)[:10]:
            print("  %3d  %s:%d" % (n, fname.replace("\\", "/"), line))
    sys.exit(1 if bad else 0)
