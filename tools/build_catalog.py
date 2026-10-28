"""Builds BookIt's bundled catalog of Project Gutenberg books.

Outputs
  app/assets/catalog.json.gz   every Gutenberg text: id, title, author, languages,
                               shelf codes and popularity rank (for instant,
                               offline search in the app)
  app/assets/featured.json     curated shelves of well-known classics

Sources: Project Gutenberg's catalog CSV and its "most downloaded" OPDS feed.
Runs in CI (.github/workflows/catalog.yml)."""
import csv
import datetime as dt
import gzip
import io
import json
import re
import sys
import time
import urllib.request
from collections import Counter

UA = {"User-Agent": "BookIt catalog builder (https://github.com/MohammedAnasAsif/BookIt)"}
ASSETS = sys.argv[1] if len(sys.argv) > 1 else "app/assets"


def get(url, timeout=60):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout).read()


# Shelf codes used by the app (lib/data/catalog.dart).
SHELF_RULES = [
    ("C", ("children", "juvenile", "young adult")),
    ("Y", ("fairy tales", "folklore", "fables", "legends")),
    ("S", ("science fiction", "science-fiction", "fantasy")),
    ("M", ("crime", "mystery", "detective", "thriller")),
    ("P", ("poetry", "poems")),
    ("H", ("history",)),
    ("F", ("philosophy", "religio", "spiritual", "ethics")),
    ("A", ("adventure",)),
    ("R", ("romance", "love stories")),
    ("T", ("short stories",)),
    ("D", ("plays", "drama")),
    ("U", ("humor", "humour")),
    ("N", ("novels", "fiction")),
]
INDIA_WORDS = ("india", "hindu", "sanskrit", "bengal", "tamil", "punjab", "mahabharata", "ramayana", "veda",
               "upanishad", "bhagavad", "gita", "kashmir", "rajput", "mughal", "telugu", "marathi", "gujarat")


def clean_author(raw):
    out = []
    for a in raw.split(";"):
        a = re.sub(r"\[[^\]]*\]", "", a).strip()
        a = re.sub(r",\s*(-?\d{1,4}\??\s*(BCE|CE)?\s*-\s*-?\d{0,4}\??\s*(BCE|CE)?|\d{1,4}\??\s*(BCE)?|active.*|fl\..*)$", "",
                   a, flags=re.I).strip()
        a = re.sub(r"\s*\([^)]*\)", "", a).strip()
        parts = [p.strip() for p in a.split(",") if p.strip()]
        if len(parts) >= 2:
            a = f"{parts[1]} {parts[0]}"
        elif parts:
            a = parts[0]
        if a and a not in out:
            out.append(a)
    return ", ".join(out[:3])


def shelves(subjects, bookshelves, authors):
    text = f"{subjects} ; {bookshelves}".lower()
    codes = [code for code, words in SHELF_RULES if any(w in text for w in words)]
    if any(w in text for w in INDIA_WORDS) or "tagore" in authors.lower():
        codes.append("I")
    return "".join(dict.fromkeys(codes))


print("downloading catalog…", file=sys.stderr)
raw = get("https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv").decode("utf-8")
rows = list(csv.DictReader(io.StringIO(raw)))
print(len(rows), "rows", file=sys.stderr)

# Popularity from the "most downloaded" feed.
rank = {}
for page in range(80):
    start = page * 25 + 1
    try:
        xml = get(f"https://www.gutenberg.org/ebooks/search.opds/?sort_order=downloads&start_index={start}", 30).decode()
    except Exception as e:  # noqa
        print("popular feed stopped at", start, e, file=sys.stderr)
        break
    ids = [int(x) for x in re.findall(r"<id>https?://www\.gutenberg\.org/ebooks/(\d+)\.opds</id>", xml)]
    if not ids:
        break
    for i in ids:
        rank.setdefault(i, len(rank) + 1)
    time.sleep(0.3)
print(len(rank), "ranked books", file=sys.stderr)

books = []
cat_names = Counter()
for r in rows:
    if r.get("Type") != "Text":
        continue
    try:
        bid = int(r["Text#"])
    except ValueError:
        continue
    title = " ".join(r["Title"].split("\n")[0].split())[:160]
    if not title:
        continue
    authors = clean_author(r.get("Authors", ""))
    langs = r.get("Language", "").replace(" ", "").replace(";", ",")
    for c in re.findall(r"Category: ([^;]+)", r.get("Bookshelves", "")):
        cat_names[c.strip()] += 1
    books.append([bid, title, authors, langs, shelves(r.get("Subjects", ""), r.get("Bookshelves", ""), authors),
                  rank.get(bid, 0)])

