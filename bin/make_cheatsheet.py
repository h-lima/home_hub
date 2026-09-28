"""Home hub cheat sheet: the routine tasks that keep the system working (A4, 3 pages).

    python3 bin/make_cheatsheet.py              # writes ../cheatsheet.pdf next to README.org
    python3 bin/make_cheatsheet.py out.pdf      # elsewhere
Needs reportlab (pip install reportlab) and the DejaVu fonts. Edit the rows below and rerun.
"""
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.colors import HexColor, white
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph, Table,
                                TableStyle, Spacer, KeepTogether, PageBreak)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.fonts import addMapping

import os, sys
D = next((d for d in ("/usr/share/fonts/truetype/dejavu/", "/usr/share/fonts/TTF/")   # Ubuntu, Arch
          if os.path.exists(os.path.join(d, "DejaVuSans.ttf"))), None)
if D is None:
    sys.exit("DejaVu fonts not found. Arch: pacman -S ttf-dejavu · Ubuntu: apt install fonts-dejavu")
for n, f in (("S", "DejaVuSans.ttf"), ("SB", "DejaVuSans-Bold.ttf"),
             ("SI", "DejaVuSans-Oblique.ttf"), ("SBI", "DejaVuSans-BoldOblique.ttf"),
             ("C", "DejaVuSansCondensed.ttf"), ("CB", "DejaVuSansCondensed-Bold.ttf")):
    pdfmetrics.registerFont(TTFont(n, D + f))
pdfmetrics.registerFont(TTFont("M", D + "DejaVuSansMono.ttf"))
pdfmetrics.registerFont(TTFont("MB", D + "DejaVuSansMono-Bold.ttf"))
addMapping("S", 0, 0, "S"); addMapping("S", 1, 0, "SB"); addMapping("S", 0, 1, "SI"); addMapping("S", 1, 1, "SBI")

INK = HexColor("#1f2933"); MUTED = HexColor("#5f6b76"); RULE = HexColor("#d5dbe1")
ACC = HexColor("#2f5d8a"); ACC_BG = HexColor("#eaf1f8"); WARN = HexColor("#9a3b1f"); WARN_BG = HexColor("#fbeee8")
HOME = HexColor("#2f6f4f"); WORK = HexColor("#6a4c93"); PHONE = HexColor("#b36b00"); ALL = HexColor("#4a5560")
CODE_BG = HexColor("#f4f6f8")

W, H = A4
M = 13 * mm

title = ParagraphStyle("t", fontName="SB", fontSize=17, leading=20, textColor=ACC)
sub = ParagraphStyle("st", fontName="SI", fontSize=8.6, leading=11, textColor=MUTED)
h2 = ParagraphStyle("h2", fontName="SB", fontSize=11, leading=13.5, textColor=white)
body = ParagraphStyle("b", fontName="S", fontSize=8.4, leading=10.8, textColor=INK)
small = ParagraphStyle("sm", parent=body, fontSize=7.6, leading=9.6, textColor=MUTED)
cell = ParagraphStyle("c", fontName="S", fontSize=7.9, leading=9.8, textColor=INK)
cellb = ParagraphStyle("cb", parent=cell, fontName="SB")
code = ParagraphStyle("code", fontName="M", fontSize=7.3, leading=9.2, textColor=INK)
hdr = ParagraphStyle("hd", fontName="CB", fontSize=7.8, leading=9.6, textColor=MUTED)


def band(text, color=ACC):
    t = Table([[Paragraph(text, h2)]], colWidths=[W - 2 * M])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), color),
                           ("LEFTPADDING", (0, 0), (-1, -1), 6), ("TOPPADDING", (0, 0), (-1, -1), 3),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
    return t


def c(s):   # a command cell: monospace, with line breaks kept
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\n", "<br/>")
    return Paragraph(s, code)


def p(s, st=cell):
    return Paragraph(s, st)


