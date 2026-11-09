# Manual steps

Things no script will do for you, in the order they have to happen.
The first section is the only one with a hard deadline.

---

## 🔴 Before the wipe — irreversible

### Evernote

Two constraints make this the first thing on the list, not the last:

- **`.enex` export only exists in the desktop client.** The web app can't do it.
  The desktop client is on the machine you're about to erase.
- **Free accounts are limited to one connected device.** Over-limit free accounts
  keep read/edit/export rights, but you get one device slot. If reauthorising the
  fresh install goes sideways, there's no second machine to fall back to.

Export per notebook, and use the naming trick — Obsidian's importer reads
`Stack@@@Notebook.enex` and rebuilds the stack as a folder:

1. Evernote → **Notebooks** → `•••` on each notebook → **Export Notebook…**
2. Format **ENEX**, and check **include note attributes** (that's what preserves
   created/updated dates, source URLs, and tags — uncheck it and you get orphan text)
3. Save to `~/Desktop/mac-restore-YYYY-MM-DD/evernote-enex/`
4. Rename: `Research@@@Competitive.enex`, `Personal@@@Recipes.enex`

Then, in Obsidian: Settings → Community plugins → install **Importer** (official,
by the Obsidian team — it wraps the YARLE conversion engine internally) →
choose Evernote (.enex) → point it at the folder.

**Import into quarantine, not into Codex proper.** `_inbox/evernote/`. A few
hundred notes of decade-old Evernote formatting will wreck your graph view and
your search results if you dump them into the root. Let them sit in quarantine
and promote what earns it. A Dataview query over `_inbox/evernote` gives you a
triage queue.

`capture.sh evernote` separately tars `~/Library/Application Support/Evernote`
— the raw local database. You'll almost certainly never open it. Keep it anyway;
it's the only copy that exists once the account lapses.

### Licenses

The indie utility layer is a real cost centre: NotchNook, Alcove, One Switch,
Sleeve, Stillcolor, ColorSlurp, iMazing, Airy. Most are single-machine licenses
delivered by email years ago.

Collect them into a secure note (Passwords.app or 1Password) *before* wiping,
not after. Search your mail for `receipt`, `license key`, `order confirmation`,
`Paddle`, `Gumroad`, `FastSpring`. Record: app, email used, key, purchase date,
vendor. Some vendors need a deactivation on the old machine before the new one
will take the key — check the ones you care about most.

### Two-factor and FileVault

- Confirm at least one *other* trusted device is on your Apple Account
- Write the FileVault recovery key somewhere off the machine
- Check which 2FA codes live in an authenticator app on the Mac only — those
  need to be re-enrolled elsewhere first, or you'll lock yourself out of the
  accounts you need to log back into

### Open tabs

Declare bankruptcy. Really.

If they mattered you'd have read them. Export them so you can prove it to
yourself, then close everything:

1. Install **Tab Session Manager** (open source, exports JSON) or **OneTab**
2. Save all windows → export → `~/Desktop/tabs.json`
3. Or, faster and just as good: `Copy All URLs` extension → paste into `tabs.txt`

Then feed them through the triage tool alongside your bookmarks:

```bash
python3 tools/triage-links.py --check --tabs ~/Desktop/tabs.txt \
  --out ~/Codex/_inbox/bookmarks
```

Anything you don't revisit in thirty days was never a task. It was a feeling of
one.

**The pairing worth noticing:** the Slurp plugin is already installed in Codex
and currently switched off. It saves a webpage into the vault as clean Markdown.
Turn it on. The handful of tabs that survive triage shouldn't come back as
bookmarks — they should come back as *content*, searchable next to your notes,
surviving the link rot that will eventually eat the URL anyway.

---

## 🟡 Before the wipe — expensive to redo

### Local AI models

Don't archive these. **Relocate them.**

LM Studio models and Stability Matrix checkpoints run to tens of gigabytes and
re-downloading is hours you'll spend twice. Move the model directories to a NAS
share or an external SSD and repoint the apps:

- LM Studio: Settings → Models directory
- Stability Matrix: it's a portable app — move the whole data folder and point
  the launcher at the new path
- ComfyUI via Stability Matrix: `extra_model_paths.yaml` handles this cleanly

Do this once and the next three wipes cost nothing. `capture.sh models` writes an
inventory to `manifests/models.md` so you can tell what went missing if something
does.

### Lightroom

`capture.sh creative` grabs presets, profiles, and export templates. It does
**not** grab the catalog — `.lrcat` files are too large and too actively locked.

Handle it separately: Lightroom Classic → File → Optimize Catalog, then quit and
copy `~/Pictures/Lightroom/*.lrcat` plus the `Previews.lrdata` (or don't — previews
regenerate, they're just slow). Enable back-up-on-exit while you're in there.

### Raycast

Raycast has its own export: Settings → Advanced → **Export Settings & Data**.
Produces an encrypted `.rayconfig`. Do it, save it to the archive.

### Warp, Termius, Docker

- Warp launch configurations live in `~/.warp/launch_configurations`
- Termius syncs via account, but confirm it before trusting it
- Docker: `docker compose config` files should already be in git somewhere. Named
  volumes are the risk — if any local container has data you care about, export
  it. Anything running on Mnemosyne is fine and needs nothing.

---

## 🟢 After the wipe

Order matters here.

1. **Sign in to Adobe CC first**, then let fonts sync, *then* restore
   `fonts-user.tar.gz`. Backwards and Font Book fills with duplicates.
2. **Restore fonts:**
   ```bash
   tar -xzf fonts-user.tar.gz -C ~/Library/
   tar -xzf font-collections.tar.gz -C ~/Library/
   ```
   Then open Font Book → File → Validate Fonts and clear anything it flags. A
   wipe is a good moment to stop carrying corrupt fonts you've been dragging
   between machines since 2016.
3. **Obsidian:** install the app, restore the vault, then confirm `.obsidian/`
   came with it. If Sync is doing the work, still verify the plugin list against
   `manifests/obsidian.md` — Sync's settings/plugin sync is a per-vault toggle
   and it's easy to have it off without knowing.
4. **Generate new SSH keys.** Don't restore the old ones. Add the new public key
   to GitHub, the NAS, and anywhere else it belongs. Ten minutes, and your key
   material has never touched a backup.
5. **Re-pair:** Tailscale, UniFi, Sonos, Roon remote, printer.
6. **Run `capture.sh` again after a week.** Whatever it finds that isn't in the
   manifests is something you rebuilt by hand and forgot to write down. That's
   the diff that makes the next wipe cheaper than this one.

---

## Things deliberately not automated

| | why |
|---|---|
| SSH / GPG keys | rotate instead; a wipe is free key rotation |
| Browser passwords | in the keychain and the password manager already |
| Photos library | iCloud; verify "Download Originals" before wiping |
| Messages history | needs Messages in iCloud enabled beforehand |
| Work-managed apps | Defender, Webex, Teams config — MDM will push these back |
| Time Machine restore | defeats the entire purpose of a clean install |
