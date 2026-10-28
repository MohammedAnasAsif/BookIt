"""Probe the NLLB ONNX export used by the BookIt app and write reference data.

Runs in CI (needs internet). Produces:
  out/nllb_files.json        file list + sizes of the Hugging Face repo
  out/tokenizer_summary.json structure of tokenizer.json (model type, normalizer, ...)
  out/onnx_io.json           input/output names, shapes and types of the ONNX graphs
  out/token_fixtures.json    reference token ids for test sentences (HF tokenizer)
  out/onnx_greedy.json       translations produced by a plain ONNX greedy loop
                             (the exact algorithm the Dart engine implements)
"""
import json
import os
import re
import sys
import time

import numpy as np
import onnxruntime as ort
from huggingface_hub import HfApi, hf_hub_download
from transformers import AutoTokenizer

REPO = os.environ.get("NLLB_REPO", "Xenova/nllb-200-distilled-600M")
OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)


def dump(name, obj):
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)


api = HfApi()
info = api.model_info(REPO, files_metadata=True)
files = [{"name": s.rfilename, "size": s.size} for s in info.siblings]
dump("nllb_files.json", files)
print("files", json.dumps(files, indent=1))

tok_path = hf_hub_download(REPO, "tokenizer.json")
with open(tok_path, encoding="utf-8") as f:
    tj = json.load(f)
model = tj["model"]
summary = {
    "model_type": model.get("type"),
    "model_keys": list(model.keys()),
    "unk_id": model.get("unk_id"),
    "byte_fallback": model.get("byte_fallback"),
    "vocab_len": len(model.get("vocab", [])),
    "vocab_head": model.get("vocab", [])[:12] if isinstance(model.get("vocab"), list) else list(model.get("vocab", {}).items())[:12],
    "merges_len": len(model.get("merges", []) or []),
    "merges_head": (model.get("merges") or [])[:5],
    "normalizer": tj.get("normalizer") and {k: (v if k != "precompiled_charsmap" else "<%d chars>" % len(v or "")) for k, v in tj["normalizer"].items()},
    "normalizer_list": [
        {k: (v if k != "precompiled_charsmap" else "<%d chars>" % len(v or "")) for k, v in n.items()}
        for n in (tj.get("normalizer") or {}).get("normalizers", [tj.get("normalizer") or {}])
    ],
    "lang_codes": [t["content"] for t in tj.get("added_tokens", []) if re.match(r"^[a-z]{3}_[A-Z][a-z]{3}$", t["content"])],
    "pre_tokenizer": tj.get("pre_tokenizer"),
    "post_processor": tj.get("post_processor"),
    "decoder": tj.get("decoder"),
    "added_tokens_len": len(tj.get("added_tokens", [])),
    "added_tokens_head": tj.get("added_tokens", [])[:8],
    "added_tokens_tail": tj.get("added_tokens", [])[-4:],
}
for name in ["config.json", "generation_config.json", "tokenizer_config.json", "special_tokens_map.json"]:
    try:
        with open(hf_hub_download(REPO, name), encoding="utf-8") as f:
            summary[name] = json.load(f)
    except Exception as e:  # noqa
        summary[name] = str(e)
for k in ["tokenizer_config.json"]:
    if isinstance(summary.get(k), dict):
        summary[k].pop("added_tokens_decoder", None)
dump("tokenizer_summary.json", summary)
print(json.dumps({k: v for k, v in summary.items() if k != "config.json"}, indent=1, ensure_ascii=False)[:6000])

tok = AutoTokenizer.from_pretrained(REPO)
sentences = {
    "eng_Latn": [
        "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
        "“Well,” said Mr. Bennet — smiling — “that's 3,500 pounds a year!”",
        "Hello   world.\tTabs and  double  spaces…",
        "Café naïve résumé coöperate — ½ ﬁ ① Ｆｕｌｌｗｉｄｔｈ",
        "Chapter IV",
        "",
    ],
    "hin_Deva": ["मैं आज बाज़ार जा रहा हूँ।", "क्या आप हिंदी बोलते हैं?"],
    "tam_Taml": ["நான் புத்தகம் படிக்கிறேன்."],
    "fra_Latn": ["Je ne sais pas ce que c'est, l'œuvre d'Hugo."],
    "jpn_Jpan": ["今日はいい天気ですね。"],
    "urd_Arab": ["میں کتاب پڑھ رہا ہوں۔"],
}
fixtures = []
for lang, items in sentences.items():
    tok.src_lang = lang
    for s in items:
        ids = tok(s)["input_ids"]
        fixtures.append({
            "lang": lang,
            "text": s,
            "ids": ids,
            "pieces": tok.convert_ids_to_tokens(ids),
        })
