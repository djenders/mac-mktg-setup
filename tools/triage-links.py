#!/usr/bin/env python3
"""
triage-links.py — turn a Chrome bookmark graveyard into something you'd actually read.

Reads Chrome's Bookmarks JSON directly (no manual HTML export), optionally checks
every URL for link rot, dedupes, and writes Markdown you can drop straight into
an Obsidian vault.

  # See what you're dealing with, no network
  ./triage-links.py --stats

  # Full pass: dedupe, check liveness, write markdown
  ./triage-links.py --check --out ~/Codex/_inbox/bookmarks

  # Include a tab dump (one URL per line, from any tab-export extension)
  ./triage-links.py --check --tabs ~/Desktop/tabs.txt --out ~/Codex/_inbox/bookmarks

Stdlib only. No pip install.
"""

import argparse
import json
import os
import re
import sys
import urllib.request
import urllib.error
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

CHROME_ROOT = Path.home() / "Library/Application Support/Google/Chrome"

# Chromium-based browsers use the identical Bookmarks JSON format
OTHER_ROOTS = [
    Path.home() / "Library/Application Support/Dia",
    Path.home() / "Library/Application Support/Comet",
    Path.home() / "Library/Application Support/BraveSoftware/Brave-Browser",
    Path.home() / "Library/Application Support/Arc",
]

# Tracking cruft that makes identical links look distinct
JUNK_PARAMS = re.compile(
    r"^(utm_|fbclid|gclid|msclkid|mc_cid|mc_eid|ref|ref_src|igshid|si|s|_hsenc|_hsmi|"
    r"vero_|piwik_|pk_|yclid|twclid|ttclid|scid|trk|trkCampaign|at_)",
    re.I,
)

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
     "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"


# ------------------------------------------------------------------------------
# Reading
# ------------------------------------------------------------------------------

def chrome_epoch(value):
    """Chrome timestamps are microseconds since 1601-01-01."""
    try:
        us = int(value)
    except (TypeError, ValueError):
        return None
    if us <= 0:
        return None
    return datetime(1601, 1, 1, tzinfo=timezone.utc) + timedelta(microseconds=us)


def walk(node, trail, out):
    kind = node.get("type")
    if kind == "url":
        out.append({
            "title": (node.get("name") or "").strip(),
            "url": node.get("url", ""),
            "folder": " / ".join(trail) or "(root)",
            "added": chrome_epoch(node.get("date_added")),
            "used": chrome_epoch(node.get("date_last_used")),
        })
    elif kind == "folder":
        for child in node.get("children", []):
            walk(child, trail + [node.get("name", "")], out)


def load_bookmarks(paths):
    items = []
    for path in paths:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"  ! could not read {path}: {exc}", file=sys.stderr)
            continue
        profile = path.parent.name
        browser = path.parent.parent.name
        found = []
        for root in data.get("roots", {}).values():
            if isinstance(root, dict) and root.get("type") == "folder":
                walk(root, [], found)
        for item in found:
            item["source"] = f"{browser}/{profile}"
        items.extend(found)
        print(f"  · {len(found):5d} from {browser}/{profile}")
    return items


def discover():
    paths = []
    for root in [CHROME_ROOT] + OTHER_ROOTS:
        if not root.is_dir():
            continue
        for bm in root.glob("*/Bookmarks"):
            if "Snapshots" not in str(bm):
                paths.append(bm)
    return sorted(paths)


# ------------------------------------------------------------------------------
# Normalising & deduping
# ------------------------------------------------------------------------------

