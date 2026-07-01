#!/usr/bin/env python3
"""
Convert BAAI/bge-small-en-v1.5 to a Core ML model for knote (ARCHITECTURE.md §7).

Produces, under ~/Library/Application Support/knote/model/:
  - bge-small-en.mlpackage   (CLS-pooled, L2-normalized 384-d embedding)
  - vocab.txt                (WordPiece vocab for the in-app tokenizer)

Once these exist, knote uses Core ML BGE automatically instead of NLEmbedding.

Setup (heavy — torch + coremltools):
    python3 -m venv .venv && source .venv/bin/activate
    pip install torch "transformers==4.40.2" coremltools
    python scripts/convert_model.py

IMPORTANT — use Python 3.11 or 3.12, not 3.13.
    Newer transformers (5.x) emit a `new_ones` op that coremltools' TorchScript
    converter can't lower ("PyTorch convert function for op 'new_ones' not
    implemented"). The reliable fix is to pin transformers==4.40.2, whose BERT
    graph converts cleanly — but that pin needs a prebuilt `tokenizers` wheel,
    which does not exist for Python 3.13. So create the venv from 3.11/3.12:
        /opt/homebrew/bin/python3.12 -m venv .venv    # or pyenv, etc.
    On 3.13 the pin fails to build and the conversion errors out.

The app runs fine without this step (it falls back to Apple's NLEmbedding);
this only upgrades retrieval quality to the BGE model.
"""
import os
import pathlib
import torch
import numpy as np
import coremltools as ct
from transformers import AutoConfig, AutoModel, AutoTokenizer

MODEL_ID = "BAAI/bge-small-en-v1.5"
MAX_LEN = 512
OUT_DIR = pathlib.Path.home() / "Library/Application Support/knote/model"


class BGEEmbedder(torch.nn.Module):
    """Wraps BGE to emit a single CLS-pooled, L2-normalized sentence vector."""
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        # Pass explicit zero token_type_ids so the model doesn't build them
        # dynamically (that path uses ops coremltools can't trace).
        token_type_ids = torch.zeros_like(input_ids)
        out = self.model(input_ids=input_ids,
                         attention_mask=attention_mask,
                         token_type_ids=token_type_ids)
        cls = out.last_hidden_state[:, 0]            # CLS token
        return torch.nn.functional.normalize(cls, p=2, dim=1)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"› loading {MODEL_ID}")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    # torchscript=True (set on the config) disables the trace-hostile dynamic
    # mask/token_type paths in HF models; eager attention keeps the graph simple.
    # Together these make the graph convertible by coremltools.
    config = AutoConfig.from_pretrained(MODEL_ID)
    config.torchscript = True
    model = AutoModel.from_pretrained(
        MODEL_ID, config=config, attn_implementation="eager").eval()
    wrapper = BGEEmbedder(model).eval()

    example = tokenizer("hello world", return_tensors="pt",
                        padding="max_length", truncation=True, max_length=16)
    ids = example["input_ids"].to(torch.int32)
    mask = example["attention_mask"].to(torch.int32)

    print("› tracing")
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, (ids, mask))

    print("› converting to Core ML")
    seq = ct.RangeDim(lower_bound=1, upper_bound=MAX_LEN, default=16)
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, seq), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, seq), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="embeddings")],
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,
    )

    model_path = OUT_DIR / "bge-small-en.mlpackage"
    mlmodel.save(str(model_path))
    tokenizer.save_vocabulary(str(OUT_DIR))  # writes vocab.txt

    print(f"✓ wrote {model_path}")
    print(f"✓ wrote {OUT_DIR / 'vocab.txt'}")
    print("Restart knote — it will switch to Core ML BGE automatically.")
    print("Existing notes re-embed in the background under the new model id.")


if __name__ == "__main__":
    main()
