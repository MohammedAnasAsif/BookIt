#!/usr/bin/env python3
"""Translate a public-domain book into a BookIt edition (.bookit file).

Editions made with this tool can be added to the community library so every
reader gets the translation instantly, without translating on their phone.
It runs on a regular PC (a GPU makes it much faster) and can use larger, more
accurate models than the app:

  * NLLB-200 (any of 200 languages)       --engine nllb  [default]
  * IndicTrans2 (22 Indian languages)     --engine indictrans2

Examples
  python tools/translate_book.py --gutenberg 1342 --to tam_Taml
  python tools/translate_book.py --epub mybook.epub --to hin_Deva --engine indictrans2
  python tools/translate_book.py --gutenberg 11 --to ben_Beng --model facebook/nllb-200-distilled-1.3B

Install:  pip install torch transformers sentencepiece beautifulsoup4 lxml
          (for IndicTrans2 also: pip install IndicTransToolkit)

Only translate books that are in the public domain (e.g. Project Gutenberg)
or that you have the rights to share.
"""
import argparse
import warnings
import base64
import datetime as dt
import gzip
import io
import json
import os
import posixpath
import re
import sys
import urllib.parse
import urllib.request
import zipfile

from bs4 import BeautifulSoup, XMLParsedAsHTMLWarning

warnings.filterwarnings("ignore", category=XMLParsedAsHTMLWarning)

UA = "BookIt translate_book.py (https://github.com/MohammedAnasAsif/BookIt)"

# --------------------------------------------------------------------------- EPUB -> BookIt content

BLOCK_TAGS = {"p", "div", "section", "article", "header", "footer", "aside", "main", "nav", "blockquote", "pre",
              "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "dl", "dt", "dd", "table", "thead", "tbody",
              "tfoot", "tr", "td", "th", "figure", "figcaption", "hr", "body", "center", "address", "hgroup"}
SKIP_TAGS = {"head", "script", "style", "svg", "math", "img", "image", "audio", "video", "object"}


def has_letters(text):
    return any(ch.isalpha() for ch in text)


def clean(text):
    lines = [re.sub(r"[ \t\r\f ]+", " ", l).strip() for l in text.split("\n")]
    return "\n".join(l for l in lines if l).strip()


class ContentBuilder:
    def __init__(self):
        self.chapters, self.title, self.blocks = [], None, []

    def start(self, title):
        self.flush()
        self.title = title

    def add(self, kind, text, no_translate=False, pg=False):
        b = {"k": kind, "t": text}
        if pg:
            b["pg"] = 1  # Project Gutenberg header/licence, left out of editions
        if no_translate or not has_letters(text):
            b["n"] = 1
        self.blocks.append(b)

    def flush(self):
        if self.blocks:
            title = self.title or next((b["t"] for b in self.blocks if b["k"] in ("h1", "h2", "h3")),
                                       f"Section {len(self.chapters) + 1}")
            self.chapters.append({"title": title[:80], "blocks": self.blocks})
        self.blocks, self.title = [], None


def walk(el, out, anchors, ctx="p", boiler=False):
    tag = (el.name or "").lower()
    if tag in SKIP_TAGS:
        return
    ident, cls = el.get("id", ""), " ".join(el.get("class", []))
    if ident in ("pg-header", "pg-footer") or "pg-boilerplate" in cls:
        boiler = True
    if tag == "hr":
        out.add("hr", "", True)
        return
    has_block_children = any(getattr(c, "name", None) in BLOCK_TAGS for c in el.children)
    if has_block_children or tag == "body":
        if ident in anchors:
            out.start(anchors[ident])
        child_ctx = "q" if tag == "blockquote" else ctx
        inline = []
        for c in el.children:
            name = getattr(c, "name", None)
            if name in BLOCK_TAGS:
                t = clean("".join(inline))
                inline = []
                if t:
                    out.add(child_ctx, t, boiler, pg=boiler)
                walk(c, out, anchors, child_ctx, boiler)
            elif name:
                inline.append(inline_text(c))
            else:
                inline.append(str(c))
        t = clean("".join(inline))
        if t:
            out.add(child_ctx, t, boiler, pg=boiler)
        return
    ids = [ident] + [d.get("id") for d in el.find_all(True) if d.get("id")]
    for i in ids:
        if i in anchors:
            out.start(anchors[i])
            break
    if tag == "pre":
        t = el.get_text().rstrip()
        if t.strip():
            out.add("pre", t, boiler, pg=boiler)
        return
    t = clean(inline_text(el))
    if not t:
        return
    kind = {"h1": "h1", "h2": "h1", "h3": "h2", "h4": "h3", "h5": "h3", "h6": "h3",
            "li": "li", "dd": "li", "dt": "li"}.get(tag, ctx)
    out.add(kind, t, boiler, pg=boiler)