dump("token_fixtures.json", {"lang_ids": {l: tok.convert_tokens_to_ids(l) for l in ["eng_Latn", "hin_Deva", "tam_Taml", "fra_Latn", "zho_Hans", "urd_Arab"]}, "items": fixtures})

# Broad tokenizer fixtures from a public-domain novel (Project Gutenberg #1342)
import urllib.request
try:
    raw = urllib.request.urlopen("https://www.gutenberg.org/cache/epub/1342/pg1342.txt", timeout=60).read().decode("utf-8")
    body = raw[raw.find("Chapter I."):][:400000]
    paras = [" ".join(p.split()) for p in body.split("\n\n")]
    paras = [p for p in paras if 20 < len(p) < 600][:400]
    tok.src_lang = "eng_Latn"
    broad = [{"text": p, "ids": tok(p)["input_ids"]} for p in paras]
    dump("broad_fixtures_eng.json", broad)
except Exception as e:
    print("broad fixtures failed", e)

# Decode fixtures: ids -> text
dec = []
for ids in [[256047, 9038, 2], tok("नमस्ते दुनिया, यह एक परीक्षण है।")["input_ids"]]:
    dec.append({"ids": ids, "text": tok.decode(ids, skip_special_tokens=True)})
dump("decode_fixtures.json", dec)

# ---- ONNX graphs ----
enc_path = hf_hub_download(REPO, "onnx/encoder_model_quantized.onnx")
dec_path = hf_hub_download(REPO, "onnx/decoder_model_merged_quantized.onnx")
io = {}
so = ort.SessionOptions()
enc = ort.InferenceSession(enc_path, so, providers=["CPUExecutionProvider"])
decs = ort.InferenceSession(dec_path, so, providers=["CPUExecutionProvider"])
for name, sess in [("encoder", enc), ("decoder_merged", decs)]:
    io[name] = {
        "inputs": [[i.name, i.shape, i.type] for i in sess.get_inputs()],
        "outputs": [[o.name, o.shape, o.type] for o in sess.get_outputs()],
    }
dump("onnx_io.json", io)


def greedy(text, src, tgt, max_len=200):
    tok.src_lang = src
    ids = tok(text)["input_ids"]
    input_ids = np.array([ids], dtype=np.int64)
    mask = np.ones_like(input_ids)
    hidden = enc.run(None, {"input_ids": input_ids, "attention_mask": mask})[0]
    names = [i.name for i in decs.get_inputs()]
    past_names = [n for n in names if n.startswith("past_key_values")]
    out_names = [o.name for o in decs.get_outputs()]
    heads = 16
    past = {n: np.zeros((1, heads, 0, 64), dtype=np.float32) for n in past_names}
    tgt_id = tok.convert_tokens_to_ids(tgt)
    out = [2, tgt_id]
    step_input = out[:]
    use_cache = False
    t0 = time.time()
    for _ in range(max_len):
        feeds = {
            "input_ids": np.array([step_input], dtype=np.int64),
            "encoder_attention_mask": mask,
            "encoder_hidden_states": hidden,
            "use_cache_branch": np.array([use_cache], dtype=bool),
        }
        feeds.update(past)
        res = decs.run(None, feeds)
        logits = res[0]
        nxt = int(np.argmax(logits[0, -1]))
        presents = dict(zip(out_names[1:], res[1:]))
        past = {n: presents[n.replace("past_key_values", "present")] for n in past_names}
        use_cache = True
        out.append(nxt)
        step_input = [nxt]
        if nxt == 2:
            break
    return {
        "src": src, "tgt": tgt, "text": text, "src_ids": ids, "out_ids": out,
        "translation": tok.decode(out, skip_special_tokens=True),
        "seconds": round(time.time() - t0, 2),
    }


results = [
    greedy(sentences["eng_Latn"][0], "eng_Latn", "hin_Deva"),
    greedy(sentences["eng_Latn"][0], "eng_Latn", "tam_Taml"),
    greedy(sentences["eng_Latn"][1], "eng_Latn", "fra_Latn"),
    greedy("The old man was dreaming about the lions.", "eng_Latn", "ben_Beng"),
    greedy(sentences["hin_Deva"][0], "hin_Deva", "eng_Latn"),
]
dump("onnx_greedy.json", results)
print(json.dumps(results, ensure_ascii=False, indent=1))
print("OK")
sys.exit(0)
