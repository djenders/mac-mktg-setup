#!/usr/bin/env python3
"""
verify-enex.py — prove your Evernote export is complete BEFORE you wipe.

The export isn't the risky part. Discovering three weeks later that a notebook
came out empty, or that attachments didn't travel, is — because by then the
account is gone and the desktop client is gone with the machine.

    ./verify-enex.py ~/Desktop/mac-restore-2026-08-17/evernote-enex/

Reports per file: note count, date range, attachment count, total attachment
bytes, and any note that looks suspiciously empty. Flags XML that won't parse.

Stdlib only.
"""

import argparse
import base64
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path

DATE_RE = re.compile(r"^(\d{8})T(\d{6})Z?$")


def parse_date(text):
    if not text:
        return None
    m = DATE_RE.match(text.strip())
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y%m%d")
    except ValueError:
        return None


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"


def inspect(path):
    result = {
        "path": path, "notes": 0, "resources": 0, "res_bytes": 0,
        "tags": set(), "empty": [], "no_title": 0, "titles": [],
        "oldest": None, "newest": None, "error": None,
    }
    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        result["error"] = f"XML parse error: {exc}"
        return result
    except Exception as exc:
        result["error"] = str(exc)
        return result

    root = tree.getroot()
    for note in root.findall(".//note"):
        result["notes"] += 1

        title_el = note.find("title")
        title = (title_el.text or "").strip() if title_el is not None else ""
        if not title:
            result["no_title"] += 1
            title = "(untitled)"
        result["titles"].append(title)

        content_el = note.find("content")
        content = content_el.text or "" if content_el is not None else ""
        # Strip ENML tags to see whether there's any actual text under the markup
        stripped = re.sub(r"<[^>]+>", "", content).strip()

        resources = note.findall("resource")
        for res in resources:
            result["resources"] += 1
            data = res.find("data")
            if data is not None and data.text:
                # base64 → bytes, without decoding the whole payload
                b64 = re.sub(r"\s", "", data.text)
                pad = b64.count("=")
                result["res_bytes"] += (len(b64) * 3) // 4 - pad

        if len(stripped) < 5 and not resources:
            result["empty"].append(title)

        for tag in note.findall("tag"):
            if tag.text:
                result["tags"].add(tag.text.strip())

        for field in ("created", "updated"):
            el = note.find(field)
            d = parse_date(el.text if el is not None else None)
            if d:
                if result["oldest"] is None or d < result["oldest"]:
                    result["oldest"] = d
                if result["newest"] is None or d > result["newest"]:
                    result["newest"] = d

    return result


def safe_name(name, fallback):
    name = unicodedata.normalize("NFKD", name or "")
    name = re.sub(r"[/\\:\x00-\x1f]", "-", name).strip().strip(".")
    return name[:120] or fallback


def extract_attachments(path, outdir):
    """Write every embedded resource out with its original filename."""
    try:
        tree = ET.parse(path)
    except Exception:
        return 0
    base = Path(outdir) / safe_name(path.stem, "notebook")
    written = 0
    for n, note in enumerate(tree.getroot().findall(".//note"), 1):
        t_el = note.find("title")
        note_title = safe_name(t_el.text if t_el is not None else "", f"note-{n}")
        for i, res in enumerate(note.findall("resource"), 1):
            data = res.find("data")
            if data is None or not data.text:
                continue
            fname = None
            attrs = res.find("resource-attributes")
            if attrs is not None:
                fn = attrs.find("file-name")
                if fn is not None and fn.text:
                    fname = safe_name(fn.text, "")
            if not fname:
                mime = res.find("mime")
                ext = (mime.text.split("/")[-1] if mime is not None and mime.text else "bin")
                fname = f"attachment-{i}.{ext}"
            dest = base / note_title
            dest.mkdir(parents=True, exist_ok=True)
            try:
                payload = base64.b64decode(re.sub(r"\s", "", data.text))
            except Exception:
                continue
            target = dest / fname
            k = 1
            while target.exists():
                target = dest / f"{target.stem}-{k}{target.suffix}"
                k += 1
            target.write_bytes(payload)
            written += 1
    return written


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", help="a .enex file, or a directory of them")
    ap.add_argument("--show-empty", action="store_true",
                    help="list the titles of notes that look empty")
    ap.add_argument("--titles", action="store_true",
                    help="print every note title, grouped by notebook")
    ap.add_argument("--extract", metavar="DIR",
                    help="pull attachments out to DIR with their original filenames")
    args = ap.parse_args()

    target = Path(args.target).expanduser()
    if target.is_dir():
        files = sorted(target.glob("*.enex"))
    elif target.is_file():
        files = [target]
    else:
        sys.exit(f"not found: {target}")

    if not files:
        sys.exit(f"no .enex files in {target}")

    print(f"\nInspecting {len(files)} file(s) in {target}\n")

    total_notes = total_res = total_bytes = 0
    all_tags = set()
    problems = []

    for f in files:
        r = inspect(f)
        name = f.name
        if r["error"]:
            print(f"  ✗ {name}")
            print(f"      {r['error']}")
            problems.append((name, r["error"]))
            continue

        span = ""
        if r["oldest"] and r["newest"]:
            span = f"{r['oldest']:%Y-%m} → {r['newest']:%Y-%m}"

        flag = "✓"
        if r["notes"] == 0:
            flag = "✗"
            problems.append((name, "zero notes — re-export this notebook"))

        print(f"  {flag} {name}")
        print(f"      {r['notes']:>5} notes   {span}")
        if r["resources"]:
            print(f"      {r['resources']:>5} attachments  ({human(r['res_bytes'])})")
        if r["tags"]:
            print(f"      {len(r['tags']):>5} distinct tags")
        if r["no_title"]:
            print(f"      {r['no_title']:>5} untitled notes")
        if r["empty"]:
            print(f"      {len(r['empty']):>5} notes with no text and no attachment")
            if args.show_empty:
                for t in r["empty"][:20]:
                    print(f"            · {t}")
                if len(r["empty"]) > 20:
                    print(f"            … and {len(r['empty'])-20} more")
        print()

        if args.titles:
            for t in r["titles"]:
                print(f"        · {t}")
            print()

        total_notes += r["notes"]
        total_res += r["resources"]
        total_bytes += r["res_bytes"]
        all_tags |= r["tags"]

    print("  " + "─" * 52)
    print(f"  {total_notes} notes · {total_res} attachments ({human(total_bytes)}) "
          f"· {len(all_tags)} tags")
    print(f"  across {len(files)} notebook file(s)")
    print()

    if args.extract:
        outdir = Path(args.extract).expanduser()
        outdir.mkdir(parents=True, exist_ok=True)
        n = sum(extract_attachments(f, outdir) for f in files)
        print(f"  extracted {n} attachment(s) → {outdir}")
        print()

    if problems:
        print("  Problems:")
        for name, why in problems:
            print(f"    ! {name}: {why}")
        print()
        print("  Fix these BEFORE the wipe. Re-export from the desktop client.")
        sys.exit(1)

    print("  Now compare that note count against what Evernote shows in the app.")
    print("  If they don't match, a notebook is missing. Do not wipe until they do.")
    print()


if __name__ == "__main__":
    main()