def table(rows, widths, head=None, zebra=True):
    data = ([[Paragraph(h, hdr) for h in head]] if head else []) + rows
    t = Table(data, colWidths=widths, repeatRows=1 if head else 0)
    st = [("VALIGN", (0, 0), (-1, -1), "TOP"),
          ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
          ("TOPPADDING", (0, 0), (-1, -1), 2.6), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.6),
          ("LINEBELOW", (0, 0), (-1, -1), 0.4, RULE)]
    if head:
        st += [("LINEBELOW", (0, 0), (-1, 0), 0.8, MUTED)]
    if zebra:
        start = 1 if head else 0
        for i in range(start, len(data)):
            if (i - start) % 2 == 1:
                st.append(("BACKGROUND", (0, i), (-1, i), CODE_BG))
    t.setStyle(TableStyle(st))
    return t


def tag(label, color):
    return f"<font name='CB' color='{color.hexval().replace('0x', '#')}'>{label}</font>"


TH = tag("HOME", HOME); TW = tag("WORK", WORK); TP = tag("PHONE", PHONE); TB = tag("BOTH", ALL)
TC = tag("CLUSTER", ALL)

CW = W - 2 * M
story = []

# ----------------------------------------------------------------- page 1: every day
story += [Paragraph("Home hub — routine cheat sheet", title),
          Paragraph("What to do, where, and when, to keep sync, the phone pages and the backups working. "
                    "Full details: <font name='M'>~/sys_org/home_hub/</font> (README → runbook, helpers, recovery). "
                    "Home laptop = Arch, user <font name='M'>archx</font>, tailnet name "
                    "<font name='M'>home.tail53b947.ts.net</font>, SSH port 2255.", sub),
          Spacer(1, 5)]

story += [band("1 · Every study or work session"), Spacer(1, 3)]
rows = [
    [p(f"{TB}<br/>sit down"), c("sync-all"),
     p("Pulls study system, lectures, org-roam, home_hub, Timewarrior; files the phone inbox; "
       "<font name='M'>task sync</font>. Asks the GitHub key passphrase (no agent). "
       "Read the last line: <b>All synced</b> or <b>Needs attention: &lt;repo&gt;</b>.")],
    [p(f"{TB}<br/>get up"), c("sync-all"),
     p("Commits and pushes what you changed. <b>The one rule:</b> never edit the same file on both laptops "
       "between two syncs.")],
    [p(f"{TB}<br/>dry run"), c("sync-all -n"), p("Shows what would be synced; touches nothing.")],
    [p(f"{TW}<br/>shell at home"), c("ssh -t home tmux new -A -s main"),
     p("Reattaches the same session after a drop. Plain <font name='M'>ssh home</font> also works "
       "(key <font name='M'>id_ed25519_home</font>).")],
    [p(f"{TW}<br/>notebooks, webUIs"), c("http://home.tail53b947.ts.net:8881"),
     p("Containers published on the tailnet address (<font name='M'>docker run -p $(tailscale ip -4):8881:8888 …</font>). "
       "Ports: 888x Jupyter · 42xx Quarto · 80xx web.")],
    [p(f"{TW}<br/>127.0.0.1-only port"), c("fwd 8881 4200\nunfwd 4200\nssh -O exit home"),
     p("On-the-fly tunnels over one shared SSH connection (the <font name='M'>fwd</font> function in "
       "<font name='M'>~/.bashrc</font>, ControlMaster on <font name='M'>Host home</font>).")],
    [p(f"{TH}<br/>heavy work"), c("nvim file.qmd   # in tmux\nquarto preview … --port 4200"),
     p("Code, kernel, data and renderer on the home laptop; only keystrokes and the page cross the network.")],
]
story.append(table(rows, [26 * mm, 58 * mm, CW - 84 * mm], head=["Where / when", "Command", "What it does"]))
story.append(Spacer(1, 7))

