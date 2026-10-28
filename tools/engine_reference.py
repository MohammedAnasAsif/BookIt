"""Prepares the end-to-end engine test (runs in CI).

* downloads the NLLB ONNX model files the app uses into $NLLB_MODEL_DIR
* writes reference translations made with ONNX Runtime in Python
  (greedy decoding, same model files) -> $NLLB_REFERENCE
* writes broad tokenizer fixtures from a public-domain book -> $NLLB_BROAD_FIXTURES
"""
import json
import os
import re
import shutil
import urllib.request

import numpy as np
import onnxruntime as ort
from huggingface_hub import hf_hub_download
from transformers import AutoTokenizer

REPO = "Xenova/nllb-200-distilled-600M"
MODEL_DIR = os.environ["NLLB_MODEL_DIR"]
os.makedirs(MODEL_DIR, exist_ok=True)

FILES = {
    "tokenizer.json": "tokenizer.json",
    "onnx/encoder_model_quantized.onnx": "encoder_model_quantized.onnx",
    "onnx/decoder_model_quantized.onnx": "decoder_model_quantized.onnx",
    "onnx/decoder_with_past_model_quantized.onnx": "decoder_with_past_model_quantized.onnx",
}
for remote, local in FILES.items():
    dest = os.path.join(MODEL_DIR, local)
    if not os.path.exists(dest):
        shutil.copy(hf_hub_download(REPO, remote), dest)
    print(local, os.path.getsize(dest))

tok = AutoTokenizer.from_pretrained(REPO)
enc = ort.InferenceSession(os.path.join(MODEL_DIR, "encoder_model_quantized.onnx"), providers=["CPUExecutionProvider"])
d1 = ort.InferenceSession(os.path.join(MODEL_DIR, "decoder_model_quantized.onnx"), providers=["CPUExecutionProvider"])
d2 = ort.InferenceSession(os.path.join(MODEL_DIR, "decoder_with_past_model_quantized.onnx"), providers=["CPUExecutionProvider"])
d1_out = [o.name for o in d1.get_outputs()]
d2_in = [i.name for i in d2.get_inputs()]
d2_out = [o.name for o in d2.get_outputs()]


def prepare(s):
    s = re.sub("[“”„‟«»″]", '"', s)
    s = re.sub("[‘’‚‛′]", "'", s)
    s = re.sub(r"\s*[—―]\s*", " - ", s)
    return s.replace("–", "-")


def translate(text, src, tgt, limit=None):
    tok.src_lang = src
    ids = tok(prepare(text))["input_ids"]
    x = np.array([ids], dtype=np.int64)
    mask = np.ones_like(x)
    hidden = enc.run(None, {"input_ids": x, "attention_mask": mask})[0]
    tgt_id = tok.convert_tokens_to_ids(tgt)
    limit = limit or max(24, min(400, len(ids) * 2 + 16))
    res = d1.run(None, {"input_ids": np.array([[2, tgt_id]], dtype=np.int64),
                        "encoder_attention_mask": mask, "encoder_hidden_states": hidden})
    past = dict(zip([n.replace("present", "past_key_values") for n in d1_out[1:]], res[1:]))
    out = []
    nxt = int(np.argmax(res[0][0, -1]))
    while nxt != 2 and len(out) < limit:
        out.append(nxt)
        feeds = {"input_ids": np.array([[nxt]], dtype=np.int64), "encoder_attention_mask": mask}
        if "encoder_hidden_states" in d2_in:
            feeds["encoder_hidden_states"] = hidden
        for n in d2_in:
            if n.startswith("past_key_values"):
                feeds[n] = past[n]
        r = d2.run(None, feeds)
        for n, v in zip(d2_out[1:], r[1:]):
            past[n.replace("present", "past_key_values")] = v
        nxt = int(np.argmax(r[0][0, -1]))
    return tok.decode(out, skip_special_tokens=True)


# Original test sentences written for BookIt.
SENTENCES = [
    "The old man was dreaming about the lions on the beach.",
    "She opened the window and the smell of rain filled the little room.",
    "“Where are you going so early?” asked her mother.",
    "The train was late, so we sat on the platform and talked for hours.",
    "Every evening the children gathered under the banyan tree to hear stories.",
    "He had never seen the sea before, and it frightened him a little.",
    "Books are the quietest and most constant of friends.",
    "The letter arrived on a Tuesday — three weeks after it was posted.",
]
refs = []
for tgt in ["hin_Deva", "tam_Taml", "ben_Beng", "fra_Latn"]:
    for s in SENTENCES:
        refs.append({"src": "eng_Latn", "tgt": tgt, "text": s, "translation": translate(s, "eng_Latn", tgt)})
        print(tgt, "|", refs[-1]["translation"])
with open(os.environ["NLLB_REFERENCE"], "w", encoding="utf-8") as f:
    json.dump(refs, f, ensure_ascii=False, indent=1)

# Broad tokenizer fixtures from a public-domain novel (Project Gutenberg #1342).
broad = []
try:
    raw = urllib.request.urlopen("https://www.gutenberg.org/cache/epub/1342/pg1342.txt", timeout=60).read().decode("utf-8")
    start = raw.find("*** START OF")
    body = raw[start:] if start >= 0 else raw
    paras = [" ".join(p.split()) for p in re.split(r"\n\s*\n", body)]
    paras = [p for p in paras if 30 < len(p) < 700][:600]
    tok.src_lang = "eng_Latn"
    broad = [{"text": p, "ids": tok(p)["input_ids"], "lang": "eng_Latn"} for p in paras]
except Exception as e:  # noqa
    print("broad fixtures failed:", e)
# A few non-English lines too.
for lang, s in [("hin_Deva", "मैं आज बाज़ार जा रहा हूँ और शाम को लौटूँगा।"), ("tam_Taml", "நான் புத்தகம் படிக்கிறேன்."),
                ("fra_Latn", "Il était une fois une petite maison au bord de la rivière.")]:
    tok.src_lang = lang
    broad.append({"text": s, "ids": tok(s)["input_ids"], "lang": lang})
with open(os.environ["NLLB_BROAD_FIXTURES"], "w", encoding="utf-8") as f:
    json.dump(broad, f, ensure_ascii=False)
print("broad fixtures:", len(broad))
