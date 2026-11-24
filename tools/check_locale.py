#!/usr/bin/env python3
"""Strict gettext POT/PO validator and GDScript runtime string audit."""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

SKIP_DIRS = {"addons", "tests", "spike", "debug"}

NAMED_PLACEHOLDER_RE = re.compile(r"\{[^{}]+\}")
PRINTF_PLACEHOLDER_RE = re.compile(
    r"(?<!%)%(?:[-+#0]|\d+\$)?(?:\d+)?(?:\.\d+)?[sdifuxXogeEc]"
)
PLURAL_FORMS_RE = re.compile(r"(?:^|\n)Plural-Forms:\s*nplurals\s*=\s*(\d+)\s*;", re.MULTILINE)

POT_DIRECTIVE_RE = re.compile(
    r'^(msgctxt|msgid_plural|msgid|msgstr(?:\[(\d+)\])?)\s+(".*")\s*$'
)
STRING_CONT_RE = re.compile(r'^(".*")\s*$')

ESCAPE_MAP = {
    "n": "\n",
    "t": "\t",
    "r": "\r",
    "\\": "\\",
    '"': '"',
    "'": "'",
    "a": "\a",
    "b": "\b",
    "f": "\f",
    "v": "\v",
}


class ParseError(Exception):
    """Raised when a POT, PO, or GDScript source cannot be parsed cleanly."""


@dataclass
class PoEntry:
    line: int
    msgctxt: str = ""
    has_msgctxt: bool = False
    msgid: str | None = None
    msgid_plural: str | None = None
    msgstr: str | None = None
    msgstr_plural: dict[int, str] = field(default_factory=dict)

    @property
    def is_header(self) -> bool:
        return self.msgid == "" and not self.has_msgctxt

    @property
    def is_plural(self) -> bool:
        return self.msgid_plural is not None

    @property
    def key(self) -> tuple[str, str]:
        return (self.msgctxt, self.msgid or "")


@dataclass
class RuntimeCall:
    path: Path
    line: int
    msgctxt: str
    msgid: str
    msgid_plural: str | None = None
    source: str = "call"


