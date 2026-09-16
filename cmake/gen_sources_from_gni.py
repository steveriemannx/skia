#!/usr/bin/env python3
#
# Copyright 2026 The Skia Authors
#
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
"""Turn Skia's machine-generated *.gni source lists into a CMake file.

The files under gn/ and modules/*/ are generated from the Bazel build by
`make -C bazel generate_gni`, so they are the canonical, always-current
description of which sources belong to which part of Skia.  Rather than
transcribing them by hand (they change on every upstream roll) or globbing
directories (which would silently pick up test/tool/rust sources), the CMake
build runs this script at configure time and includes the result.

The grammar is deliberately narrow - every list is an assignment of a literal
string array, e.g.

    _src = get_path_info("../src", "abspath")
    skia_core_sources = [
      "$_src/core/RasterContext.cpp",
      ...
    ]

Anything outside that subset (conditionals, +=, computed entries, unknown
"$_variable" prefixes) aborts with a file:line diagnostic, so an upstream
change to the generator stops the build instead of quietly compiling the
wrong file set.

Usage:
    gen_sources_from_gni.py --root <skia root> --out <file.cmake> [--check]

Output: a CMake file with one "set(SKIA_GN_<list name> ...)" per list, holding
only compilable sources (.c/.cc/.cpp/.cxx/.m/.mm), as root-relative paths.
"""

import argparse
import os
import re
import sys

# Extensions we hand to the compiler. Everything else in the lists is a header,
# a .sksl/.rts/.compute shader module, or a Rust source for the optional Rust
# decoders - none of which CMake compiles.
COMPILABLE = ('.c', '.cc', '.cpp', '.cxx', '.m', '.mm')

# Files whose lists we consume. Excluded on purpose:
#   gn/shared_sources.gni  - uses import()/dict syntax
#   gn/skia.gni, ios.gni   - declare_args()/configs, not source lists
#   gn/{bench,gm,tests,fuzz,_sksl_tests,skills}.gni - test/tool sources
GN_FILES = [
    'gn/codec.gni',
    'gn/core.gni',
    'gn/effects.gni',
    'gn/effects_imagefilters.gni',
    'gn/gpu.gni',
    'gn/graphite.gni',
    'gn/opts.gni',
    'gn/pathops.gni',
    'gn/pdf.gni',
    'gn/ports.gni',
    'gn/sksl.gni',
    'gn/svg.gni',
    'gn/utils.gni',
    'gn/xml.gni',
    'gn/xps.gni',
]

ASSIGN_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\[(.*?)^\]\s*$', re.S | re.M)
DECL_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=', re.M)
PATHVAR_RE = re.compile(
    r'^(\w+)\s*=\s*get_path_info\("([^"]+)"\s*,\s*"abspath"\)\s*$', re.M)
STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')


class GniError(Exception):
    pass


def strip_comments(text):
    """Drop #-comments. Kept simple: Skia paths never contain '#'."""
    return re.sub(r'#[^\n]*', '', text)


def parse_path_vars(text, gni_rel_dir, relpath, out_errors):
    """Map $_name -> repo-relative directory, resolved from the .gni's own dir."""
    variables = {}
    for m in PATHVAR_RE.finditer(text):
        name, value = m.group(1), m.group(2)
        if '$' in value:
            out_errors.append('%s: computed get_path_info value %r' % (relpath, value))
            continue
        # get_path_info() takes a path relative to the file's directory; the build
        # passes an absolute path in as `source_absolute_path`, but "abspath" only
        # asks for the result to be absolute *for that input*, which is the Skia
        # root here.
        resolved = os.path.normpath(os.path.join(gni_rel_dir, value))
        if resolved.startswith('..'):
            out_errors.append('%s: path variable %s escapes the repo (%s)'
                              % (relpath, name, resolved))
            continue
        variables[name] = resolved.replace(os.sep, '/')
    return variables


def read_list_body(lines, i, rest):
    """Collect the text of the list assigned at lines[i]; None if it is not one."""
    if rest.startswith('['):
        body, i = rest[1:], i + 1
    else:
        # "name =" with the bracket on a following line.
        j = i + 1
        while j < len(lines) and not lines[j].strip():
            j += 1
        if j >= len(lines) or not lines[j].lstrip().startswith('['):
            return None, i + 1
        body, i = lines[j].lstrip()[1:], j + 1
    if ']' in body:  # single-line list
        return body.split(']')[0], i
    parts = []
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith(']'):
            i += 1
            break
        parts.append(lines[i])
        i += 1
    return body + '\n' + '\n'.join(parts), i