story += [band("2 · Phone (Android) and clusters", PHONE), Spacer(1, 3)]
rows = [
    [p(f"{TP}<br/>always"), p("Tailscale app <b>connected</b>"), p("Nothing is reachable without it; it can stay on all day.")],
    [p(f"{TP}<br/>read"), c("https://home.tail53b947.ts.net/\nhttps://home.tail53b947.ts.net:8443/notes/week.html"),
     p("Lectures (progress saved, committed within 10 min) · study site. Pin both: ⋮ → Add to Home screen.")],
    [p(f"{TP}<br/>note / log"), c("logs/inbox.md  ← one line\ntime 06:00-06:50 math …\nnext math: …   win: …"),
     p("Filed by the next <font name='M'>sync-all</font> on a laptop (<font name='M'>learn inbox</font>).")],
    [p(f"{TP}<br/>shell"), c("ssh home   # Termux"),
     p("Termux config uses the <b>100.x address</b> (<font name='M'>tailscale ip -4</font> at home), port 2255.")],
    [p(f"{TC}<br/>code, notes"), c("git clone / git pull   (GitHub)"),
     p("Clusters cannot join the tailnet. Log time there with an inbox line, commit, push.")],
    [p(f"{TC}<br/>data → drive"), c("sh ~/sys_org/home_hub/bin/backup-clusters.sh"),
     p("From the home laptop if the cluster lets it in; else from the work laptop (→ <font name='M'>~/cluster-mirror</font>, "
       "carried by its backup). List: <font name='M'>~/.config/home-server/clusters</font>.")],
]
story.append(table(rows, [26 * mm, 70 * mm, CW - 96 * mm], head=["Where / when", "Do", "Note"]))
story.append(Spacer(1, 7))

story += [band("3 · What runs by itself (nothing to do — just know it is there)", ALL), Spacer(1, 3)]
rows = [
    [p(TH), p("<b>home-refresh</b>", cell), p("every 10 min"),
     p("Pull + rebuild the study site in <font name='M'>~/srv</font>, commit phone reading progress, "
       "sync Timewarrior, <font name='M'>task sync</font>. Uses the passphrase-less deploy keys.")],
    [p(TB), p("<b>task-keep</b>"), p("home 03:00<br/>work 01:00"),
     p("JSON export of all tasks → <font name='M'>~/backups/tasks/</font> (90 days); at home also a copy of the sync server DB (14 days).")],
    [p(TH), p("<b>backup-system</b> (root)"), p("daily 03:30"),
     p("Whole system + <font name='M'>/mnt/StorageHDD</font> + manifest → Toshiba drive; refreshes <font name='M'>backups/RECOVERY/</font>.")],
    [p(TW), p("<b>backup</b>"), p("01:30"),
     p("<font name='M'>/home/hlima</font> → drive over Tailscale (backup key); skips quietly when home is unreachable, catches up later.")],
    [p(TH), p("<b>backup-prune</b> (root)"), p("Sun 05:00"),
     p("Thin snapshots (7 daily · 8 weekly · 24 monthly · 10 yearly), free space, <font name='M'>restic check</font> — every repository.")],
    [p(TH), p("<b>backup-check</b> (root)"), p("1st, 06:00"),
     p("Reads back 10 % of every repository's data.")],
    [p(TH), p("<b>lectures-web · study-web · tasksync</b>"), p("always"),
     p("On 127.0.0.1, published to the tailnet by <font name='M'>tailscale serve</font> on 443 · 8443 · 10000.")],
]
story.append(table(rows, [14 * mm, 38 * mm, 20 * mm, CW - 72 * mm], head=["", "Job", "When", "What"]))

story.append(PageBreak())

# ----------------------------------------------------------------- page 2: weekly / monthly / yearly
story += [band("4 · Weekly — at the Saturday review (5 minutes)"), Spacer(1, 3)]
rows = [
    [p(TH), c("sudo backup-system snapshots | tail -3"), p("A snapshot from last night?")],
    [p(TW), c("sh ~/sys_org/home_hub/bin/backup.sh snapshots | tail -3"), p("A snapshot from the last day or two?")],
    [p(TB), c("systemctl --failed; systemctl --user --failed"), p("Must list 0 units.")],
    [p(TH), c("journalctl -u backup-prune -n 15 --no-pager"), p("Ends with “no errors were found”.")],
    [p(TH), c("journalctl --user -u home-refresh -n 10 --no-pager"), p("No “pull failed” / “build failed”.")],
    [p(TB), c("tailscale status"), p("Both laptops and the phone listed; home “active”.")],
]
story.append(table(rows, [14 * mm, 88 * mm, CW - 102 * mm]))
story.append(Spacer(1, 7))

