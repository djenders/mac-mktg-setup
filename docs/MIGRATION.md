# Migration runbook — Daedalus → new machine

**This is not a wipe.** Both machines are alive at the same time. That single
fact removes almost every risk in `docs/MANUAL.md`, because nothing is
irreversible while the old machine still boots.

Rule for the whole operation: **don't touch Daedalus.** No wiping, no
"cleaning up," no selling. It stays exactly as it is for thirty days. It is
your rollback, your reference, and — for Evernote specifically — your only
authorized device.

---

## Tonight, on Daedalus

Everything here happens before the box is opened.

### 1. Re-capture. The August data is three months stale.

```bash
cd ~/Developer/mac-mktg-setup/capture
./capture.sh
git -C .. add manifests brewfiles config
git -C .. commit -m "capture $(date +%F) — pre-migration"
git -C .. push
```

Diff it against August. Anything new is something you installed and forgot.

### 2. Evernote — export from Daedalus, and only Daedalus

Free accounts get **one connected device**. If you install Evernote on the new
machine, it may claim that slot and knock Daedalus out of the only client that
can produce a `.enex`.

So: **do not install Evernote on the new machine. Ever.** It is not in any
Brewfile and should not be added to one.

Export per `docs/MANUAL.md`, then verify:

```bash
python3 ~/Developer/mac-mktg-setup/tools/verify-enex.py \
  ~/Desktop/mac-restore-*/evernote-enex/ --titles > ~/Desktop/evernote-index.txt
```

Compare the note count to what the app shows. If they don't match, re-export.

### 3. Ship the archive

```bash
rsync -avh --progress ~/Desktop/mac-restore-*/ \
  Mnemosyne:/archive/mac-restore/2026-11-daedalus/
ssh Mnemosyne 'cd /archive/mac-restore/2026-11-daedalus && shasum -a 256 -c SHA256SUMS'
```

### 4. Collect what isn't a file

- **Licenses** — NotchNook, Alcove, One Switch, Sleeve, Stillcolor, iMazing,
  Airy. Search mail for Paddle, Gumroad, FastSpring. Some vendors need
  deactivation on the old machine before the new one accepts the key.
- **2FA** — any authenticator living only on Daedalus needs a second enrollment
  before you start signing into things on a new device.
- **Name the new machine.** `MANIFEST.md` uses `ComputerName` to distinguish
  archives. Two machines both called "Daedalus" makes your archive history
  useless.

---

## Tomorrow — Setup Assistant

### Do NOT run Migration Assistant.

Setup Assistant will offer to bring everything over from Daedalus. Decline it.
Choose **"Don't transfer any information now."**

The case for declining: you built a restore kit precisely so this would be a
rebuild rather than a transplant. Migration Assistant would faithfully carry
over the three-way `node` / `node@20` / `nvm` conflict, EOL `python@3.9`,
`watchman` from a fork you never used, the phantom `chatgpt` cask whose app
doesn't exist, and the duplicate `ledger-live`. That cruft is exactly what this
whole project exists to shed.

The usual argument for migrating — "but I'll lose my data" — doesn't hold here,
because Daedalus is sitting right there. You can pull any file across at any
time, and Migration Assistant still exists in `/Applications/Utilities/` if you
later decide you want it.

**You can always migrate later. You can never un-migrate.**

### Settings during setup

- Sign into Apple Account, enable iCloud, FileVault
- **Decline Apple Intelligence setup for now** — one fewer variable while you
  work out what's broken
- Set the computer name immediately: System Settings → General → About → Name

### Update before you install anything

The machine ships with some build of macOS 27 Golden Gate. Get to **27.2** (the
current stable, released 26 October).

**Stay off 27.3.** It is beta only — developer beta 1 landed 3 November, public
beta 2 days later. You are about to depend on this machine for client work.

---

## Build order

Order matters in three places. Everything else is flexible.

### 1. Foundations

```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

mkdir -p ~/Developer && cd ~/Developer
git clone https://github.com/djenders/mac-mktg-setup.git
cd mac-mktg-setup
```

### 2. Core, then tiers

```bash
brew bundle install --file=brewfiles/Brewfile.core
brew bundle install --file=brewfiles/Brewfile.media
brew bundle install --file=brewfiles/Brewfile.ai
brew bundle install --file=brewfiles/Brewfile.finance
# work tier: check MDM first — see the note in that file
```

### 3. Adobe — **order-critical**

```bash
brew bundle install --file=brewfiles/Brewfile.creative
```

1. Sign into Creative Cloud
2. Let Adobe Fonts finish syncing
3. **Only then** restore fonts:

