"""Builds BookIt's "discover" shelves: catalog/discover.json (+ a bundled copy in
app/assets/discover.json). Runs weekly in CI (.github/workflows/discover.yml).

Shelves
  trending       What people are reading right now (Open Library's weekly
                 trending list) plus well-known recent bestsellers. Metadata
                 and covers only: these books are sold by their publishers, so
                 the app shows where to buy or borrow them.
  bestsellers    Hand-picked popular modern books (metadata only, as above).
  freeFiction    Modern novels their authors released under Creative Commons
                 licences that allow non-commercial sharing and translation.
                 Each licence is checked on the author's page; the EPUB is
                 mirrored to the `free-fiction` GitHub release.
  standardEbooks Carefully edited public-domain classics from Standard Ebooks
                 (list built from their public GitHub sources).
"""
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

UA = {"User-Agent": "BookIt discover builder (https://github.com/MohammedAnasAsif/BookIt)"}
REPO = os.environ.get("GITHUB_REPOSITORY", "MohammedAnasAsif/BookIt")
TOKEN = os.environ.get("GITHUB_TOKEN", "")
RELEASE_TAG = "free-fiction"
LOG = []


def log(*a):
    msg = " ".join(str(x) for x in a)
    LOG.append(msg)
    print(msg, file=sys.stderr, flush=True)


def get(url, timeout=60, headers=None, tries=2):
    h = dict(UA)
    if headers:
        h.update(headers)
    last = None
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=timeout) as r:
                return r.read()
        except Exception as e:  # noqa
            last = e
            time.sleep(2 * (i + 1))
    raise last


def get_json(url, **kw):
    return json.loads(get(url, **kw))


# ----------------------------------------------------------------- trending

SKIP_WORDS = re.compile(r"graphic novel|summary|workbook|study guide|analysis of|coloring book|journal", re.I)


def ol_doc(d, reason):
    if not d.get("cover_i") or not d.get("title") or SKIP_WORDS.search(d["title"]):
        return None
    authors = d.get("author_name") or []
    return {
        "key": d["key"],
        "title": d["title"],
        "author": ", ".join(authors[:2]),
        "year": d.get("first_publish_year"),
        "cover": d["cover_i"],
        "reason": reason,
    }


def trending():
    out, seen = [], set()
    for period in ("weekly", "monthly"):
        try:
            data = get_json(f"https://openlibrary.org/trending/{period}.json?limit=200", timeout=90)
        except Exception as e:  # noqa
            log("trending", period, "failed", e)
            continue
        for w in data.get("works", []):
            year = w.get("first_publish_year") or 0
            if year < 1990:
                continue  # classics are already in the free library
            item = ol_doc(w, period)
            norm = re.sub(r"\W+", " ", (item or {}).get("title", "")).strip().lower()
            if item and item["key"] not in seen and norm not in seen:
                seen.update({item["key"], norm})
                out.append(item)
    log("trending:", len(out))
    return out[:60]


# Popular recent books people ask for (metadata and covers only).
BESTSELLERS = [
    ("It Ends With Us", "Colleen Hoover"), ("It Starts With Us", "Colleen Hoover"),
    ("Verity", "Colleen Hoover"), ("Reminders of Him", "Colleen Hoover"),
    ("Killing Floor", "Lee Child"), ("Persuader", "Lee Child"), ("Bad Luck and Trouble", "Lee Child"),
    ("Fourth Wing", "Rebecca Yarros"), ("Iron Flame", "Rebecca Yarros"),
    ("The Housemaid", "Freida McFadden"), ("A Court of Thorns and Roses", "Sarah J. Maas"),
    ("The Silent Patient", "Alex Michaelides"), ("Where the Crawdads Sing", "Delia Owens"),
    ("The Seven Husbands of Evelyn Hugo", "Taylor Jenkins Reid"), ("Lessons in Chemistry", "Bonnie Garmus"),
    ("Project Hail Mary", "Andy Weir"), ("The Martian", "Andy Weir"), ("The Midnight Library", "Matt Haig"),
    ("Book Lovers", "Emily Henry"), ("The Love Hypothesis", "Ali Hazelwood"),
    ("Tomorrow, and Tomorrow, and Tomorrow", "Gabrielle Zevin"), ("Normal People", "Sally Rooney"),
    ("Gone Girl", "Gillian Flynn"), ("The Girl on the Train", "Paula Hawkins"),
    ("The Hunger Games", "Suzanne Collins"), ("The Alchemist", "Paulo Coelho"),
    ("The Kite Runner", "Khaled Hosseini"),
    ("The Da Vinci Code", "Dan Brown"), ("The Thursday Murder Club", "Richard Osman"),
    ("Educated", "Tara Westover"), ("Atomic Habits", "James Clear"), ("Sapiens", "Yuval Noah Harari"),
    ("The Psychology of Money", "Morgan Housel"), ("Ikigai", "Héctor García"),
    ("The White Tiger", "Aravind Adiga"), ("The God of Small Things", "Arundhati Roy"),
    ("Five Point Someone", "Chetan Bhagat"), ("The Immortals of Meluha", "Amish Tripathi"),
    ("An Unequal Defense", "Chad Zunker"), ("A Man Called Ove", "Fredrik Backman"),
]