books.sort(key=lambda b: (b[5] == 0, b[5] or 0, b[0]))
catalog = {"format": "bookit-catalog", "version": 1, "built": dt.date.today().isoformat(), "books": books}
data = json.dumps(catalog, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
with open(f"{ASSETS}/catalog.json.gz", "wb") as f:
    f.write(gzip.compress(data, 9, mtime=0))
print(f"{len(books)} books, {len(data) / 1e6:.1f} MB json, gz -> {ASSETS}/catalog.json.gz", file=sys.stderr)
print("categories:", cat_names.most_common(60), file=sys.stderr)
print("shelf counts:", Counter(c for b in books for c in b[4]), file=sys.stderr)

# Featured shelves
WANTED = [
    ("india", "Gitanjali", "tagore"), ("india", "The Home and the World", "tagore"),
    ("india", "The Gardener", "tagore"), ("india", "Stray Birds", "tagore"),
    ("india", "The Hungry Stones", "tagore"), ("india", "Kim", "kipling"),
    ("india", "The Jungle Book", "kipling"), ("india", "Indian Fairy Tales", "jacobs"),
    ("india", "Tales of the Punjab", "steel"), ("india", "The Song Celestial", "arnold"),
    ("india", "The Light of Asia", "arnold"), ("india", "Hindu Tales from the Sanskrit", ""),
    ("classics", "Pride and Prejudice", "austen"), ("classics", "The Adventures of Sherlock Holmes", "doyle"),
    ("classics", "Frankenstein", "shelley"), ("classics", "Little Women", "alcott"),
    ("classics", "Around the World in Eighty Days", "verne"), ("classics", "The Time Machine", "wells"),
    ("classics", "A Christmas Carol", "dickens"), ("classics", "Great Expectations", "dickens"),
    ("classics", "Jane Eyre", "bront"), ("classics", "Wuthering Heights", "bront"),
    ("classics", "Dracula", "stoker"), ("classics", "The Count of Monte Cristo", "dumas"),
    ("classics", "Les Misérables", "hugo"), ("classics", "War and Peace", "tolstoy"),
    ("classics", "Crime and Punishment", "dostoyevsky"), ("classics", "Siddhartha", "hesse"),
    ("classics", "The Prophet", "gibran"), ("classics", "Meditations", "aurelius"),
    ("classics", "The Art of War", "sun"), ("classics", "The Picture of Dorian Gray", "wilde"),
    ("classics", "Moby Dick", "melville"), ("classics", "Don Quixote", "cervantes"),
    ("classics", "The Life and Adventures of Robinson Crusoe", "defoe"), ("classics", "Gulliver's Travels into Several Remote Nations", "swift"),
    ("children", "Alice's Adventures in Wonderland", "carroll"), ("children", "Treasure Island", "stevenson"),
    ("children", "Peter Pan", "barrie"), ("children", "The Secret Garden", "burnett"),
    ("children", "Anne of Green Gables", "montgomery"), ("children", "Black Beauty", "sewell"),
    ("children", "Heidi", "spyri"), ("children", "Grimms' Fairy Tales", "grimm"),
    ("children", "Andersen's Fairy Tales", "andersen"), ("children", "Aesop's Fables", "aesop"),
    ("children", "The Adventures of Tom Sawyer", "twain"), ("children", "The Wonderful Wizard of Oz", "baum"),
    ("children", "The Adventures of Pinocchio", "collodi"), ("children", "The Wind in the Willows", "grahame"),
    ("children", "Just So Stories", "kipling"), ("children", "The Happy Prince", "wilde"),
    ("children", "The Velveteen Rabbit", "bianco"),
]
featured = []
for shelf, title, author in WANTED:
    t = title.lower()
    candidates = [b for b in books if b[1].lower().startswith(t) and (not author or author in b[2].lower())
                  and "en" in b[3].split(",")]
    if not candidates:
        print("NOT FOUND:", title, file=sys.stderr)
        continue
    # Prefer popular editions, then the exact title, then the oldest (original) upload.
    best = min(candidates, key=lambda b: (b[5] == 0, b[5] or 0, b[1].lower() != t, b[0]))
    featured.append({"id": best[0], "title": best[1], "authors": [best[2]] if best[2] else [],
                     "languages": best[3].split(","), "shelf": shelf, "rank": best[5]})
    print(f"{shelf:9} {best[0]:>6} #{best[5]:<5} {best[1][:50]} — {best[2][:30]}", file=sys.stderr)
with open(f"{ASSETS}/featured.json", "w", encoding="utf-8") as f:
    json.dump({"format": "bookit-featured", "version": 1, "books": featured}, f, ensure_ascii=False, indent=1)
print(len(featured), "featured", file=sys.stderr)