```bash
tar -xzf fonts-user.tar.gz -C ~/Library/
tar -xzf font-collections.tar.gz -C ~/Library/
```

Reverse 2 and 3 and Font Book fills with duplicates. Afterwards: Font Book →
File → Validate Fonts, and bin whatever it flags. No reason to carry corrupt
fonts onto a machine that has never seen them.

Then restore Lightroom presets and Camera Raw settings from
`creative/*.tar.gz`, and copy the `.lrcat` catalogs across by hand.

### 4. Obsidian — **order-critical**

Install the app and sign into Sync **before** restoring anything. Then:

```bash
tar -xzf obsidian-codex-full.tar.gz -C ~/Documents/
```

Verify the plugin list against `manifests/obsidian.md`. Sync's
settings-and-plugins toggle is per-vault and easy to have off without knowing.

Install **Importer** and do the Evernote import into `_inbox/evernote/` now —
you have the enex files and a clean vault, which is the easiest this will ever be.

### 5. Models — **set this up right once**

Do not let LM Studio or Stability Matrix put models in `~`. Point them at an
external SSD or a NAS share on day one:

- LM Studio → Settings → Models directory
- Stability Matrix → portable; place the data folder where you want it
- ComfyUI → `extra_model_paths.yaml`

Get this right now and every future machine costs nothing. You also have a
40-core GPU, so re-downloading is the only slow part of local inference left.

**Decide: Stability Matrix or Comfy Desktop, not both.** See `Brewfile.ai`.

### 6. Git identity — the dotfiles can't carry it

`config/shell/` is deliberately out of this public repo, so a fresh machine
invents an identity from your hostname (`djenders@MacBook-Pro.localdomain`).
Commits made that way don't link to your GitHub account. Set it before the
first commit:

```bash
git config --global user.name "Dennis Jenders"
git config --global user.email "djenders@users.noreply.github.com"
```

The noreply address keeps a real mailbox out of public commit metadata.

`gh` is in `Brewfile.core`, and `gh auth login` installs git's credential
helper. Without it, pushing over HTTPS fails with a password prompt that can
never succeed — GitHub dropped password auth in 2021.

**Once a commit is pushed, never `--amend` it.** Add a new commit instead. An
amended commit gets a new SHA, diverges from the remote, and the only ways out
are a force-push or this:

```bash
git fetch origin && git reset --soft origin/master
git commit -m "<what the change actually was>"
git push
```

### 7. Keys — generate, don't copy

```bash
ssh-keygen -t ed25519 -C "djenders@users.noreply.github.com"
```

Add the new public key to GitHub, Mnemosyne, and anywhere else. A new machine
is free key rotation. Your old private keys never touch a backup.

### 8. Re-pair

Tailscale · UniFi · Sonos · Roon remote (Core stays on Mnemosyne) · printer ·
Samsung Magician · Logitech

---

## The new step: the Intel app audit

macOS 27 is **the last release with full Rosetta 2**. macOS 28, arriving around
September 2027, removes it except for a narrow games carve-out. Rosetta is no
longer installed by default — it installs on first launch of an Intel app.

Golden Gate adds a list for exactly this:

> **System Settings → General → About → Intel-Based Apps → Details**

It shows every installed app that needs Rosetta, *and when each was last
launched in the past year*.

Run it after everything is installed. Every app on that list is on a ~10-month
clock. Likely candidates in your stack: Airy, VidBee, OrpheusDL GUI,
SamsungMagician, ComicTagger.

This is a new column for Brewfile decisions — not just "do I want this?" but
"will it still run next autumn?" Replacing one app deliberately now beats five
breaking at once during a client sprint. It's also a second argument for
OpenLogi over Logi Options+.

---

## Close the loop

Two weeks in, run capture on the new machine and diff:

```bash
cd ~/Developer/mac-mktg-setup/capture && ./capture.sh
git -C .. diff manifests/
```

Whatever appears in that diff is what you rebuilt by hand and forgot to write
down. Fold it into the Brewfiles and commit.

That diff is the entire point of this repo. It's what makes migration three
cost an afternoon.

---

## Only then, Daedalus

After thirty days and at least one full client cycle on the new machine:

1. Confirm nothing is still only on Daedalus
2. Deactivate per-machine licenses
3. Sign out of Apple Account, iCloud, Adobe, Messages
4. Erase All Content and Settings

Daedalus becomes a known-good spare running macOS 26 — which is worth keeping
around, since it's the last macOS that could ever boot an Intel Mac and the
last one you have in a different major version. Handy when you need to test
whether something broke because of 27 or because of you.