def inline_text(el):
    parts = []
    for c in el.children:
        name = getattr(c, "name", None)
        if name is None:
            parts.append(str(c))
        elif name in SKIP_TAGS or any(x in " ".join(c.get("class", [])) for x in ("pagenum", "pageno")):
            continue
        elif name == "br":
            parts.append("\n")
        else:
            parts.append(inline_text(c))
    return "".join(parts)


def parse_epub(data):
    z = zipfile.ZipFile(io.BytesIO(data))
    read = lambda p: z.read(urllib.parse.unquote(p)).decode("utf-8", "replace")
    container = BeautifulSoup(read("META-INF/container.xml"), "xml")
    opf_path = container.find("rootfile")["full-path"]
    base = posixpath.dirname(opf_path)
    opf = BeautifulSoup(read(opf_path), "xml")
    resolve = lambda href: posixpath.normpath(posixpath.join(base, href.split("#")[0]))
    meta = lambda n: (opf.find(n).get_text(strip=True) if opf.find(n) else "")
    manifest = {i["id"]: i for i in opf.find_all("item")}
    spine = [manifest[r["idref"]] for r in opf.find_all("itemref") if r.get("idref") in manifest]

    toc = {}
    nav = next((i for i in manifest.values() if "nav" in (i.get("properties") or "").split()), None)
    if nav is not None:
        doc = BeautifulSoup(read(resolve(nav["href"])), "lxml")
        nav_dir = posixpath.dirname(resolve(nav["href"]))
        for a in doc.select("nav a[href]"):
            target = posixpath.normpath(posixpath.join(nav_dir, a["href"]))
            f, _, frag = target.partition("#")
            toc.setdefault(f, {}).setdefault(frag, " ".join(a.get_text().split()))
    out = ContentBuilder()
    for item in spine:
        if "html" not in item.get("media-type", ""):
            continue
        path = resolve(item["href"])
        anchors = toc.get(path, {})
        if "" in anchors:
            out.start(anchors[""])
        soup = BeautifulSoup(read(path), "lxml")
        body = soup.body or soup
        walk(body, out, {k: v for k, v in anchors.items() if k})
    out.flush()

    cover = None
    cover_item = next((i for i in manifest.values() if "cover-image" in (i.get("properties") or "")), None)
    meta_cover = opf.find("meta", attrs={"name": "cover"})
    if cover_item is None and meta_cover is not None:
        cover_item = manifest.get(meta_cover.get("content"))
    if cover_item is not None and cover_item.get("media-type", "").startswith("image/"):
        cover = (z.read(resolve(cover_item["href"])), cover_item["href"].rsplit(".", 1)[-1])
    # Project Gutenberg's header and licence text (marked in the HTML) is left
    # out of editions: the public-domain book may be shared without it.
    chapters = []
    for c in out.chapters:
        blocks = [b for b in c["blocks"] if not b.pop("pg", None)]
        if any(b["t"].strip() for b in blocks):
            title = c["title"]
            if "gutenberg" in title.lower():
                title = next((b["t"] for b in blocks if b["k"] in ("h1", "h2", "h3")), meta("title") or title)[:80]
            chapters.append({"title": title, "blocks": blocks})
    out.chapters = chapters
    content = {"format": "bookit-content", "version": 1, "title": meta("title") or "Untitled",
               "author": ", ".join(c.get_text(strip=True) for c in opf.find_all("creator")),
               "language": meta("language"), "chapters": out.chapters}
    return content, cover


# --------------------------------------------------------------------------- sentence handling

