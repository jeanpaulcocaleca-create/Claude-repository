#!/usr/bin/env python3
"""Canopy OS · GitHub Actions workflows: every ${{ … }} expression may use only the contexts GitHub allows at that place.

GitHub checks this when a workflow file is pushed, not here in CI, and the private backup repository's workflows live
under ops/backup/repositorio-respaldos/ where GitHub never parses them: a mistake shows up only when the owner uploads
them ("Unrecognized named-value: 'runner'" on 2026-10-13, a job-level env that used runner.temp). This check applies
GitHub's context-availability table (docs.github.com/en/actions/learn-github-actions/contexts#context-availability)
to each file given, and fails on the first place that uses a context GitHub does not allow there, or that has an
expression where none is allowed (uses:, id:, on:, permissions:).

Usage: tests/tools/workflow-contexts.py FILE...   (exit 1 with one line per problem)
"""
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit('workflow-contexts.py needs PyYAML (apt: python3-yaml, pip: pyyaml)')

CONTEXTS = {'github', 'env', 'vars', 'job', 'jobs', 'steps', 'runner', 'secrets', 'strategy', 'matrix', 'needs', 'inputs'}
FUNCTIONS = {'contains', 'startswith', 'endswith', 'format', 'join', 'tojson', 'fromjson', 'hashfiles',
             'success', 'always', 'cancelled', 'failure'}
LITERALS = {'true', 'false', 'null'}
STATUS = {'success', 'always', 'cancelled', 'failure'}   # only in jobs.<id>.if and jobs.<id>.steps.if
SPECIAL = STATUS | {'hashfiles'}                         # hashFiles: only in jobs.<id>.steps.* (not uses/id/shell)
STEP_KEYS = ('continue-on-error', 'env', 'name', 'run', 'timeout-minutes', 'with', 'working-directory')

# GitHub's table, by place. A place not listed here allows no expression at all.
TOP = {'github', 'inputs', 'vars'}
TOP_ENV = {'github', 'secrets', 'inputs', 'vars'}
JOB = {'github', 'needs', 'strategy', 'matrix', 'vars', 'inputs'}
JOB_ENV = JOB | {'secrets'}
JOB_IF = {'github', 'needs', 'vars', 'inputs'}
STEP = {'github', 'needs', 'strategy', 'matrix', 'job', 'runner', 'env', 'vars', 'secrets', 'steps', 'inputs'}
STEP_IF = STEP - {'secrets'}


def allowed(path):
    """The contexts GitHub allows at this path (a tuple of keys/indexes), or an empty set."""
    p = path
    if not p:
        return set()
    head = p[0]
    if head in ('run-name', 'concurrency'):
        return TOP
    if head == 'env':
        return TOP_ENV
    if head == 'on' and len(p) >= 5 and p[1] == 'workflow_call':
        if p[2] == 'inputs' and p[4] == 'default':
            return TOP
        if p[2] == 'outputs' and p[4] == 'value':
            return {'github', 'jobs', 'vars', 'inputs'}
    if head != 'jobs' or len(p) < 3:
        return set()                       # on: (the rest), name:, permissions:, defaults: (top level): no expressions
    key = p[2]
    rest = p[3:]
    if key == 'env':
        return JOB_ENV
    if key in ('if', 'strategy'):
        return JOB_IF
    if key in ('runs-on', 'name', 'timeout-minutes', 'continue-on-error', 'concurrency', 'with'):
        return JOB
    if key == 'environment':
        return STEP - {'secrets'} if rest and rest[0] == 'url' else JOB
    if key == 'secrets':
        return JOB_ENV
    if key == 'defaults':
        return JOB | {'env'}
    if key == 'outputs':
        return STEP
    if key in ('services', 'container'):
        sub = rest[1:] if key == 'services' else rest
        if sub and sub[0] == 'env':
            return STEP - {'steps'}        # the steps have not run when the containers start
        if sub and sub[0] == 'credentials':
            return JOB_ENV | {'env'}
        return JOB
    if key == 'steps':
        if len(rest) < 2:
            return set()
        step_key = rest[1]
        if step_key == 'if':
            return STEP_IF
        if step_key in ('uses', 'id', 'shell'):
            return set()
        return STEP
    return set()                           # needs, uses, permissions: no expressions