story += [band("5 · Monthly — at the monthly review (15 minutes)"), Spacer(1, 3)]
rows = [
    [p(TB), p("<b>Restore one file</b> and open it — the only real proof"),
     c("sudo RESTIC_PASSWORD_FILE=/etc/restic/password restic -r \\\n  /run/media/archx/Toshiba_4T/backups/restic/$(hostname -s) \\\n  restore latest --include <file> --target /tmp/r      # HOME\nsh …/backup.sh restore latest <file> /tmp/r           # WORK")],
    [p(TH), p("<b>Disk health</b> (old laptop, old disks)"),
     c("cat /var/backups/system-manifest/smart.txt\njournalctl -u backup-system | grep -i smart")],
    [p(TH), p("<b>Drive space</b>"), c("df -h /run/media/archx/Toshiba_4T")],
    [p(TH), p("<b>Monthly read-back</b> passed"), c("journalctl -u backup-check -n 10 --no-pager")],
    [p(TB), p("<b>Task exports</b> exist from today"), c("sh ~/sys_org/home_hub/bin/task-keep.sh --list | tail -3")],
    [p(TH), p("<b>Serving clone clean</b> (never edit it)"), c("git -C ~/srv/study-system status -s")],
    [p(TH), p("<b>Updates</b>, then check everything came back"),
     c("sudo pacman -Syu && sudo reboot\n# afterwards: phone pages load, task sync works")],
    [p(TW), p("<b>Updates</b>"), c("sudo apt update && sudo apt upgrade")],
]
story.append(table(rows, [14 * mm, 58 * mm, CW - 72 * mm]))
story.append(Spacer(1, 7))

story += [band("6 · Quarterly and yearly"), Spacer(1, 3)]
rows = [
    [p("<b>Quarterly</b>"), p("Second copy away from the house (fire, theft, surge take laptop + drive together):"),
     c("restic -r /run/media/archx/OFFSITE/restic-home copy \\\n  --from-repo /run/media/archx/Toshiba_4T/backups/restic/<host> latest")],
    [p("<b>Quarterly</b>"), p("Cluster data to the drive"), c("sh ~/sys_org/home_hub/bin/backup-clusters.sh")],
    [p("<b>Yearly</b>"), p("Rehearse a rebuild in a VM (recovery.org, scenario 3 or 4). Note every surprise in the file."),
     c("virt-manager  # or qemu, with the real drive attached")],
    [p("<b>Yearly</b>"), p("Lectures repository size (each library rebuild adds history)"),
     c("gh repo view h-lima/lectures --json diskUsage")],
    [p("<b>Yearly</b>"), p("Arch USB stick still boots; password manager holds every secret (box below)."), p("")],
]
story.append(table(rows, [18 * mm, 72 * mm, CW - 90 * mm]))

story.append(PageBreak())

# ----------------------------------------------------------------- page 3: before risky changes / fixes / keys
story += [band("7 · Before anything risky, and after editing a helper", WARN), Spacer(1, 3)]
rows = [
    [p("Before upgrading Taskwarrior, touching <font name='M'>~/.task</font> or <font name='M'>~/.timewarrior</font>, "
       "merging, or any change you are unsure about"),
     c("sh ~/sys_org/home_hub/bin/safety-snapshot.sh"),
     p("Must end with <b>SAFETY SNAPSHOT COMPLETE</b>. Roll back tasks: "
       "<font name='M'>mv ~/.task ~/.task.broken &amp;&amp; tar xzf S/dot-task.tar.gz -C ~</font>")],
    [p("After editing <font name='M'>bin/backup-system.sh</font> in home_hub"),
     c("sudo sh ~/sys_org/home_hub/bin/backup-system.sh install"),
     p("Root runs only the installed copy in <font name='M'>/usr/local/sbin</font>.")],
    [p("After changing <font name='M'>config.sh</font> or the services"),
     c("sh ~/sys_org/home_hub/bin/install-home.sh"), p("Safe to run again.")],
    [p("New excludes on the work laptop"),
     c("restic backup ~ --exclude-file ~/.config/restic/excludes \\\n  --one-file-system --dry-run -v | tail -5"),
     p("See size and file count before a real run.")],
]
story.append(table(rows, [44 * mm, 84 * mm, CW - 128 * mm]))
story.append(Spacer(1, 7))