END = re.compile(r"(?<=[.!?।॥。])[\"'’”)\]]*\s+")
ABBR = re.compile(r"\b(Mr|Mrs|Ms|Dr|St|Sr|Jr|Prof|Rev|Gen|Col|Capt|Lt|Mt|vs|etc|No|Vol)\.$")


def split_sentences(text):
    parts, start = [], 0
    for m in END.finditer(text):
        piece = text[start:m.end()].strip()
        if ABBR.search(piece):
            continue
        parts.append(piece)
        start = m.end()
    if text[start:].strip():
        parts.append(text[start:].strip())
    merged = []
    for p in parts:
        if merged and len(p) < 12:
            merged[-1] += " " + p
        else:
            merged.append(p)
    return merged


def prepare(s):
    s = re.sub("[“”„‟«»]", '"', s)
    s = re.sub("[‘’‚‛]", "'", s)
    s = re.sub(r"\s*[—―]\s*", " - ", s)
    return s.replace("–", "-")


# --------------------------------------------------------------------------- engines

class NllbEngine:
    def __init__(self, model, src, tgt, device, beams=4):
        import torch
        from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
        self.torch = torch
        self.beams = beams
        torch.set_num_threads(max(1, os.cpu_count() or 1))
        self.tok = AutoTokenizer.from_pretrained(model, src_lang=src)
        self.model = AutoModelForSeq2SeqLM.from_pretrained(model).to(device).eval()
        if device == "cuda":
            self.model = self.model.half()
        self.device, self.tgt_id = device, self.tok.convert_tokens_to_ids(tgt)
        self.name = model.split("/")[-1]

    def translate(self, sentences):
        enc = self.tok([prepare(s) for s in sentences], return_tensors="pt", padding=True, truncation=True,
                       max_length=256).to(self.device)
        with self.torch.no_grad():
            out = self.model.generate(**enc, forced_bos_token_id=self.tgt_id, num_beams=self.beams,
                                      max_new_tokens=int(enc["input_ids"].shape[1] * 2 + 16))
        return self.tok.batch_decode(out, skip_special_tokens=True)


class IndicTrans2Engine:
    def __init__(self, model, src, tgt, device):
        import torch
        from IndicTransToolkit.processor import IndicProcessor
        from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
        model = model or ("ai4bharat/indictrans2-en-indic-1B" if src == "eng_Latn" else "ai4bharat/indictrans2-indic-en-1B")
        self.torch, self.src, self.tgt, self.device = torch, src, tgt, device
        self.ip = IndicProcessor(inference=True)
        self.tok = AutoTokenizer.from_pretrained(model, trust_remote_code=True)
        self.model = AutoModelForSeq2SeqLM.from_pretrained(model, trust_remote_code=True).to(device).eval()
        self.name = model.split("/")[-1]

    def translate(self, sentences):
        batch = self.ip.preprocess_batch([prepare(s) for s in sentences], src_lang=self.src, tgt_lang=self.tgt)
        enc = self.tok(batch, truncation=True, padding="longest", return_tensors="pt").to(self.device)
        with self.torch.no_grad():
            out = self.model.generate(**enc, num_beams=4, max_length=256, use_cache=True)
        dec = self.tok.batch_decode(out, skip_special_tokens=True, clean_up_tokenization_spaces=True)
        return self.ip.postprocess_batch(dec, lang=self.tgt)


# --------------------------------------------------------------------------- main

