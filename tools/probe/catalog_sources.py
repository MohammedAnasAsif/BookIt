"""Times catalog sources and saves samples (bounded, no retries)."""
import json, os, time, urllib.request
OUT = os.path.join(os.path.dirname(__file__), "out"); os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "BookIt catalog probe (https://github.com/MohammedAnasAsif/BookIt)"}
res = {}
for name, url, keep in [
    ("epub_noimages", "https://www.gutenberg.org/ebooks/1342.epub.noimages", 0),
    ("epub3_images", "https://www.gutenberg.org/ebooks/1342.epub3.images", 0),
    ("cache_epub", "https://www.gutenberg.org/cache/epub/1342/pg1342.epub", 0),
    ("cache_epub_images", "https://www.gutenberg.org/cache/epub/1342/pg1342-images.epub", 0),
    ("cache_epub3_images", "https://www.gutenberg.org/cache/epub/1342/pg1342-images-3.epub", 0),
    ("pglaf_cache_epub", "https://gutenberg.pglaf.org/cache/epub/1342/pg1342.epub", 0),
    ("aleph_cache_epub", "https://aleph.gutenberg.org/cache/epub/1342/pg1342.epub", 0),
    ("cover_medium", "https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg", 0),
    ("cover_small", "https://www.gutenberg.org/cache/epub/1342/pg1342.cover.small.jpg", 0),
    ("pglaf_cover", "https://gutenberg.pglaf.org/cache/epub/1342/pg1342.cover.medium.jpg", 0),
    ("aleph_cover", "https://aleph.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg", 0),
    ("cover_37106", "https://www.gutenberg.org/cache/epub/37106/pg37106.cover.medium.jpg", 0),
    ("noimages_37106", "https://www.gutenberg.org/ebooks/37106.epub.noimages", 0),
    ("noimages_7164", "https://www.gutenberg.org/ebooks/7164.epub.noimages", 0),
]:
    t0 = time.time()
    try:
        data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=25).read()
        res[name] = {"s": round(time.time() - t0, 2), "bytes": len(data)}
        if keep:
            open(os.path.join(OUT, name + ".txt"), "wb").write(data[:keep])
    except Exception as e:
        res[name] = {"s": round(time.time() - t0, 2), "error": str(e)[:200]}
print(json.dumps(res, indent=1))
json.dump(res, open(os.path.join(OUT, "catalog_timings.json"), "w"), indent=1)
