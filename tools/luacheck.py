"""Minimal Lua 5.1 lexical/block checker used while porting GearInfo to Ashita v4.

Catches unterminated strings/comments, unbalanced () {} and if/then/do/function/end
mismatches. Same algorithm as tools/luacheck.mjs, kept as the runnable copy because
this machine has no node on PATH.

Usage: python tools/luacheck.py FILE [FILE...]
"""
import re
import sys

KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
            'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then',
            'true', 'until', 'while'}

BLOCK_ENDERS = {'end': {'then', 'do', 'function'}, 'until': {'repeat'}}
LONG_OPEN = re.compile(r'\[(=*)\[')
NAME_START = re.compile(r'[A-Za-z_]')
NAME_CHAR = re.compile(r'[A-Za-z0-9_]')
DIGIT = re.compile(r'[0-9]')
HEXDIGIT = re.compile(r'[0-9a-fA-FxX.]')


def check(src, name='<string>'):
    errors = []
    stack = []
    i = 0
    line = 1
    n = len(src)

    def push(kind):
        stack.append((kind, line))

    def pop(kind):
        if not stack:
            errors.append('%s:%d: %r without matching opener' % (name, line, kind))
            return
        top_kind, top_line = stack[-1]
        if kind in ('end', 'until'):
            if top_kind not in BLOCK_ENDERS[kind]:
                errors.append('%s:%d: %r does not match %r opened at line %d'
                              % (name, line, kind, top_kind, top_line))
            stack.pop()
            return
        if top_kind != kind:
            errors.append('%s:%d: %r does not match %r opened at line %d'
                          % (name, line, kind, top_kind, top_line))
        stack.pop()

    while i < n:
        c = src[i]

        if c == '\n':
            line += 1
            i += 1
            continue
        if c in ' \t\r':
            i += 1
            continue

        # comments
        if c == '-' and src[i + 1:i + 2] == '-':
            if src[i + 2:i + 3] == '[':
                m = LONG_OPEN.match(src, i + 2)
                if m:
                    close = ']' + (m.group(1) or '') + ']'
                    start_line = line
                    i += 2 + (m.end() - m.start())
                    idx = src.find(close, i)
                    if idx == -1:
                        errors.append('%s:%d: unterminated long comment' % (name, start_line))
                        break
                    line += src.count('\n', i, idx)
                    i = idx + len(close)
                    continue
            nl = src.find('\n', i)
            i = n if nl == -1 else nl
            continue

        # strings
        if c in '"\'':
            quote = c
            start_line = line
            i += 1
            closed = False
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == '\n':
                    break
                if src[i] == quote:
                    i += 1
                    closed = True
                    break
                i += 1
            if not closed:
                errors.append('%s:%d: unterminated string literal' % (name, start_line))
            continue

        if c == '[':
            m = LONG_OPEN.match(src, i)
            if m:
                close = ']' + (m.group(1) or '') + ']'
                start_line = line
                i += m.end() - m.start()
                idx = src.find(close, i)
                if idx == -1:
                    errors.append('%s:%d: unterminated long string' % (name, start_line))
                    break
                line += src.count('\n', i, idx)
                i = idx + len(close)
                continue

        # numbers
        if DIGIT.match(c) or (c == '.' and DIGIT.match(src[i + 1:i + 2] or '')):
            while i < n and HEXDIGIT.match(src[i]):
                i += 1
            continue

        # names / keywords
        if NAME_START.match(c):
            j = i
            while j < n and NAME_CHAR.match(src[j]):
                j += 1
            word = src[i:j]
            i = j
            if word not in KEYWORDS:
                continue
            if word == 'if':
                continue
            if word == 'then':
                push('then')
                continue
            if word == 'elseif':
                pop('then')
                continue
            if word == 'else':
                continue
            if word == 'end':
                pop('end')
                continue
            if word == 'do':
                push('do')
                continue
            if word == 'function':
                push('function')
                continue
            if word == 'repeat':
                push('repeat')
                continue
            if word == 'until':
                pop('until')
                continue
            continue

        # punctuation
        if c == '(':
            push('paren')
            i += 1
            continue
        if c == ')':
            pop('paren')
            i += 1
            continue
        if c == '{':
            push('brace')
            i += 1
            continue
        if c == '}':
            pop('brace')
            i += 1
            continue
        if c == '~' and src[i + 1:i + 2] == '=':
            i += 2
            continue
        i += 1

    for kind, open_line in stack:
        errors.append('%s:%d: block %r never closed' % (name, open_line, kind))
    return errors


def main(argv):
    bad = 0
    for path in argv:
        with open(path, 'r', encoding='utf-8', errors='replace') as handle:
            src = handle.read()
        errs = check(src, path.replace('\\', '/').split('/')[-1])
        if errs:
            bad += 1
            print('\n'.join(errs))
    if bad == 0:
        print('OK: %d file(s) lexically balanced' % len(argv))
    else:
        print('%d file(s) with issues' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