def fetch(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=120).read()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src_group = ap.add_mutually_exclusive_group(required=True)
    src_group.add_argument("--gutenberg", type=int, help="Project Gutenberg book number")
    src_group.add_argument("--epub", help="path to a DRM-free EPUB you may share")
    ap.add_argument("--to", required=True, help="target language code, e.g. tam_Taml, hin_Deva, fra_Latn")
    ap.add_argument("--from", dest="src", default="eng_Latn", help="source language code (default eng_Latn)")
    ap.add_argument("--engine", choices=["nllb", "indictrans2"], default="nllb")
    ap.add_argument("--model", default=None, help="Hugging Face model id (default depends on engine)")
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--beams", type=int, default=4, help="beam size (1 = fastest)")
    ap.add_argument("--entry-out", default=None, help="also write the catalog entry to this JSON file")
    ap.add_argument("--out", default="editions")
    args = ap.parse_args()

    import torch
    device = "cuda" if torch.cuda.is_available() else "cpu"
    if args.gutenberg:
        data = fetch(f"https://www.gutenberg.org/cache/epub/{args.gutenberg}/pg{args.gutenberg}.epub")
    else:
        data = open(args.epub, "rb").read()
    content, cover = parse_epub(data)
    print(f"{content['title']} - {len(content['chapters'])} chapters: "
          + "; ".join(c["title"] for c in content["chapters"][:12]), file=sys.stderr)
    if not content["chapters"]:
        sys.exit("No text found in this book")

    if args.engine == "nllb":
        engine = NllbEngine(args.model or "facebook/nllb-200-distilled-600M", args.src, args.to, device, args.beams)
    else:
        engine = IndicTrans2Engine(args.model, args.src, args.to, device)

    os.makedirs(args.out, exist_ok=True)
    stem = re.sub(r"[^\w]+", "-", content["title"].lower()).strip("-")[:60] or "book"
    partial = os.path.join(args.out, f"{stem}.{args.to}.partial.json")
    chapters = json.load(open(partial)) if os.path.exists(partial) else \
        [[None] * len(c["blocks"]) for c in content["chapters"]]

    total = sum(1 for c in content["chapters"] for b in c["blocks"] if not b.get("n"))
    done = sum(1 for ci, c in enumerate(content["chapters"]) for bi, b in enumerate(c["blocks"])
               if not b.get("n") and chapters[ci][bi] is not None)
    for ci, ch in enumerate(content["chapters"]):
        units = []
        for bi, b in enumerate(ch["blocks"]):
            if chapters[ci][bi] is not None:
                continue
            if b.get("n"):
                chapters[ci][bi] = b["t"]
                continue
            sents = split_sentences(b["t"])
            for si, s in enumerate(sents):
                units.append((bi, si, len(sents), s))
        pieces = {}
        for i in range(0, len(units), args.batch):
            batch = units[i:i + args.batch]
            outs = engine.translate([u[3] for u in batch])
            for (bi, si, n, _), o in zip(batch, outs):
                pieces.setdefault(bi, [None] * n)[si] = o.strip()
                if all(p is not None for p in pieces[bi]):
                    joiner = "" if args.to.split("_")[1] in ("Hans", "Hant", "Jpan", "Thai") else " "
                    chapters[ci][bi] = joiner.join(pieces[bi])
                    done += 1
            print(f"\r{done}/{total} paragraphs", end="", file=sys.stderr)
        json.dump(chapters, open(partial, "w"), ensure_ascii=False)
    print(file=sys.stderr)

    now = dt.datetime.now(dt.timezone.utc).isoformat()
    edition = {"format": "bookit-edition", "version": 1, "sourceLang": args.src,
               "content": content,
               "translation": {"format": "bookit-translation", "version": 1, "lang": args.to,
                               "sourceLang": args.src, "engine": engine.name, "createdAt": now,
                               "updatedAt": now, "chapters": chapters}}
    if args.gutenberg:
        edition["gutenbergId"] = args.gutenberg
    if cover:
        edition["cover"], edition["coverExt"] = base64.b64encode(cover[0]).decode(), cover[1]
    path = os.path.join(args.out, f"{stem}.{args.to}.bookit")
    with gzip.open(path, "wb") as f:
        f.write(json.dumps(edition, ensure_ascii=False).encode("utf-8"))
    os.remove(partial)
    entry = {"id": f"{'pg' + str(args.gutenberg) if args.gutenberg else stem}-{args.to}", "title": content["title"],
             "author": content["author"], "lang": args.to, "sourceLang": args.src,
             "gutenbergId": args.gutenberg, "engine": engine.name, "size": os.path.getsize(path),
             "url": f"https://github.com/MohammedAnasAsif/BookIt/releases/download/editions/{os.path.basename(path)}",
             "cover": f"https://www.gutenberg.org/cache/epub/{args.gutenberg}/pg{args.gutenberg}.cover.medium.jpg"
             if args.gutenberg else None}
    if args.entry_out:
        json.dump(entry, open(args.entry_out, "w", encoding="utf-8"), ensure_ascii=False)
    print(f"Wrote {path}")
    print("Catalog entry for catalog/editions.json:")
    print(json.dumps(entry, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