def parse_lists(text, variables, relpath, out_errors):
    """Return {list name: [root-relative source paths]} for one file.

    Line based rather than one big regex: some generated lists put the opening
    bracket on the line after "name =" and/or indent the closing bracket, and a
    sloppy ".*?" match would run past the end of one list and swallow the next.
    """
    lines = text.split('\n')
    lists = {}
    i = 0
    while i < len(lines):
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$', lines[i])
        if not m:
            i += 1
            continue
        name, rest = m.group(1), m.group(2).strip()
        line = i + 1
        body, i = read_list_body(lines, i, rest)
        if body is None:
            continue
        where = '%s:%d' % (relpath, line)

        if '$' in re.sub(r'\$_[A-Za-z_][A-Za-z0-9_]*/', '', body):
            out_errors.append('%s: list %s contains an unsupported "$" expression'
                              % (where, name))
            continue
        if re.search(r'"\s*\+|\+\s*"|\(|\bif\b|\bforeach\b', body):
            out_errors.append('%s: list %s uses concatenation/conditionals'
                              % (where, name))
            continue

        items = []
        for raw in STRING_RE.findall(body):
            expanded = re.sub(r'\$(_[A-Za-z_][A-Za-z0-9_]*)/',
                              lambda mm: variables.get(mm.group(1), mm.group(0)) + '/',
                              raw)
            if '$' in expanded:
                out_errors.append('%s: list %s has unresolved variable in %r'
                                  % (where, name, raw))
                continue
            items.append(os.path.normpath(expanded).replace(os.sep, '/'))
        lists[name] = items
    return lists


def collect(root, relpaths):
    """Parse every given .gni file; abort via GniError on anything unexpected."""
    errors = []
    lists = {}
    for relpath in relpaths:
        path = os.path.join(root, relpath)
        if not os.path.exists(path):
            errors.append('%s: missing' % relpath)
            continue
        text = strip_comments(open(path, encoding='utf-8').read())
        if re.search(r'^\s*\+=', text, re.M):
            errors.append('%s: uses "+=" (list mutation is unsupported)' % relpath)
        variables = parse_path_vars(text, os.path.dirname(relpath), relpath, errors)
        for name, items in parse_lists(text, variables, relpath, errors).items():
            if name in lists:
                errors.append('%s: list %s redefined (also in another .gni)' % (relpath, name))
            lists[name] = items
        # Any bare assignment we did not understand (dicts, strings) is fine as
        # long as it is not a list we needed; but flag unknown "$_" uses.
        for token in re.findall(r'\$_([A-Za-z_][A-Za-z0-9_]*)', text):
            if '_' + token not in variables:
                errors.append('%s: unknown path variable "$_%s"' % (relpath, token))
    if errors:
        raise GniError('\n'.join(sorted(set(errors))))
    return lists


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', required=True, help='path to the Skia checkout')
    parser.add_argument('--out', help='CMake file to write')
    parser.add_argument('--check', action='store_true',
                        help='print a summary and validate paths, but write nothing')
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    relpaths = list(GN_FILES)
    modules_dir = os.path.join(root, 'modules')
    if os.path.isdir(modules_dir):
        for entry in sorted(os.listdir(modules_dir)):
            gni = os.path.join('modules', entry, entry + '.gni')
            if os.path.exists(os.path.join(root, gni)):
                relpaths.append(gni)
            # some modules name their list file differently
            for other in sorted(os.listdir(os.path.join(modules_dir, entry))):
                if other.endswith('.gni') and other != entry + '.gni':
                    cand = os.path.join('modules', entry, other)
                    if cand not in relpaths and os.path.exists(os.path.join(root, cand)):
                        relpaths.append(cand)

    try:
        lists = collect(root, relpaths)
    except GniError as exc:
        sys.stderr.write('gen_sources_from_gni.py: cannot parse the .gni sources:\n%s\n'
                         % exc)
        return 2

    # Keep only compilable files, de-duplicating while preserving order, and
    # check that every path actually exists.
    missing = []
    out_lists = {}
    for name, items in lists.items():
        kept, seen = [], set()
        for item in items:
            if not item.endswith(COMPILABLE) or item in seen:
                continue
            seen.add(item)
            if not os.path.exists(os.path.join(root, item)):
                missing.append(item)
            kept.append(item)
        if kept:
            out_lists[name] = kept

    if missing:
        sys.stderr.write('gen_sources_from_gni.py: %d listed sources do not exist:\n%s\n'
                         % (len(missing), '\n'.join(sorted(missing)[:20])))
        return 2

    if args.check:
        total = 0
        for name in sorted(out_lists):
            print('%-46s %5d' % (name, len(out_lists[name])))
            total += len(out_lists[name])
        print('%-46s %5d' % ('TOTAL (with duplicates across lists)', total))
        return 0

    if not args.out:
        parser.error('--out is required unless --check is given')

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as out:
        out.write('# Generated by cmake/gen_sources_from_gni.py from the machine-generated\n'
                  '# gn/*.gni and modules/*/*.gni lists - DO NOT EDIT.\n'
                  '# Regenerate with: python3 cmake/gen_sources_from_gni.py --root . --out <file>\n\n')
        for name in sorted(out_lists):
            out.write('set(SKIA_GN_%s\n' % name)
            for item in out_lists[name]:
                out.write('    "%s"\n' % item)
            out.write(')\n\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
