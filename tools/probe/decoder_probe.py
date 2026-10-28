"""Find a decoding setup for the NLLB ONNX decoder that works with the
ONNX Runtime version bundled in the app (1.15.1)."""
import json
import os
import time
import traceback

import numpy as np
import onnxruntime as ort
from huggingface_hub import hf_hub_download
from transformers import AutoTokenizer

REPO = "Xenova/nllb-200-distilled-600M"
OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)
report = {"ort_version": ort.__version__}

tok = AutoTokenizer.from_pretrained(REPO)
enc = ort.InferenceSession(hf_hub_download(REPO, "onnx/encoder_model_quantized.onnx"), providers=["CPUExecutionProvider"])
merged = ort.InferenceSession(hf_hub_download(REPO, "onnx/decoder_model_merged_quantized.onnx"), providers=["CPUExecutionProvider"])

text = "The old man was dreaming about the lions on the beach."
tok.src_lang = "eng_Latn"
src = tok(text)["input_ids"]
tgt = tok.convert_tokens_to_ids("hin_Deva")
ids = np.array([src], dtype=np.int64)
mask = np.ones_like(ids)
hidden = enc.run(None, {"input_ids": ids, "attention_mask": mask})[0]
report["hidden_shape"] = list(hidden.shape)
past_names = [i.name for i in merged.get_inputs() if i.name.startswith("past_key_values")]
out_names = [o.name for o in merged.get_outputs()]


def run_merged(first_past_len, first_ids, enc_past_mode):
    past = {}
    for n in past_names:
        if ".encoder." in n and enc_past_mode == "enc_len":
            past[n] = np.zeros((1, 16, ids.shape[1], 64), dtype=np.float32)
        else:
            past[n] = np.zeros((1, 16, first_past_len, 64), dtype=np.float32)
    step = first_ids
    out = list(first_ids)
    use_cache = False
    for _ in range(60):
        feeds = {"input_ids": np.array([step], dtype=np.int64), "encoder_attention_mask": mask,
                 "encoder_hidden_states": hidden, "use_cache_branch": np.array([use_cache], dtype=bool)}
        feeds.update(past)
        res = merged.run(None, feeds)
        nxt = int(np.argmax(res[0][0, -1]))
        pres = dict(zip(out_names[1:], res[1:]))
        past = {n: pres[n.replace("past_key_values", "present")] for n in past_names}
        use_cache = True
        out.append(nxt)
        step = [nxt]
        if nxt == 2:
            break
    return tok.decode(out, skip_special_tokens=True)


variants = {
    "merged_zero_past": (0, [2, tgt], "same"),
    "merged_one_past": (1, [2, tgt], "same"),
    "merged_zero_dec_enc_len": (0, [2, tgt], "enc_len"),
    "merged_single_start_token": (0, [2], "same"),
}
for name, (pl, first, mode) in variants.items():
    t0 = time.time()
    try:
        r = run_merged(pl, first, mode)
        report[name] = {"ok": True, "text": r, "s": round(time.time() - t0, 2)}
    except Exception as e:  # noqa
        report[name] = {"ok": False, "error": str(e)[:400]}

# Split decoders
try:
    d1 = ort.InferenceSession(hf_hub_download(REPO, "onnx/decoder_model_quantized.onnx"), providers=["CPUExecutionProvider"])
    d2 = ort.InferenceSession(hf_hub_download(REPO, "onnx/decoder_with_past_model_quantized.onnx"), providers=["CPUExecutionProvider"])
    report["d1_inputs"] = [i.name for i in d1.get_inputs()]
    report["d2_inputs"] = [i.name for i in d2.get_inputs()][:6]
    report["d2_outputs"] = [o.name for o in d2.get_outputs()][:6]
    t0 = time.time()
    res = d1.run(None, {"input_ids": np.array([[2, tgt]], dtype=np.int64), "encoder_attention_mask": mask, "encoder_hidden_states": hidden})
    names1 = [o.name for o in d1.get_outputs()]
    pres = dict(zip(names1[1:], res[1:]))
    out = [2, tgt, int(np.argmax(res[0][0, -1]))]
    d2_in = [i.name for i in d2.get_inputs()]
    d2_out = [o.name for o in d2.get_outputs()]
    for _ in range(60):
        feeds = {"input_ids": np.array([[out[-1]]], dtype=np.int64), "encoder_attention_mask": mask}
        if "encoder_hidden_states" in d2_in:
            feeds["encoder_hidden_states"] = hidden
        for n in d2_in:
            if n.startswith("past_key_values"):
                feeds[n] = pres[n.replace("past_key_values", "present")]
        r2 = d2.run(None, feeds)
        nxt = int(np.argmax(r2[0][0, -1]))
        new = dict(zip(d2_out[1:], r2[1:]))
        for k in list(pres.keys()):
            if k in new:
                pres[k] = new[k]
        out.append(nxt)
        if nxt == 2:
            break
    report["split"] = {"ok": True, "text": tok.decode(out, skip_special_tokens=True), "s": round(time.time() - t0, 2)}
except Exception as e:  # noqa
    report["split"] = {"ok": False, "error": traceback.format_exc()[-800:]}

# Reference
try:
    from transformers import AutoModelForSeq2SeqLM
    import torch
    m = AutoModelForSeq2SeqLM.from_pretrained("facebook/nllb-200-distilled-600M")
    with torch.no_grad():
        g = m.generate(**tok(text, return_tensors="pt"), forced_bos_token_id=tgt, num_beams=1, max_new_tokens=60)
    report["reference_pytorch_greedy"] = tok.decode(g[0], skip_special_tokens=True)
except Exception as e:  # noqa
    report["reference_pytorch_greedy"] = "skipped: " + str(e)[:200]

with open(os.path.join(OUT, "decoder_probe_%s.json" % ort.__version__), "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=1)
print(json.dumps(report, ensure_ascii=False, indent=1))