story += [band("8 · When something is off", WARN), Spacer(1, 3)]
rows = [
    [p("Phone page does not load"), c("tailscale serve status\nsystemctl --user status lectures-web study-web"), p("App connected? Services active?")],
    [p("Progress does not save"), c("grep LIBRARY_HOSTS ~/.config/systemd/user/lectures-web.service"), p("Must be the exact tailnet name.")],
    [p("Study site out of date / no PDF"), c("less ~/srv/build-site.log"), p("reportlab in <font name='M'>~/srv/study-system/.venv</font>?")],
    [p("<font name='M'>task sync</font> fails"), c("ssh home systemctl --user status tasksync\ntask show sync"), p("Settings identical on both laptops. Worse: recovery.org scenario 7.")],
    [p("Backup “not reachable”"), c("ssh home true\nsftp home-backup   # then: bye\nssh home mountpoint /run/media/archx/Toshiba_4T"), p("Tailscale up? Drive mounted?")],
    [p("<b>Needs attention: &lt;repo&gt;</b>"), c("cd <repo> && git status"), p("Resolve, <font name='M'>git rebase --continue</font>, run sync-all again.")],
    [p("Pull stops in <font name='M'>~/.timewarrior</font>"), c("python3 ~/sys_org/home_hub/bin/timew-merge.py install"), p("Driver missing in that clone; then continue the rebase.")],
    [p("SSH asks for the wrong key"), c("ssh -v home true 2>&1 | grep -iE 'offering|accepted'"), p("<font name='M'>IdentitiesOnly yes</font> in the Host entry.")],
    [p("Stale restic lock"), c("restic unlock"), p("Removes only locks of crashed runs.")],
]
story.append(table(rows, [42 * mm, 82 * mm, CW - 124 * mm]))
story.append(Spacer(1, 7))

left = table([
    [p("<b>Key</b>", cellb), p("<b>Opens</b>", cellb)],
    [c("~/.ssh/id_ed25519"), p("GitHub (work laptop)")],
    [c("~/.ssh/id_ed25519_home"), p("home laptop login")],
    [c("~/.ssh/id_ed25519_backup"), p("backups only: sftp, tailnet only")],
    [c("~/.ssh/deploy_*  (home)"), p("home-refresh: one repo each")],
    [p("Termux key (phone)"), p("home laptop login")],
], [44 * mm, (CW / 2) - 48 * mm], zebra=False)
right = table([
    [p("<b>Lost a device?</b> Revoke its keys:", cellb)],
    [p("GitHub → Settings → SSH keys (and repo → Deploy keys)")],
    [p("home laptop: delete its line in <font name='M'>~/.ssh/authorized_keys</font> (each line has a comment)")],
    [p("<b>In the password manager — never only on a laptop:</b>", cellb)],
    [p("restic password · Taskwarrior <font name='M'>sync.encryption_secret</font> · key passphrases")],
    [p("<b>If a machine dies:</b> <font name='M'>~/sys_org/home_hub/recovery.org</font> — also on the drive in "
       "<font name='M'>backups/RECOVERY/</font>, readable without restic.")],
], [(CW / 2) - 4 * mm], zebra=False)
box = Table([[left, right]], colWidths=[CW / 2, CW / 2])
box.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
                         ("RIGHTPADDING", (0, 0), (-1, -1), 4)]))
story += [band("9 · Keys, secrets, and where to look", ALL), Spacer(1, 3), box]


def on_page(cv, doc):
    cv.saveState()
    cv.setFont("S", 7); cv.setFillColor(MUTED)
    cv.drawString(M, 7 * mm, "home_hub cheat sheet · " + __import__("datetime").date.today().isoformat())
    cv.drawRightString(W - M, 7 * mm, f"{doc.page} / 3")
    cv.setStrokeColor(RULE); cv.setLineWidth(0.5); cv.line(M, 10 * mm, W - M, 10 * mm)
    cv.restoreState()


OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "cheatsheet.pdf")
doc = BaseDocTemplate(OUT, pagesize=A4,
                      leftMargin=M, rightMargin=M, topMargin=M, bottomMargin=13 * mm,
                      title="Home hub — routine cheat sheet", author="hlima")
frame = Frame(M, 12 * mm, W - 2 * M, H - M - 12 * mm, id="f", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
doc.addPageTemplates([PageTemplate(id="p", frames=[frame], onPage=on_page)])
doc.build(story)
print("written:", os.path.abspath(OUT))
