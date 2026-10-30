"""Heuristic undefined-global scanner for the Windower -> Ashita v4 GearInfo port.

Not a parser: it collects the names a file (or file set) can resolve and reports bare
identifier *uses* that are not in that set, so it can over- or under-report on unusual
formatting. Treat every hit as a question, not an error.

What it treats as defined:
  * anything in the Lua 5.1/5.2 plus Ashita v4 globals whitelist
  * `local x`, `local function x`, `function a.b:c(x, y)` names and parameters
  * `for x in`, `for x =`, `repeat ... until` variables, `function (x)` parameters
  * every name assigned as a table field somewhere in the file set (`t.x =`, `x.y =`)
  * require'd module names and any name appearing inside a `function(...)` parameter list

Usage: python tools/undefscan.py FILE [FILE...]
"""
import re
import sys

GLOBALS = set('''
_G assert bit debug dofile error getfenv getmetatable ipairs load loadfile loadstring next pairs pcall
print rawequal rawget rawlen rawset require select setfenv setmetatable tonumber tostring type
unpack assert xpcall coroutine io math os string table utf8 package _VERSION
'''.split())

# Names gearinfo.lua injects into lib/include.lua's shared environment for the logic files.
ENV_GLOBALS = set('''
_addon game res Extdata chat chars config files settings sections defaults imageColors ImageBlock
DW_Gear Unity_rank Martial_Arts_Gear Set_bonus_by_Set_ID Set_bonus_by_item_id Blu_spells
Gifts Cor_Rolls Bard_Songs Geo_Spells
'''.split())

# Ashita v4 host globals, addon object fields and the shims this port installs.
ASHITA_GLOBALS = set('''
AshitaCore addon ashita imgini FontObject GetEntity GetPlayerEntity GetPartyEntity GetGuildleEffect
GetContainerItem windower res T S P V L FFI_EXT struct
FontDrawFlags FontCreateFlags FontBorderFlags FrameAnchor RECT SIZE ImGuiCond
'''.split())

DECL_PATTERNS = [
    re.compile(r'\blocal\s+function\s+([A-Za-z_]\w*)'),
    re.compile(r'\blocal\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)'),
    re.compile(r'\bfunction\s+([A-Za-z_]\w*)'),
    re.compile(r'\bfor\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s+in\s'),
    re.compile(r'\bfor\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*='),
    re.compile(r'\bfor\s*\(([^)]*)\)\s*(?:do|$)'),
    re.compile(r'\bwhile\s+([A-Za-z_]\w*)'),
]

PARAM_SPLIT = re.compile(r'\bfunction\s+[A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)*\s*\(([^)]*)\)'
                         r'|\bfunction\s*\(([^)]*)\)')
FIELD_ASSIGN = re.compile(r'(?:^|[^\w.\'"])([A-Za-z_]\w*)\s*(?:\.\s*[A-Za-z_]\w*)*\s*=\s*[^=]')
IDENT_USE = re.compile(r'(?<![.\w:])([A-Za-z_]\w*)')
LUA_TOKENS = set('''
and break do else elseif end false for function goto if in local nil not or repeat return then
true until while
'''.split())


def strip_noise(src):
    """Blank out comments and string literals so identifiers inside them are ignored."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == '-' and src[i + 1:i + 2] == '-':
            if src[i + 2:i + 3] == '[' and re.match(r'\[(=*)\[', src[i + 2:]):
                m = re.match(r'\[(=*)\[', src[i + 2:])
                close = ']' + m.group(1) + ']'
                idx = src.find(close, i + 2 + m.end())
                idx = n if idx == -1 else idx + len(close)
                out.append(' ' * (idx - i))
                i = idx
                continue
            nl = src.find('\n', i)
            nl = n if nl == -1 else nl
            out.append(' ' * (nl - i))
            i = nl
            continue
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == '\\' else 1
            j = min(j + 1, n)
            out.append(' ' * (j - i))
            i = j
            continue
        if c == '[' and re.match(r'\[(=*)\[', src[i:]):
            m = re.match(r'\[(=*)\[', src[i:])
            close = ']' + m.group(1) + ']'
            idx = src.find(close, i + m.end())
            idx = n if idx == -1 else idx + len(close)
            out.append(' ' * (idx - i))
            i = idx
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def collect(src):
    defined = set()
    for pattern in DECL_PATTERNS:
        for match in pattern.finditer(src):
            for name in re.split(r'\s*,\s*', match.group(1).strip()):
                if re.fullmatch(r'[A-Za-z_]\w*', name):
                    defined.add(name)
    for match in PARAM_SPLIT.finditer(src):
        for name in re.split(r'\s*,\s*', (match.group(1) or match.group(2) or '').strip()):
            name = name.strip()
            if re.fullmatch(r'[A-Za-z_]\w*', name):
                defined.add(name)
    for match in FIELD_ASSIGN.finditer(src):
        defined.add(match.group(1))
    return defined


def uses(src):
    found = {}
    for lineno, text in enumerate(src.split('\n'), 1):
        for match in IDENT_USE.finditer(text):
            name = match.group(1)
            if name in LUA_TOKENS:
                continue
            found.setdefault(name, []).append(lineno)
    return found


def main(argv):
    sources = []
    for path in argv:
        with open(path, 'r', encoding='utf-8', errors='replace') as handle:
            sources.append((path, strip_noise(handle.read())))

    # Field names and locals are pooled across the whole file set: the port splits one addon
    # namespace over several modules and a field assigned in one is legitimately read in another.
    pool = set(GLOBALS) | set(ASHITA_GLOBALS) | set(ENV_GLOBALS)
    for _, src in sources:
        pool |= collect(src)

    reported = 0
    for path, src in sources:
        for name, lines in sorted(uses(src).items()):
            if name in pool:
                continue
            reported += 1
            print('%s: unresolved %r at line(s) %s'
                  % (path.replace('\\', '/').split('/')[-1], name,
                     ', '.join(str(x) for x in lines[:6])))
    if reported == 0:
        print('OK: no unresolved identifiers in %d file(s)' % len(argv))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