def bestsellers():
    out = []
    fields = "key,title,author_name,cover_i,first_publish_year,edition_count"
    for title, author in BESTSELLERS:
        docs = []
        for params in ({"title": title, "author": author}, {"q": f"{title} {author}"}):
            q = urllib.parse.urlencode({**params, "limit": 10, "fields": fields})
            try:
                docs = get_json(f"https://openlibrary.org/search.json?{q}", timeout=60).get("docs", [])
            except Exception as e:  # noqa
                log("bestseller lookup failed", title, e)
                docs = []
            docs = [d for d in docs if d.get("cover_i") and not SKIP_WORDS.search(d.get("title", ""))]
            if docs:
                break
        if not docs:
            log("bestseller not found", title)
            continue
        want = re.sub(r"\W+", " ", title).strip().lower()
        best = max(docs, key=lambda d: (re.sub(r"\W+", " ", d.get("title", "")).strip().lower() == want,
                                        d.get("edition_count", 0)))
        item = ol_doc(best, "bestseller")
        if item:
            out.append(item)
        time.sleep(0.5)
    log("bestsellers:", len(out))
    return out


# ----------------------------------------------------------------- free modern fiction

ALLOWED = {"by", "by-sa", "by-nc", "by-nc-sa"}  # licences that allow translation
LICENCE_NAMES = {
    "by": "CC BY", "by-sa": "CC BY-SA", "by-nc": "CC BY-NC", "by-nc-sa": "CC BY-NC-SA",
}

# Candidates; each licence is verified on the source page before inclusion.
# Blurbs are BookIt's own one-line summaries.
FREE_FICTION = [
    {"id": "doctorow-little-brother", "title": "Little Brother", "author": "Cory Doctorow",
     "page": "https://craphound.com/littlebrother/download/", "genre": "Thriller · Young adult",
     "blurb": "A teenage hacker takes on a surveillance state after a terror attack on San Francisco."},
    {"id": "doctorow-homeland", "title": "Homeland", "author": "Cory Doctorow",
     "page": "https://craphound.com/homeland/download/", "genre": "Thriller · Young adult",
     "blurb": "The sequel to Little Brother: Marcus is handed secrets that could bring down the powerful."},
    {"id": "doctorow-down-and-out", "title": "Down and Out in the Magic Kingdom", "author": "Cory Doctorow",
     "page": "https://craphound.com/down/download/", "genre": "Science fiction",
     "blurb": "In a future without death or money, a feud breaks out over who runs a theme park."},
    {"id": "doctorow-makers", "title": "Makers", "author": "Cory Doctorow",
     "page": "https://craphound.com/makers/download/", "genre": "Science fiction",
     "blurb": "Two inventors in a junkyard start a movement that shakes up the whole economy."},
    {"id": "doctorow-for-the-win", "title": "For the Win", "author": "Cory Doctorow",
     "page": "https://craphound.com/ftw/download/", "genre": "Thriller · Young adult",
     "blurb": "Young gamers working in online-game sweatshops around the world fight back together."},
    {"id": "doctorow-pirate-cinema", "title": "Pirate Cinema", "author": "Cory Doctorow",
     "page": "https://craphound.com/pc/download/", "genre": "Young adult",
     "blurb": "A teenage film-maker in London runs away and joins a gang of remix artists."},
    {"id": "doctorow-eastern-standard-tribe", "title": "Eastern Standard Tribe", "author": "Cory Doctorow",
     "page": "https://craphound.com/est/download/", "genre": "Science fiction",
     "blurb": "A spy for an online tribe ends up on a rooftop deciding whether he's lost his mind."},
    {"id": "doctorow-someone-comes-to-town", "title": "Someone Comes to Town, Someone Leaves Town",
     "author": "Cory Doctorow", "page": "https://craphound.com/someone/download/", "genre": "Fantasy",
     "blurb": "A strange man with very strange family tries to build free wireless internet for his city."},
    {"id": "doctorow-overclocked", "title": "Overclocked", "author": "Cory Doctorow",
     "page": "https://craphound.com/overclocked/download/", "genre": "Short stories",
     "blurb": "Six stories about the near future, from robots to copyright wars."},
    {"id": "watts-blindsight", "title": "Blindsight", "author": "Peter Watts",
     "page": "https://www.rifters.com/real/Blindsight.htm", "html": True, "genre": "Science fiction",
     "blurb": "A crew of strange, modified humans makes first contact with an alien intelligence."},
    {"id": "watts-starfish", "title": "Starfish", "author": "Peter Watts",
     "page": "https://www.rifters.com/real/STARFISH.htm", "html": True, "genre": "Science fiction",
     "blurb": "Damaged people are sent to work at a power station on the deep ocean floor."},
    {"id": "watts-maelstrom", "title": "Maelstrom", "author": "Peter Watts",
     "page": "https://www.rifters.com/real/MAELSTROM.htm", "html": True, "genre": "Science fiction",
     "blurb": "Starfish continued: Lenie Clarke walks out of the sea into a world that wants her dead."},
]