def unescape_c_string(quoted: str, path: Path, line_no: int) -> str:
    """Decode a double-quoted gettext string literal."""
    if len(quoted) < 2 or quoted[0] != '"' or quoted[-1] != '"':
        raise ParseError(f"{path}:{line_no}: expected double-quoted string, got {quoted!r}")
    inner = quoted[1:-1]
    out: list[str] = []
    i = 0
    n = len(inner)
    while i < n:
        ch = inner[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= n:
            raise ParseError(f"{path}:{line_no}: trailing backslash in string")
        esc = inner[i]
        if esc in ESCAPE_MAP:
            out.append(ESCAPE_MAP[esc])
            i += 1
        elif esc == "x":
            if i + 2 >= n:
                raise ParseError(f"{path}:{line_no}: truncated \\x escape")
            hex_digits = inner[i + 1 : i + 3]
            try:
                out.append(chr(int(hex_digits, 16)))
            except ValueError as exc:
                raise ParseError(f"{path}:{line_no}: invalid \\x{hex_digits}") from exc
            i += 3
        elif esc in "01234567":
            j = i
            while j < n and j < i + 3 and inner[j] in "01234567":
                j += 1
            out.append(chr(int(inner[i:j], 8)))
            i = j
        else:
            raise ParseError(f"{path}:{line_no}: unknown escape \\{esc}")
    return "".join(out)


def parse_gettext_file(path: Path) -> list[PoEntry]:
    """Parse a .pot or .po file strictly, validating syntax."""
    text = path.read_text(encoding="utf-8")
    entries: list[PoEntry] = []
    cur: PoEntry | None = None
    active_field: str | None = None
    active_plural_idx: int | None = None
    seen_fields: set[str] = set()

    def close_current() -> None:
        nonlocal cur, active_field, active_plural_idx, seen_fields
        if cur is not None:
            if cur.msgid is None:
                raise ParseError(f"{path}:{cur.line}: entry missing msgid")
            entries.append(cur)
        cur = None
        active_field = None
        active_plural_idx = None
        seen_fields = set()

    for line_no, raw in enumerate(text.splitlines(), 1):
        stripped = raw.strip()
        if stripped == "":
            close_current()
            continue
        if stripped.startswith("#"):
            continue

        m = POT_DIRECTIVE_RE.match(stripped)
        if m:
            directive, idx_str, quoted = m.group(1), m.group(2), m.group(3)
            val = unescape_c_string(quoted, path, line_no)
            base_dir = "msgstr[]" if idx_str is not None else directive

            # Allow adjacent entries without blank lines if a new msgctxt/msgid starts after msgstr.
            if cur is not None and base_dir in ("msgctxt", "msgid") and (
                cur.msgstr is not None or cur.msgstr_plural
            ):
                close_current()

            if cur is None:
                cur = PoEntry(line=line_no)

            if directive == "msgctxt":
                if "msgctxt" in seen_fields or "msgid" in seen_fields:
                    raise ParseError(f"{path}:{line_no}: unexpected msgctxt")
                cur.msgctxt = val
                cur.has_msgctxt = True
                seen_fields.add("msgctxt")
                active_field = "msgctxt"
                active_plural_idx = None
            elif directive == "msgid":
                if "msgid" in seen_fields:
                    raise ParseError(f"{path}:{line_no}: duplicate msgid in entry")
                cur.msgid = val
                seen_fields.add("msgid")
                active_field = "msgid"
                active_plural_idx = None
            elif directive == "msgid_plural":
                if "msgid" not in seen_fields or "msgid_plural" in seen_fields:
                    raise ParseError(f"{path}:{line_no}: invalid msgid_plural placement")
                cur.msgid_plural = val
                seen_fields.add("msgid_plural")
                active_field = "msgid_plural"
                active_plural_idx = None
            elif idx_str is not None:
                idx = int(idx_str)
                field_key = f"msgstr[{idx}]"
                if field_key in seen_fields:
                    raise ParseError(f"{path}:{line_no}: duplicate {field_key} in entry")
                cur.msgstr_plural[idx] = val
                seen_fields.add(field_key)
                active_field = "msgstr_plural"
                active_plural_idx = idx
            elif directive == "msgstr":
                if "msgstr" in seen_fields:
                    raise ParseError(f"{path}:{line_no}: duplicate msgstr in entry")
                cur.msgstr = val
                seen_fields.add("msgstr")
                active_field = "msgstr"
                active_plural_idx = None
            continue

        cm = STRING_CONT_RE.match(stripped)
        if cm:
            if cur is None or active_field is None:
                raise ParseError(f"{path}:{line_no}: stray continuation string")
            val = unescape_c_string(cm.group(1), path, line_no)
            if active_field == "msgctxt":
                cur.msgctxt += val
            elif active_field == "msgid":
                cur.msgid = (cur.msgid or "") + val
            elif active_field == "msgid_plural":
                cur.msgid_plural = (cur.msgid_plural or "") + val
            elif active_field == "msgstr":
                cur.msgstr = (cur.msgstr or "") + val
            elif active_field == "msgstr_plural" and active_plural_idx is not None:
                cur.msgstr_plural[active_plural_idx] += val
            continue

        raise ParseError(f"{path}:{line_no}: syntax error: {raw!r}")

    close_current()
    return entries


def validate_pot_entries(entries: list[PoEntry], pot_path: Path) -> tuple[list[str], dict[tuple[str, str], PoEntry]]:
    """Validate POT structure, duplicates, and singular/plural msgstr shapes."""
    errors: list[str] = []
    by_key: dict[tuple[str, str], PoEntry] = {}
    has_header = False

    for entry in entries:
        if entry.is_header:
            if has_header:
                errors.append(f"{pot_path}:{entry.line}: duplicate POT header entry")
            has_header = True
            if entry.is_plural or entry.msgstr is None or entry.msgstr_plural:
                errors.append(f"{pot_path}:{entry.line}: malformed POT header msgstr shape")
            continue

        if entry.msgid == "":
            errors.append(f"{pot_path}:{entry.line}: empty msgid with non-empty msgctxt")
            continue

        if entry.key in by_key:
            first = by_key[entry.key]
            errors.append(
                f"{pot_path}:{entry.line}: duplicate (msgctxt={entry.msgctxt!r}, msgid={entry.msgid!r}) "
                f"(first seen at line {first.line})"
            )
        else:
            by_key[entry.key] = entry

        if entry.is_plural:
            if entry.msgstr is not None or set(entry.msgstr_plural.keys()) != {0, 1}:
                errors.append(
                    f"{pot_path}:{entry.line}: plural entry {entry.msgid!r} must have "
                    f"exactly msgstr[0] and msgstr[1] and no plain msgstr"
                )
        else:
            if entry.msgstr is None or entry.msgstr_plural:
                errors.append(
                    f"{pot_path}:{entry.line}: singular entry {entry.msgid!r} must have "
                    f"plain msgstr and no msgstr[n]"
                )

    if not has_header:
        errors.append(f"{pot_path}:1: missing POT header entry (msgid \"\")")

    return errors, by_key


@dataclass
class GdToken:
    kind: str  # IDENT, STRING, SYMBOL, NEWLINE
    value: str
    line: int


def decode_gd_string(raw: str, quote: str, is_raw: bool) -> str:
    """Decode a GDScript string literal body."""
    if is_raw:
        return raw
    out: list[str] = []
    i = 0
    n = len(raw)
    while i < n:
        ch = raw[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= n:
            out.append("\\")
            break
        esc = raw[i]
        if esc in ESCAPE_MAP:
            out.append(ESCAPE_MAP[esc])
            i += 1
        elif esc == "\n":
            i += 1
        elif esc == "u" and i + 4 < n:
            try:
                out.append(chr(int(raw[i + 1 : i + 5], 16)))
                i += 5
            except ValueError:
                out.append("\\u")
                i += 1
        elif esc == "U" and i + 6 < n:
            try:
                out.append(chr(int(raw[i + 1 : i + 7], 16)))
                i += 7
            except ValueError:
                out.append("\\U")
                i += 1
        else:
            out.append(esc)
            i += 1
    return "".join(out)


def tokenize_gd(text: str) -> list[GdToken]:
    """Tokenize GDScript source, stripping comments and decoding string literals."""
    tokens: list[GdToken] = []
    i = 0
    n = len(text)
    line = 1

    while i < n:
        ch = text[i]
        if ch == "\n":
            tokens.append(GdToken("NEWLINE", "\n", line))
            line += 1
            i += 1
            continue
        if ch in " \t\r":
            i += 1
            continue
        if ch == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue

        # Raw or StringName / NodePath prefixes
        if ch in ("&", "^") and i + 1 < n and text[i + 1] in ('"', "'"):
            tokens.append(GdToken("SYMBOL", ch, line))
            i += 1
            continue

        is_raw = False
        if ch == "r" and i + 1 < n and text[i + 1] in ('"', "'"):
            is_raw = True
            i += 1
            ch = text[i]

        if ch in ('"', "'"):
            start_line = line
            if text[i : i + 3] == ch * 3:
                delim = ch * 3
                i += 3
                start = i
                while i < n and text[i : i + 3] != delim:
                    if not is_raw and text[i] == "\\":
                        if i + 1 < n and text[i + 1] == "\n":
                            line += 1
                        i += 2
                        continue
                    if text[i] == "\n":
                        line += 1
                    i += 1
                body = text[start:i]
                if i < n:
                    i += 3
                tokens.append(GdToken("STRING", decode_gd_string(body, ch, is_raw), start_line))
                continue

            i += 1
            start = i
            while i < n and text[i] != ch:
                if not is_raw and text[i] == "\\":
                    if i + 1 < n and text[i + 1] == "\n":
                        line += 1
                    i += 2
                    continue
                if text[i] == "\n":
                    break
                i += 1
            body = text[start:i]
            if i < n and text[i] == ch:
                i += 1
            tokens.append(GdToken("STRING", decode_gd_string(body, ch, is_raw), start_line))
            continue

        if ch.isalpha() or ch == "_":
            start = i
            while i < n and (text[i].isalnum() or text[i] == "_"):
                i += 1
            tokens.append(GdToken("IDENT", text[start:i], line))
            continue

        if ch.isdigit():
            start = i
            while i < n and (text[i].isalnum() or text[i] in "._"):
                i += 1
            tokens.append(GdToken("NUMBER", text[start:i], line))
            continue

        tokens.append(GdToken("SYMBOL", ch, line))
        i += 1

    return tokens


def eval_string_expr(
    toks: list[GdToken], local_consts: dict[str, str], global_consts: dict[tuple[str, str], str]
) -> str | None:
    """Evaluate a pure string literal / const / '+' expression, or return None."""
    filtered = [t for t in toks if t.kind != "NEWLINE"]
    # Strip balanced outer parentheses
    while (
        len(filtered) >= 2
        and filtered[0].kind == "SYMBOL"
        and filtered[0].value == "("
        and filtered[-1].kind == "SYMBOL"
        and filtered[-1].value == ")"
    ):
        depth = 0
        wraps_all = True
        for idx, tok in enumerate(filtered):
            if tok.kind == "SYMBOL" and tok.value == "(":
                depth += 1
            elif tok.kind == "SYMBOL" and tok.value == ")":
                depth -= 1
                if depth == 0 and idx < len(filtered) - 1:
                    wraps_all = False
                    break
        if wraps_all:
            filtered = filtered[1:-1]
        else:
            break

    if not filtered:
        return None

    parts: list[str] = []
    i = 0
    expect_term = True
    while i < len(filtered):
        tok = filtered[i]
        if not expect_term:
            if tok.kind == "SYMBOL" and tok.value == "+":
                expect_term = True
                i += 1
                continue
            return None

        if tok.kind == "STRING":
            parts.append(tok.value)
            expect_term = False
            i += 1
        elif tok.kind == "IDENT":
            if (
                i + 2 < len(filtered)
                and filtered[i + 1].kind == "SYMBOL"
                and filtered[i + 1].value == "."
                and filtered[i + 2].kind == "IDENT"
            ):
                val = global_consts.get((tok.value, filtered[i + 2].value))
                if val is None:
                    return None
                parts.append(val)
                i += 3
                expect_term = False
            elif tok.value in local_consts:
                parts.append(local_consts[tok.value])
                i += 1
                expect_term = False
            else:
                return None
        elif tok.kind == "SYMBOL" and tok.value == "(":
            depth = 0
            j = i
            while j < len(filtered):
                if filtered[j].kind == "SYMBOL" and filtered[j].value == "(":
                    depth += 1
                elif filtered[j].kind == "SYMBOL" and filtered[j].value == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            if depth != 0:
                return None
            sub = eval_string_expr(filtered[i + 1 : j], local_consts, global_consts)
            if sub is None:
                return None
            parts.append(sub)
            i = j + 1
            expect_term = False
        else:
            return None

    if expect_term:
        return None
    return "".join(parts)


def collect_gd_consts(
    files: list[Path],
) -> tuple[dict[Path, list[GdToken]], dict[Path, dict[str, str]], dict[tuple[str, str], str]]:
    """Tokenize all runtime .gd files and collect string constants."""
    file_tokens: dict[Path, list[GdToken]] = {}
    file_consts: dict[Path, dict[str, str]] = {}
    global_consts: dict[tuple[str, str], str] = {}
    file_classes: dict[Path, str] = {}

    for path in files:
        toks = tokenize_gd(path.read_text(encoding="utf-8"))
        file_tokens[path] = toks
        consts: dict[str, str] = {}
        cls_name = ""

        # First locate class_name
        for i, tok in enumerate(toks):
            if (
                tok.kind == "IDENT"
                and tok.value == "class_name"
                and i + 1 < len(toks)
                and toks[i + 1].kind == "IDENT"
            ):
                cls_name = toks[i + 1].value
                break
        file_classes[path] = cls_name

        # Collect top-level / simple const IDENT [: Type] := expr
        i = 0
        n = len(toks)
        while i < n:
            tok = toks[i]
            if tok.kind == "IDENT" and tok.value == "const" and i + 1 < n and toks[i + 1].kind == "IDENT":
                cname = toks[i + 1].value
                j = i + 2
                # Skip optional type annotation up to '='
                while j < n and not (toks[j].kind == "SYMBOL" and toks[j].value == "="):
                    if toks[j].kind == "NEWLINE":
                        break
                    j += 1
                if j < n and toks[j].kind == "SYMBOL" and toks[j].value == "=":
                    k = j + 1
                    paren_depth = 0
                    while k < n:
                        t = toks[k]
                        if t.kind == "SYMBOL" and t.value in "([{":
                            paren_depth += 1
                        elif t.kind == "SYMBOL" and t.value in ")]}":
                            paren_depth = max(0, paren_depth - 1)
                        elif t.kind == "NEWLINE" and paren_depth == 0:
                            break
                        k += 1
                    val = eval_string_expr(toks[j + 1 : k], consts, global_consts)
                    if val is not None:
                        consts[cname] = val
                        if cls_name:
                            global_consts[(cls_name, cname)] = val
                    i = k
                    continue
            i += 1
        file_consts[path] = consts

    return file_tokens, file_consts, global_consts


def split_call_args(toks: list[GdToken], open_paren_idx: int) -> tuple[list[list[GdToken]], int] | None:
    """Split arguments inside '(' ... ')' at open_paren_idx."""
    args: list[list[GdToken]] = []
    cur: list[GdToken] = []
    depth = 1
    i = open_paren_idx + 1
    n = len(toks)
    while i < n:
        tok = toks[i]
        if tok.kind == "SYMBOL" and tok.value in "([{":
            depth += 1
            cur.append(tok)
        elif tok.kind == "SYMBOL" and tok.value in ")]}":
            depth -= 1
            if depth == 0:
                if any(t.kind != "NEWLINE" for t in cur):
                    args.append(cur)
                return args, i
            cur.append(tok)
        elif tok.kind == "SYMBOL" and tok.value == "," and depth == 1:
            args.append(cur)
            cur = []
        else:
            cur.append(tok)
        i += 1
    return None


def scan_translation_calls(
    files: list[Path],
    file_tokens: dict[Path, list[GdToken]],
    file_consts: dict[Path, dict[str, str]],
    global_consts: dict[tuple[str, str], str],
) -> list[RuntimeCall]:
    """Scan runtime .gd files for literal tr/tr_n/atr/atr_n/TranslationServer calls."""
    calls: list[RuntimeCall] = []

    for path in files:
        toks = file_tokens[path]
        local_consts = file_consts[path]
        n = len(toks)
        i = 0
        while i < n:
            tok = toks[i]
            if tok.kind != "IDENT":
                i += 1
                continue

            kind: str | None = None
            open_idx = -1

            if tok.value in ("tr", "atr", "tr_n", "atr_n"):
                if (
                    i + 1 < n
                    and toks[i + 1].kind == "SYMBOL"
                    and toks[i + 1].value == "("
                ):
                    # Skip function declarations: `func tr(...)`
                    if i > 0 and toks[i - 1].kind == "IDENT" and toks[i - 1].value == "func":
                        i += 1
                        continue
                    kind = tok.value
                    open_idx = i + 1
            elif (
                tok.value == "TranslationServer"
                and i + 3 < n
                and toks[i + 1].kind == "SYMBOL"
                and toks[i + 1].value == "."
                and toks[i + 2].kind == "IDENT"
                and toks[i + 2].value in ("translate", "translate_plural")
                and toks[i + 3].kind == "SYMBOL"
                and toks[i + 3].value == "("
            ):
                kind = toks[i + 2].value
                open_idx = i + 3

            if kind is None:
                i += 1
                continue

            parsed = split_call_args(toks, open_idx)
            if parsed is None:
                i += 1
                continue
            args, _close_idx = parsed

            if kind in ("tr", "atr", "translate"):
                if len(args) >= 1:
                    msgid = eval_string_expr(args[0], local_consts, global_consts)
                    if msgid is not None and msgid != "":
                        ctx = ""
                        if len(args) >= 2:
                            ctx_val = eval_string_expr(args[1], local_consts, global_consts)
                            if ctx_val is not None:
                                ctx = ctx_val
                        calls.append(RuntimeCall(path=path, line=tok.line, msgctxt=ctx, msgid=msgid))
            elif kind in ("tr_n", "atr_n", "translate_plural"):
                if len(args) >= 2:
                    msgid = eval_string_expr(args[0], local_consts, global_consts)
                    plural = eval_string_expr(args[1], local_consts, global_consts)
                    if msgid is not None and plural is not None and msgid != "":
                        ctx = ""
                        if len(args) >= 4:
                            ctx_val = eval_string_expr(args[3], local_consts, global_consts)
                            if ctx_val is not None:
                                ctx = ctx_val
                        calls.append(
                            RuntimeCall(
                                path=path,
                                line=tok.line,
                                msgctxt=ctx,
                                msgid=msgid,
                                msgid_plural=plural,
                            )
                        )

            i = open_idx + 1

    return calls


def extract_const_dict_strings(
    path: Path,
    const_name: str,
    keys: tuple[str, ...],
    toks: list[GdToken],
    local_consts: dict[str, str],
    global_consts: dict[tuple[str, str], str],
) -> list[RuntimeCall]:
    """Extract string values for specified keys from a const Array[Dictionary] / Array."""
    calls: list[RuntimeCall] = []
    n = len(toks)
    start = -1
    for i in range(n - 1):
        if (
            toks[i].kind == "IDENT"
            and toks[i].value == "const"
            and toks[i + 1].kind == "IDENT"
            and toks[i + 1].value == const_name
        ):
            start = i
            break
    if start < 0:
        return calls

    # Find '=' first (skipping typed annotations like Array[Dictionary]), then '['
    j = start + 2
    while j < n and not (toks[j].kind == "SYMBOL" and toks[j].value == "="):
        j += 1
    while j < n and not (toks[j].kind == "SYMBOL" and toks[j].value == "["):
        j += 1
    if j >= n:
        return calls

    bracket_depth = 0
    brace_depth = 0
    k = j
    while k < n:
        t = toks[k]
        if t.kind == "SYMBOL" and t.value == "[":
            bracket_depth += 1
        elif t.kind == "SYMBOL" and t.value == "]":
            bracket_depth -= 1
            if bracket_depth == 0:
                break
        elif t.kind == "SYMBOL" and t.value == "{":
            brace_depth += 1
        elif t.kind == "SYMBOL" and t.value == "}":
            brace_depth = max(0, brace_depth - 1)
        elif (
            t.kind == "STRING"
            and t.value in keys
            and k + 2 < n
            and toks[k + 1].kind == "SYMBOL"
            and toks[k + 1].value == ":"
        ):
            val_start = k + 2
            m = val_start
            expr_depth = 0
            while m < n:
                mt = toks[m]
                if mt.kind == "SYMBOL" and mt.value in "([{":
                    expr_depth += 1
                elif mt.kind == "SYMBOL" and mt.value in ")]}":
                    if expr_depth == 0:
                        break
                    expr_depth -= 1
                elif mt.kind == "SYMBOL" and mt.value == "," and expr_depth == 0:
                    break
                m += 1
            val = eval_string_expr(toks[val_start:m], local_consts, global_consts)
            if val is not None and val != "":
                calls.append(
                    RuntimeCall(
                        path=path,
                        line=toks[val_start].line,
                        msgctxt="",
                        msgid=val,
                        source=f"catalog:{const_name}[{t.value}]",
                    )
                )
            k = m
            continue
        k += 1
    return calls


def collect_dynamic_catalog_calls(
    game_dir: Path,
    file_tokens: dict[Path, list[GdToken]],
    file_consts: dict[Path, dict[str, str]],
    global_consts: dict[tuple[str, str], str],
) -> list[RuntimeCall]:
    """Collect strings from dynamic runtime catalogs translated by variable."""
    calls: list[RuntimeCall] = []
    targets = [
        (game_dir / "core" / "achievements.gd", "CATALOG", ("title", "description")),
        (game_dir / "rating" / "airport_certification.gd", "LEVELS", ("title",)),
        (game_dir / "rating" / "airport_awards.gd", "CATEGORIES", ("title",)),
        (game_dir / "build" / "build_unlocks.gd", "TIERS", ("facilities",)),
    ]
    for path, const_name, keys in targets:
        if path in file_tokens:
            calls.extend(
                extract_const_dict_strings(
                    path, const_name, keys, file_tokens[path], file_consts[path], global_consts
                )
            )
    return calls


def discover_runtime_gd_files(game_dir: Path) -> list[Path]:
    """Return sorted runtime .gd files under game/, skipping excluded directories."""
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(game_dir):
        rel = Path(dirpath).relative_to(game_dir)
        if any(part in SKIP_DIRS for part in rel.parts):
            dirnames[:] = []
            continue
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            if name.endswith(".gd"):
                files.append(Path(dirpath) / name)
    return files


def find_missing_runtime_entries(
    repo_root: Path, pot_entries: dict[tuple[str, str], PoEntry]
) -> list[RuntimeCall]:
    """Scan runtime .gd files and dynamic catalogs against parsed POT entries."""
    game_dir = repo_root / "game"
    files = discover_runtime_gd_files(game_dir)
    file_tokens, file_consts, global_consts = collect_gd_consts(files)
    calls = scan_translation_calls(files, file_tokens, file_consts, global_consts)
    calls.extend(collect_dynamic_catalog_calls(game_dir, file_tokens, file_consts, global_consts))

    missing: list[RuntimeCall] = []
    for call in calls:
        key = (call.msgctxt, call.msgid)
        entry = pot_entries.get(key)
        if entry is None:
            missing.append(call)
        elif call.msgid_plural is not None and entry.msgid_plural != call.msgid_plural:
            missing.append(call)
    return missing


def extract_placeholders(text: str) -> Counter[str]:
    """Return Counter of all {named} and printf tokens in text."""
    tokens = NAMED_PLACEHOLDER_RE.findall(text) + PRINTF_PLACEHOLDER_RE.findall(text)
    return Counter(tokens)


def validate_po_file(
    po_path: Path, pot_entries: dict[tuple[str, str], PoEntry]
) -> tuple[list[str], int]:
    """Validate one .po file against messages.pot. Returns (errors, translated_count)."""
    errors: list[str] = []
    try:
        entries = parse_gettext_file(po_path)
    except ParseError as exc:
        return [str(exc)], 0

    header: PoEntry | None = None
    seen: dict[tuple[str, str], PoEntry] = {}
    nplurals: int | None = None

    for entry in entries:
        if entry.is_header:
            if header is not None:
                errors.append(f"{po_path}:{entry.line}: duplicate PO header entry")
                continue
            header = entry
            if entry.msgstr is None or entry.is_plural or entry.msgstr_plural:
                errors.append(f"{po_path}:{entry.line}: malformed PO header msgstr")
                continue
            pm = PLURAL_FORMS_RE.search(entry.msgstr)
            if not pm:
                errors.append(f"{po_path}:{entry.line}: missing or invalid Plural-Forms header")
            else:
                nplurals = int(pm.group(1))
                if nplurals < 1:
                    errors.append(f"{po_path}:{entry.line}: invalid nplurals={nplurals}")
                    nplurals = None
            continue

        if entry.msgid == "":
            errors.append(f"{po_path}:{entry.line}: empty msgid with non-empty msgctxt")
            continue

        if entry.key in seen:
            first = seen[entry.key]
            errors.append(
                f"{po_path}:{entry.line}: duplicate (msgctxt={entry.msgctxt!r}, msgid={entry.msgid!r}) "
                f"(first seen at line {first.line})"
            )
            continue
        seen[entry.key] = entry

    if header is None:
        errors.append(f"{po_path}:1: missing PO header entry (msgid \"\")")

    translated_count = 0
    expected_plural_indices = set(range(nplurals)) if nplurals is not None else None

    for key, pot_entry in pot_entries.items():
        po_entry = seen.get(key)
        if po_entry is None:
            errors.append(
                f"{po_path}: missing entry (msgctxt={pot_entry.msgctxt!r}, msgid={pot_entry.msgid!r})"
            )
            continue

        if pot_entry.is_plural:
            if po_entry.msgid_plural != pot_entry.msgid_plural:
                errors.append(
                    f"{po_path}:{po_entry.line}: msgid_plural mismatch for {pot_entry.msgid!r}"
                )
                continue
            if po_entry.msgstr is not None:
                errors.append(
                    f"{po_path}:{po_entry.line}: plural entry {pot_entry.msgid!r} must not have plain msgstr"
                )
                continue
            if expected_plural_indices is not None and set(po_entry.msgstr_plural.keys()) != expected_plural_indices:
                errors.append(
                    f"{po_path}:{po_entry.line}: plural entry {pot_entry.msgid!r} must have "
                    f"msgstr[0]..msgstr[{nplurals - 1}] (got {sorted(po_entry.msgstr_plural.keys())})"
                )
                continue

            sg_ph = extract_placeholders(pot_entry.msgid or "")
            pl_ph = extract_placeholders(pot_entry.msgid_plural or "")
            entry_ok = True
            for idx, val in sorted(po_entry.msgstr_plural.items()):
                if val == "":
                    errors.append(
                        f"{po_path}:{po_entry.line}: empty msgstr[{idx}] for {pot_entry.msgid!r}"
                    )
                    entry_ok = False
                    continue
                got_ph = extract_placeholders(val)
                allowed = [sg_ph, pl_ph] if (idx == 0 and (nplurals or 2) > 1 and sg_ph != pl_ph) else [pl_ph]
                if got_ph not in allowed:
                    errors.append(
                        f"{po_path}:{po_entry.line}: placeholder mismatch in msgstr[{idx}] for "
                        f"{pot_entry.msgid!r}: expected {dict(allowed[0])}, got {dict(got_ph)}"
                    )
                    entry_ok = False
            if entry_ok:
                translated_count += 1
        else:
            if po_entry.is_plural or po_entry.msgstr_plural:
                errors.append(
                    f"{po_path}:{po_entry.line}: singular entry {pot_entry.msgid!r} must not have plural forms"
                )
                continue
            if po_entry.msgstr is None or po_entry.msgstr == "":
                errors.append(
                    f"{po_path}:{po_entry.line}: empty msgstr for {pot_entry.msgid!r}"
                )
                continue
            exp_ph = extract_placeholders(pot_entry.msgid or "")
            got_ph = extract_placeholders(po_entry.msgstr)
            if got_ph != exp_ph:
                errors.append(
                    f"{po_path}:{po_entry.line}: placeholder mismatch in msgstr for "
                    f"{pot_entry.msgid!r}: expected {dict(exp_ph)}, got {dict(got_ph)}"
                )
                continue
            translated_count += 1

    return errors, translated_count


def count_po_coverage(po_path: Path, pot_entries: dict[tuple[str, str], PoEntry]) -> tuple[int, int]:
    """Return (covered_non_empty_count, total_entries_in_po) without failing."""
    try:
        entries = parse_gettext_file(po_path)
    except ParseError:
        return 0, 0
    by_key = {e.key: e for e in entries if not e.is_header}
    covered = 0
    for key, pot_entry in pot_entries.items():
        po_entry = by_key.get(key)
        if po_entry is None:
            continue
        if pot_entry.is_plural:
            if po_entry.msgstr_plural and all(v != "" for v in po_entry.msgstr_plural.values()):
                covered += 1
        else:
            if po_entry.msgstr:
                covered += 1
    return covered, len(by_key)


def run_validate_pot(repo_root: Path, pot_path: Path) -> int:
    try:
        entries = parse_gettext_file(pot_path)
    except ParseError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    pot_errors, pot_map = validate_pot_entries(entries, pot_path)
    missing = find_missing_runtime_entries(repo_root, pot_map)

    if pot_errors:
        for err in pot_errors:
            print(f"POT ERROR: {err}", file=sys.stderr)

    if missing:
        dedup: dict[tuple[str, str, str | None], list[RuntimeCall]] = {}
        for call in missing:
            dedup.setdefault((call.msgctxt, call.msgid, call.msgid_plural), []).append(call)
        print(f"MISSING RUNTIME MSGIDS ({len(dedup)} unique, {len(missing)} call sites):", file=sys.stderr)
        for (ctx, msgid, plural), sites in dedup.items():
            locs = ", ".join(f"{s.path.relative_to(repo_root)}:{s.line}" for s in sites[:3])
            if len(sites) > 3:
                locs += f" (+{len(sites) - 3} more)"
            ctx_note = f" [ctx={ctx!r}]" if ctx else ""
            plural_note = f" [plural={plural!r}]" if plural is not None else ""
            print(f"  - {msgid!r}{ctx_note}{plural_note}  <- {locs}", file=sys.stderr)

    if pot_errors or missing:
        return 1

    plural_count = sum(1 for e in pot_map.values() if e.is_plural)
    singular_count = len(pot_map) - plural_count
    print(
        f"POT OK: {len(pot_map)} non-header entries ({singular_count} singular, {plural_count} plural), "
        f"0 duplicates, 0 malformed, 0 missing runtime msgids."
    )
    return 0


def run_validate_po(pot_path: Path, po_paths: list[Path]) -> int:
    try:
        pot_entries_list = parse_gettext_file(pot_path)
    except ParseError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    pot_errors, pot_map = validate_pot_entries(pot_entries_list, pot_path)
    if pot_errors:
        for err in pot_errors:
            print(f"POT ERROR: {err}", file=sys.stderr)
        return 1

    rc = 0
    for po_path in po_paths:
        if not po_path.is_file():
            print(f"PO ERROR: file not found: {po_path}", file=sys.stderr)
            rc = 1
            continue
        errors, translated = validate_po_file(po_path, pot_map)
        if errors:
            rc = 1
            print(f"PO FAIL {po_path} ({len(errors)} errors, {translated}/{len(pot_map)} valid):", file=sys.stderr)
            for err in errors[:50]:
                print(f"  {err}", file=sys.stderr)
            if len(errors) > 50:
                print(f"  ... and {len(errors) - 50} more errors", file=sys.stderr)
        else:
            print(f"PO OK {po_path}: {translated}/{len(pot_map)} (100.0%) valid.")
    return rc


def run_summary(repo_root: Path, pot_path: Path) -> int:
    try:
        entries = parse_gettext_file(pot_path)
    except ParseError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    pot_errors, pot_map = validate_pot_entries(entries, pot_path)
    missing = find_missing_runtime_entries(repo_root, pot_map)
    dedup_missing = {(c.msgctxt, c.msgid, c.msgid_plural) for c in missing}

    plural_count = sum(1 for e in pot_map.values() if e.is_plural)
    singular_count = len(pot_map) - plural_count
    total_with_header = len(entries)

    print(f"POT ({pot_path.relative_to(repo_root)}):")
    print(f"  Total entries (with header): {total_with_header}")
    print(f"  Translatable entries:        {len(pot_map)} ({singular_count} singular, {plural_count} plural)")
    print(f"  POT structural errors:       {len(pot_errors)}")
    print(f"  Missing runtime msgids:      {len(dedup_missing)}")
    print("PO coverage:")

    locale_dir = pot_path.parent
    total_pot = len(pot_map)
    for po_path in sorted(locale_dir.glob("*.po")):
        if po_path.name == "en.po":
            print(f"  {po_path.name:<8} source fallback (header only)")
            continue
        covered, in_file = count_po_coverage(po_path, pot_map)
        pct = (100.0 * covered / total_pot) if total_pot else 0.0
        print(f"  {po_path.name:<8} {covered:4d} / {total_pot} ({pct:5.1f}%)  [{in_file} entries in file]")
    return 0


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    default_pot = repo_root / "game" / "locale" / "messages.pot"

    parser = argparse.ArgumentParser(
        description="Validate Godot gettext POT and Core Steam 10 PO catalogs."
    )
    parser.add_argument(
        "--pot",
        type=Path,
        default=default_pot,
        help="Path to messages.pot (default: game/locale/messages.pot)",
    )
    parser.add_argument(
        "--validate-pot",
        action="store_true",
        help="Validate POT syntax/duplicates/shapes and audit all runtime GDScript msgids.",
    )
    parser.add_argument(
        "--validate-po",
        nargs="+",
        type=Path,
        metavar="PO_FILE",
        help="Validate one or more .po files strictly against messages.pot.",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print POT counts, missing runtime count, and per-PO coverage.",
    )
    args = parser.parse_args()

    if not (args.validate_pot or args.validate_po or args.summary):
        parser.print_help()
        return 2

    pot_path = args.pot if args.pot.is_absolute() else (Path.cwd() / args.pot)
    rc = 0
    if args.validate_pot:
        rc = max(rc, run_validate_pot(repo_root, pot_path))
    if args.validate_po:
        po_paths = [p if p.is_absolute() else (Path.cwd() / p) for p in args.validate_po]
        rc = max(rc, run_validate_po(pot_path, po_paths))
    if args.summary:
        rc = max(rc, run_summary(repo_root, pot_path))
    return rc


if __name__ == "__main__":
    sys.exit(main())
