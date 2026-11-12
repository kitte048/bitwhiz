#!/usr/bin/env python3
"""manual_check.py -- the manual's trace tags still point at real code
(doc/design/manual.md, "Keeping it true to the code"). From the bitwhiz
folder (make test runs it):

    python3 tests/manual_check.py

Every \\trace{file}{routines}{tests} in doc/manual/ names a source file
under src/, the routines that compute the equation above it, and the tests
that check them (comma-separated). This checks that the file exists, that
each routine is still a subroutine or function in it, and that each test is
still a file under tests/ (test_x is tests/test_x.f95; anything else by its
own name). It catches a renamed or deleted routine or test, not a wrong
equation: the equations are checked by doc/manual/checks/ and by the tests
the tags name.

Exit status 0 if every tag resolves. Python 3, standard library only.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MANUAL = os.path.join(ROOT, 'doc', 'manual')
TRACE = re.compile(r'\\trace\{([^{}]*)\}\{([^{}]*)\}\{([^{}]*)\}')

def tex_files():
    for d, _, fs in os.walk(MANUAL):
        for f in sorted(fs):
            if f.endswith('.tex'):
                yield os.path.join(d, f)

def test_paths():
    found = {}
    for d, _, fs in os.walk(os.path.join(ROOT, 'tests')):
        for f in fs:
            found.setdefault(f, os.path.join(d, f))
    return found

def main():
    if not os.path.isdir(MANUAL):
        print('manual_check.py: no doc/manual here, nothing to check')
        return 0
    tests = test_paths()
    bad, ntag, nroutine, ntest = [], 0, set(), set()
    for tf in tex_files():
        rel = os.path.relpath(tf, ROOT)
        lines = open(tf, encoding='utf-8').read().split('\n')
        for i, line in enumerate(lines, 1):
            if line.lstrip().startswith('%') or '\\newcommand' in line:
                continue
            for src, routines, tnames in TRACE.findall(line):
                ntag += 1
                where = f'{rel}:{i}'
                path = os.path.join(ROOT, 'src', src.strip())
                if not os.path.isfile(path):
                    bad.append(f'{where}: no source file src/{src.strip()}')
                    continue
                code = open(path, encoding='utf-8', errors='replace').read()
                for r in [x.strip() for x in routines.split(',') if x.strip()]:
                    nroutine.add((src, r))
                    pat = re.compile(r'(?im)^\s*(?:[a-z0-9_(),= ]*\s)?'
                                     r'(?:subroutine|function)\s+'
                                     + re.escape(r) + r'\b')
                    if not pat.search(code):
                        bad.append(f'{where}: {r} is not a subroutine or '
                                   f'function in src/{src.strip()}')
                for t in [x.strip() for x in tnames.split(',') if x.strip()]:
                    ntest.add(t)
                    if t not in tests and t + '.f95' not in tests:
                        bad.append(f'{where}: no test {t} under tests/')
    if ntag == 0:
        bad.append('no \\trace tags found in doc/manual/')
    for b in bad:
        print('   FAIL  ' + b)
    print(f'manual_check.py: {ntag} trace tags, {len(nroutine)} routines, '
          f'{len(ntest)} tests: ' + ('all found' if not bad else
                                     f'{len(bad)} not found'))
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