def find_licence(text):
    m = re.search(r"creativecommons\.org/licenses/([a-z\-]+)/(\d\.\d)", text, re.I)
    if m:
        return m.group(1).lower(), m.group(2)
    m = re.search(r"Creative\s+Commons\s+(Attribution(?:[\s\-]+(?:Non[\s\-]?Commercial|Share[\s\-]?Alike|No[\s\-]?Deriv\w*))*)",
                  text, re.I)
    if m:
        words = m.group(1).lower()
        code = "by"
        if "noncommercial" in words.replace("-", "").replace(" ", ""):
            code += "-nc"
        if "noderiv" in words.replace("-", "").replace(" ", ""):
            code += "-nd"
        if "sharealike" in words.replace("-", "").replace(" ", ""):
            code += "-sa"
        return code, ""
    return None, None


def is_epub(data):
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
        return z.read("mimetype").strip() == b"application/epub+zip"
    except Exception:  # noqa
        return False


def epub_cover(data):
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
        names = [n for n in z.namelist() if re.search(r"\.(jpe?g|png)$", n, re.I)]
        named = [n for n in names if "cover" in n.lower()]
        pick = (named or sorted(names, key=lambda n: -z.getinfo(n).file_size))[:1]
        if pick and z.getinfo(pick[0]).file_size > 5000:
            return z.read(pick[0]), pick[0].rsplit(".", 1)[-1].lower()
    except Exception:  # noqa
        pass
    return None, None


def html_to_epub(html_bytes, title, author, licence_text):
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "book.html")
        out = os.path.join(d, "book.epub")
        open(src, "wb").write(html_bytes)
        meta = os.path.join(d, "meta.yaml")
        open(meta, "w").write(f"---\ntitle: \"{title}\"\ncreator:\n- role: author\n  text: \"{author}\"\n"
                              f"rights: \"{licence_text}\"\nlang: en\n...\n")
        subprocess.run(["pandoc", src, "-f", "html", "-o", out, "--metadata-file", meta,
                        "--split-level=1", "--toc"], check=True, capture_output=True, timeout=300)
        return open(out, "rb").read()


def gh(*args):
    return subprocess.run(["gh", *args, "--repo", REPO], capture_output=True, text=True)