def allowed_functions(path):
    """The special functions GitHub allows at this path (the status functions and hashFiles); the rest are allowed everywhere."""
    p = path
    if len(p) == 3 and p[0] == 'jobs' and p[2] == 'if':
        return STATUS
    if len(p) >= 5 and p[0] == 'jobs' and p[2] == 'steps' and isinstance(p[3], int):
        if p[4] == 'if':
            return SPECIAL
        if p[4] in STEP_KEYS:
            return {'hashfiles'}
    return set()


def is_if(path):
    """jobs.<id>.if and jobs.<id>.steps[i].if: GitHub reads the whole value as one expression, with or without ${{ }}."""
    p = path
    return (len(p) == 3 and p[0] == 'jobs' and p[2] == 'if') or \
        (len(p) == 5 and p[0] == 'jobs' and p[2] == 'steps' and isinstance(p[3], int) and p[4] == 'if')


def contexts_in(expr):
    """The context names an expression uses (a name not followed by '(' and not a literal), and the functions it calls."""
    found, calls = set(), set()
    # drop string literals first: 'a.b' inside quotes is text, not a context
    text = re.sub(r"'(?:[^']|'')*'", "''", expr)
    # a name is not preceded by a letter, a dot or a hyphen (strategy.job-index, github.event.check-suite are one path)
    for m in re.finditer(r"(?<![\w.-])([A-Za-z_][\w-]*)(\s*\()?", text):
        name, call = m.group(1), m.group(2)
        low = name.lower()
        if call:
            calls.add(low)
            continue
        if low in LITERALS or re.fullmatch(r'[0-9_]+', name):
            continue
        found.add(low if low in CONTEXTS else name)
    return found, calls


def walk(node, path, out):
    if isinstance(node, dict):
        for k, v in node.items():
            # PyYAML (YAML 1.1) reads the bare key "on" as the boolean True
            key = 'on' if k is True else k
            walk(v, path + (key,), out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, path + (i,), out)
    elif isinstance(node, str) and ('${{' in node or is_if(path)):
        out.append((path, node))


def check(filename):
    problems = []
    with open(filename, encoding='utf-8') as f:
        doc = yaml.safe_load(f)
    leaves = []
    walk(doc, (), leaves)
    for path, text in leaves:
        where = '.'.join(str(x) for x in path)
        ok = allowed(path)
        exprs = re.findall(r'\$\{\{(.*?)\}\}', text, flags=re.S)
        if not exprs and is_if(path):
            exprs = [text]
        for expr in exprs:
            used, calls = contexts_in(expr)
            unknown_fn = sorted(c for c in calls if c not in FUNCTIONS)
            if unknown_fn:
                problems.append(f'{filename}: {where}: unknown function(s) {", ".join(unknown_fn)} in ${{{{{expr.strip()}}}}}')
            misplaced = sorted(c for c in calls if c in SPECIAL and c not in allowed_functions(path))
            if misplaced:
                problems.append(f'{filename}: {where}: function "{", ".join(misplaced)}()" is not allowed here'
                                + ' (status functions only in if:, hashFiles only in a step)')
            unknown = sorted(c for c in used if c not in CONTEXTS)
            if unknown:
                problems.append(f'{filename}: {where}: unknown name(s) {", ".join(unknown)} in ${{{{{expr.strip()}}}}}')
            bad = sorted(c for c in used if c in CONTEXTS and c not in ok)
            if bad:
                problems.append(f'{filename}: {where}: context "{", ".join(bad)}" is not allowed here'
                                + (f' (allowed: {", ".join(sorted(ok))})' if ok else ' (no expression is allowed here)'))
    return problems


def main(files):
    problems = []
    for fn in files:
        try:
            problems += check(fn)
        except yaml.YAMLError as e:
            problems.append(f'{fn}: not valid YAML: {e}')
        except OSError as e:
            problems.append(f'{fn}: cannot read: {e}')
    for p in problems:
        print(p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
