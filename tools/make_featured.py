"""Builds app/assets/featured.json: a curated list of popular public-domain
classics with verified Project Gutenberg ids, so the app can show them
instantly (and offline) without waiting for the online catalog.

Also measures the online catalog services and saves samples for development.
Runs in CI (needs internet)."""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

UA = {"User-Agent": "BookIt featured list builder (https://github.com/MohammedAnasAsif/BookIt)"}
OUT = sys.argv[1] if len(sys.argv) > 1 else "app/assets/featured.json"
LOGDIR = sys.argv[2] if len(sys.argv) > 2 else "catalog-probe"
os.makedirs(LOGDIR, exist_ok=True)

# (search terms, required author word, shelf)
WANTED = [
    ("Gitanjali", "tagore", "india"),
    ("The Home and the World", "tagore", "india"),
    ("The Gardener", "tagore", "india"),
    ("Stray Birds", "tagore", "india"),
    ("The Hungry Stones", "tagore", "india"),
    ("Kim", "kipling", "india"),
    ("The Jungle Book", "kipling", "india"),
    ("Just So Stories", "kipling", "children"),
    ("Indian Fairy Tales", "jacobs", "india"),
    ("Tales of the Punjab", "steel", "india"),
    ("The Song Celestial", "arnold", "india"),
    ("The Light of Asia", "arnold", "india"),
    ("Pride and Prejudice", "austen", "classics"),
    ("Alice's Adventures in Wonderland", "carroll", "children"),
    ("The Adventures of Sherlock Holmes", "doyle", "classics"),
    ("Frankenstein", "shelley", "classics"),
    ("Little Women", "alcott", "classics"),
    ("Treasure Island", "stevenson", "children"),
    ("Around the World in Eighty Days", "verne", "classics"),
    ("The Time Machine", "wells", "classics"),
    ("Peter Pan", "barrie", "children"),
    ("The Secret Garden", "burnett", "children"),
    ("Anne of Green Gables", "montgomery", "children"),
    ("Black Beauty", "sewell", "children"),
    ("Heidi", "spyri", "children"),
    ("Grimms' Fairy Tales", "grimm", "children"),
    ("Fairy Tales of Hans Christian Andersen", "andersen", "children"),
    ("Aesop's Fables", "aesop", "children"),
    ("The Arabian Nights", "", "classics"),
    ("Robinson Crusoe", "defoe", "classics"),
    ("Gulliver's Travels", "swift", "classics"),
    ("The Adventures of Tom Sawyer", "twain", "children"),
    ("Adventures of Huckleberry Finn", "twain", "classics"),
    ("A Christmas Carol", "dickens", "classics"),
    ("Oliver Twist", "dickens", "classics"),
    ("Great Expectations", "dickens", "classics"),
    ("Jane Eyre", "bront", "classics"),
    ("Wuthering Heights", "bront", "classics"),
    ("Dracula", "stoker", "classics"),
    ("The Wonderful Wizard of Oz", "baum", "children"),
    ("The Call of the Wild", "london", "classics"),
    ("The Count of Monte Cristo", "dumas", "classics"),
    ("Les Misérables", "hugo", "classics"),
    ("War and Peace", "tolstoy", "classics"),
    ("Crime and Punishment", "dostoyevsky", "classics"),
    ("The Adventures of Pinocchio", "collodi", "children"),
    ("The Wind in the Willows", "grahame", "children"),
    ("Siddhartha", "hesse", "classics"),
    ("The Prophet", "gibran", "classics"),
    ("Meditations", "aurelius", "classics"),
    ("The Art of War", "sun", "classics"),
    ("The Picture of Dorian Gray", "wilde", "classics"),
    ("Romeo and Juliet", "shakespeare", "classics"),
    ("Moby Dick", "melville", "classics"),
    ("The Odyssey", "homer", "classics"),
    ("Don Quixote", "cervantes", "classics"),
    ("The Three Musketeers", "dumas", "classics"),
    ("Twenty Thousand Leagues under the Sea", "verne", "classics"),
    ("The Happy Prince", "wilde", "children"),
    ("The Velveteen Rabbit", "bianco", "children"),
]


def get(url, timeout=60):
    t0 = time.time()
    req = urllib.request.Request(url, headers=UA)
    data = urllib.request.urlopen(req, timeout=timeout).read()
    return data, time.time() - t0


def gutendex(query):
    url = "https://gutendex.com/books?" + urllib.parse.urlencode({"search": query})
    for attempt in range(4):
        try:
            data, _ = get(url, 90)
            return json.loads(data)["results"]
        except Exception as e:  # noqa
            print("retry", query, e, file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    return []


# ---- measure catalog services
timings = {}
for name, url in [
    ("gutendex_popular", "https://gutendex.com/books?languages=en"),
    ("gutendex_search", "https://gutendex.com/books?search=austen"),
    ("gutendex_topic", "https://gutendex.com/books?topic=children&languages=en"),
    ("gutenberg_opds_search", "https://www.gutenberg.org/ebooks/search.opds/?query=austen"),
    ("gutenberg_opds_popular", "https://www.gutenberg.org/ebooks/search.opds/?sort_order=downloads"),
    ("gutenberg_opds_book", "https://www.gutenberg.org/ebooks/1342.opds"),
    ("community_catalog", "https://raw.githubusercontent.com/MohammedAnasAsif/BookIt/main/catalog/editions.json"),
]:
    try:
        data, secs = get(url, 90)
        timings[name] = {"seconds": round(secs, 2), "bytes": len(data)}
        with open(os.path.join(LOGDIR, name + ".txt"), "wb") as f:
            f.write(data[:60000])
    except Exception as e:  # noqa
        timings[name] = {"error": str(e)}
print(json.dumps(timings, indent=1))
with open(os.path.join(LOGDIR, "timings.json"), "w") as f:
    json.dump(timings, f, indent=1)

# ---- resolve the featured list
featured = []
for title, author, shelf in WANTED:
    results = gutendex(title)
    best = None
    for r in results:
        names = " ".join(a.get("name", "") for a in r.get("authors", [])).lower()
        if author and author not in names:
            continue
        if not any(k.startswith("application/epub") for k in r.get("formats", {})):
            continue
        if best is None or r.get("download_count", 0) > best.get("download_count", 0):
            best = r
    if best is None:
        print("NOT FOUND:", title, file=sys.stderr)
        continue
    authors = [a["name"] for a in best.get("authors", [])]
    featured.append({
        "id": best["id"],
        "title": best["title"],
        "authors": authors,
        "languages": best.get("languages", []),
        "shelf": shelf,
        "downloads": best.get("download_count", 0),
    })
    print(f"{best['id']:>6}  {best['title'][:60]}  ({', '.join(authors)[:40]})")
    time.sleep(1)

with open(OUT, "w", encoding="utf-8") as f:
    json.dump({"format": "bookit-featured", "version": 1, "books": featured}, f, ensure_ascii=False, indent=1)
print(f"{len(featured)} featured books -> {OUT}")