def canonical(url):
    """Strip tracking params, trailing slash, fragment, www — so dupes collapse."""
    try:
        parts = urlsplit(url)
    except ValueError:
        return url
    if parts.scheme not in ("http", "https"):
        return url
    host = parts.netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    query = urlencode([(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
                       if not JUNK_PARAMS.match(k)])
    path = parts.path.rstrip("/") or "/"
    return urlunsplit(("https", host, path, query, ""))


def dedupe(items):
    groups = defaultdict(list)
    for item in items:
        groups[canonical(item["url"])].append(item)

    unique, dupes = [], 0
    for key, group in groups.items():
        # Keep the one with the most informative title
        best = max(group, key=lambda i: len(i["title"]))
        best["canonical"] = key
        best["copies"] = len(group)
        best["also_in"] = sorted({g["folder"] for g in group if g["folder"] != best["folder"]})
        unique.append(best)
        dupes += len(group) - 1
    return unique, dupes


# ------------------------------------------------------------------------------
# Link rot
# ------------------------------------------------------------------------------

def probe(item, timeout=8):
    url = item["url"]
    if not url.startswith(("http://", "https://")):
        item["status"] = "skip"
        return item
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            item["status"] = resp.status
            final = resp.geturl()
            if canonical(final) != canonical(url):
                item["redirect"] = final
    except urllib.error.HTTPError as exc:
        # Plenty of servers reject HEAD but serve GET fine
        if exc.code in (403, 405, 501):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    item["status"] = resp.status
                    return item
            except Exception:
                pass
        item["status"] = exc.code
    except Exception as exc:
        item["status"] = type(exc).__name__
    return item


def check_all(items, workers=24):
    done = 0
    total = len(items)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for _ in pool.map(probe, items):
            done += 1
            if done % 25 == 0 or done == total:
                print(f"\r  checking… {done}/{total}", end="", flush=True)
    print()
    return items


def is_alive(item):
    s = item.get("status")
    return isinstance(s, int) and 200 <= s < 400


# ------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------

def fm(title, tags, count):
    return (
        "---\n"
        f"title: {title}\n"
        f"created: {datetime.now().strftime('%Y-%m-%d')}\n"
        f"count: {count}\n"
        f"tags: [{', '.join(tags)}]\n"
        "---\n\n"
    )


def line(item, show_status=False):
    title = item["title"] or item["url"]
    title = title.replace("[", "(").replace("]", ")")
    bits = []
    if item.get("copies", 1) > 1:
        bits.append(f"×{item['copies']}")
    if item.get("added"):
        bits.append(item["added"].strftime("%Y-%m"))
    if show_status:
        bits.append(str(item.get("status")))
    suffix = f"  <sub>{' · '.join(bits)}</sub>" if bits else ""
    return f"- [{title}]({item['url']}){suffix}\n"


def write_markdown(items, outdir, checked):
    outdir = Path(outdir).expanduser()
    outdir.mkdir(parents=True, exist_ok=True)
    written = []

    live = [i for i in items if is_alive(i)] if checked else items
    dead = [i for i in items if not is_alive(i)] if checked else []

    # By folder — the useful one
    by_folder = defaultdict(list)
    for item in live:
        by_folder[item["folder"]].append(item)

    body = fm("Bookmarks", ["bookmarks", "inbox", "triage"], len(live))
    body += "Imported from browser bookmarks. Keep, slurp, or delete — nothing here is sacred.\n\n"
    for folder in sorted(by_folder, key=lambda f: (-len(by_folder[f]), f)):
        body += f"## {folder}  <sub>({len(by_folder[folder])})</sub>\n\n"
        for item in sorted(by_folder[folder], key=lambda i: i["title"].lower()):
            body += line(item)
        body += "\n"
    p = outdir / "Bookmarks.md"
    p.write_text(body, encoding="utf-8")
    written.append(p)

    # By domain — reveals the pattern the folders hide
    by_domain = defaultdict(list)
    for item in live:
        by_domain[urlsplit(item["url"]).netloc.lower().removeprefix("www.")].append(item)

    body = fm("Bookmarks by domain", ["bookmarks", "triage"], len(live))
    body += "Where your attention actually went. Anything with 10+ entries is a subscription you never made.\n\n"
    for domain in sorted(by_domain, key=lambda d: (-len(by_domain[d]), d)):
        entries = by_domain[domain]
        if len(entries) < 2:
            continue
        body += f"## {domain}  <sub>({len(entries)})</sub>\n\n"
        for item in entries:
            body += line(item)
        body += "\n"
    p = outdir / "Bookmarks by domain.md"
    p.write_text(body, encoding="utf-8")
    written.append(p)

    if checked and dead:
        body = fm("Dead bookmarks", ["bookmarks", "linkrot", "delete-me"], len(dead))
        body += ("These didn't respond. Some are genuinely gone; some are paywalls, "
                 "logins, or bot-blockers. Spot-check before bulk-deleting.\n\n")
        for item in sorted(dead, key=lambda i: str(i.get("status"))):
            body += line(item, show_status=True)
        p = outdir / "Dead bookmarks.md"
        p.write_text(body, encoding="utf-8")
        written.append(p)

    return written


def stats(items):
    print(f"\n  total bookmarks:  {len(items)}")
    by_folder = defaultdict(int)
    by_domain = defaultdict(int)
    ancient = 0
    cutoff = datetime.now(timezone.utc) - timedelta(days=730)
    for item in items:
        by_folder[item["folder"]] += 1
        by_domain[urlsplit(item["url"]).netloc.lower().removeprefix("www.")] += 1
        if item.get("added") and item["added"] < cutoff:
            ancient += 1
    print(f"  folders:          {len(by_folder)}")
    print(f"  distinct domains: {len(by_domain)}")
    print(f"  older than 2 yrs: {ancient}  ({ancient*100//max(len(items),1)}%)")
    print("\n  Biggest folders:")
    for folder, n in sorted(by_folder.items(), key=lambda kv: -kv[1])[:12]:
        print(f"    {n:5d}  {folder}")
    print("\n  Biggest domains:")
    for domain, n in sorted(by_domain.items(), key=lambda kv: -kv[1])[:12]:
        print(f"    {n:5d}  {domain}")


# ------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", help="output directory for Markdown")
    ap.add_argument("--check", action="store_true", help="probe every URL for link rot")
    ap.add_argument("--stats", action="store_true", help="print a summary and stop")
    ap.add_argument("--tabs", help="text file of open-tab URLs, one per line")
    ap.add_argument("--bookmarks", nargs="*", help="explicit Bookmarks JSON path(s)")
    ap.add_argument("--workers", type=int, default=24)
    args = ap.parse_args()

    paths = [Path(p) for p in args.bookmarks] if args.bookmarks else discover()
    if not paths and not args.tabs:
        sys.exit("No Bookmarks files found. Pass --bookmarks /path/to/Bookmarks")

    print("Reading:")
    items = load_bookmarks(paths)

    if args.tabs:
        raw = Path(args.tabs).expanduser().read_text(encoding="utf-8").splitlines()
        urls = [u.strip() for u in raw if u.strip().startswith("http")]
        for u in urls:
            items.append({"title": "", "url": u, "folder": "Open tabs",
                          "added": None, "used": None, "source": "tabs"})
        print(f"  · {len(urls):5d} from open tabs")

    items, removed = dedupe(items)
    print(f"\n  {removed} duplicates collapsed → {len(items)} unique")

    if args.stats:
        stats(items)
        return

    if args.check:
        print("\nChecking liveness (HEAD, then GET on 403/405):")
        check_all(items, args.workers)
        alive = sum(1 for i in items if is_alive(i))
        print(f"  {alive} alive, {len(items)-alive} dead or unreachable")

    if args.out:
        written = write_markdown(items, args.out, args.check)
        print("\nWrote:")
        for p in written:
            print(f"  {p}")
        print("\n  Open the vault, sort by folder, and be ruthless.")
    else:
        stats(items)
        print("\n  (pass --out DIR to write Markdown)")


if __name__ == "__main__":
    main()