def free_fiction():
    if TOKEN:
        if gh("release", "view", RELEASE_TAG).returncode != 0:
            r = gh("release", "create", RELEASE_TAG, "--title", "Free modern fiction (mirrored)", "--prerelease",
                   "--notes", "Novels their authors released under Creative Commons licences, mirrored for BookIt. "
                              "Each book's licence and source are listed in catalog/discover.json.")
            log("create release:", r.returncode, r.stderr[:200])
    out = []
    work = tempfile.mkdtemp()
    for c in FREE_FICTION:
        try:
            page = get(c["page"], timeout=90)
            text = page.decode("utf-8", "replace")
            code, ver = find_licence(text)
            if code not in ALLOWED:
                log("skip (licence not suitable):", c["title"], code)
                continue
            licence = LICENCE_NAMES[code] + (f" {ver}" if ver else "")
            licence_url = f"https://creativecommons.org/licenses/{code}/{ver or '4.0'}/"
            if c.get("html"):
                data = html_to_epub(page, c["title"], c["author"], f"{licence} - {c['author']}")
                source = c["page"]
            else:
                links = re.findall(r'href="([^"]+\.epub)"', text)
                links = [urllib.parse.urljoin(c["page"], l) for l in links]
                links = [l for l in links if "Cory_Doctorow_-_" in l and not re.search(r"(DANSK|_[A-Z]{2,}_|segmented)", l)]
                if not links:
                    log("skip (no epub link):", c["title"])
                    continue
                source = min(links, key=len)
                data = get(source, timeout=120)
            if not is_epub(data):
                log("skip (not an epub):", c["title"])
                continue
            fname = f"{c['id']}.epub"
            path = os.path.join(work, fname)
            open(path, "wb").write(data)
            cover_url = None
            img, ext = epub_cover(data)
            assets = [path]
            if img:
                cpath = os.path.join(work, f"{c['id']}.{ext}")
                open(cpath, "wb").write(img)
                assets.append(cpath)
                cover_url = f"https://github.com/{REPO}/releases/download/{RELEASE_TAG}/{c['id']}.{ext}"
            if TOKEN:
                r = gh("release", "upload", RELEASE_TAG, *assets, "--clobber")
                if r.returncode != 0:
                    log("upload failed:", c["title"], r.stderr[:200])
                    continue
            out.append({
                "id": c["id"], "title": c["title"], "author": c["author"], "genre": c["genre"],
                "blurb": c["blurb"], "licence": licence, "licenceUrl": licence_url,
                "sourcePage": c["page"], "sourceFile": source,
                "epub": f"https://github.com/{REPO}/releases/download/{RELEASE_TAG}/{fname}",
                "cover": cover_url, "size": len(data),
            })
            log("free fiction ok:", c["title"], licence, len(data), "cover" if img else "no cover")
        except Exception as e:  # noqa
            log("skip (error):", c["title"], e)
    return out


# ----------------------------------------------------------------- Standard Ebooks

def standard_ebooks():
    out = []
    headers = {"Authorization": f"Bearer {TOKEN}"} if TOKEN else {}
    for page in range(1, 40):
        try:
            repos = get_json(f"https://api.github.com/orgs/standardebooks/repos?per_page=100&page={page}",
                             headers=headers, timeout=60)
        except Exception as e:  # noqa
            log("standard ebooks page failed", page, e)
            break
        if not repos:
            break
        for r in repos:
            desc = r.get("description") or ""
            m = re.match(r"Epub source for the Standard Ebooks edition of (.+), by (.+?)\.?$", desc)
            if not m or r.get("archived") or r.get("private"):
                continue
            name = r["name"]
            path = name.replace("_", "/")
            out.append({
                "id": name,
                "title": m.group(1),
                "author": re.sub(r"\. Translated by.*$|, translated by.*$", "", m.group(2)),
                "stars": r.get("stargazers_count", 0),
                "page": f"https://standardebooks.org/ebooks/{path}",
                "epub": f"https://standardebooks.org/ebooks/{path}/downloads/{name}.epub?source=download",
                "cover": f"https://raw.githubusercontent.com/standardebooks/{name}/{r.get('default_branch', 'master')}/images/cover.jpg",
            })
    out.sort(key=lambda b: (-b["stars"], b["title"]))
    log("standard ebooks:", len(out))
    # Measure a few cover sizes for the log.
    for b in out[:3]:
        try:
            log("  cover size", b["id"], len(get(b["cover"], timeout=60)))
        except Exception as e:  # noqa
            log("  cover failed", b["id"], e)
    return out


def main():
    assets_dir = sys.argv[1] if len(sys.argv) > 1 else "app/assets"
    previous = {}
    try:
        previous = json.load(open("catalog/discover.json"))
    except Exception:  # noqa
        pass
    data = {"format": "bookit-discover", "version": 1, "built": time.strftime("%Y-%m-%d")}
    for key, fn in [("trending", trending), ("bestsellers", bestsellers),
                    ("freeFiction", free_fiction), ("standardEbooks", standard_ebooks)]:
        try:
            value = fn()
        except Exception as e:  # noqa
            log(key, "failed", e)
            value = []
        # Never replace a good shelf with an empty one because a site was down.
        data[key] = value if value else previous.get(key, [])
    text = json.dumps(data, ensure_ascii=False, indent=1)
    os.makedirs("catalog", exist_ok=True)
    open("catalog/discover.json", "w", encoding="utf-8").write(text)
    open(os.path.join(assets_dir, "discover.json"), "w", encoding="utf-8").write(text)
    os.makedirs("discover-log", exist_ok=True)
    open("discover-log/log.txt", "w").write("\n".join(LOG))
    log({k: len(v) for k, v in data.items() if isinstance(v, list)})


if __name__ == "__main__":
    main()
