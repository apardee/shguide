# Adapter pipeline

shguide is designed so that — once prompting + tools hit a quality ceiling — a LoRA adapter can be slotted into the same `QueryEngine`. This doc captures the workflow without committing the Python project until we actually have data worth training on.

## When to consider an adapter

Look at the eval reports. If `generable-with-tools` has been at or below the same coverage rate for two macOS releases, and the failure modes are consistent (hallucinated flags, wrong leading binary), an adapter is probably worth the effort. Until then, prompts and tools are cheaper and don't carry an OS-version-pinning tax.

## Hardware & entitlements

- **Training:** Mac with Apple silicon and ≥32 GB unified memory, or a Linux box with a GPU. Python 3.11+.
- **Production deployment:** the [`com.apple.developer.foundation-model-adapter`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.foundation-model-adapter) entitlement is required to ship an adapter to end users. Apple Developer Program account holder must request it.
- **Adapter ↔ OS coupling:** an adapter is pinned to one specific system-model version. We will need one `.fmadapter` per macOS release we support.

## Training data

Use the eval dataset as the seed. The Apple toolkit expects JSONL with `{role, content}` chat pairs:

```jsonl
{"messages":[
  {"role":"user","content":"find large files in this subdirectory sorted by size"},
  {"role":"assistant","content":"{\"suggestions\":[{\"command\":\"find . -type f -size +500M\",\"explanation\":\"List files larger than 500 MB.\",\"risk\":\"safe\"}]}"}
]}
```

The assistant content is the JSON form of `SuggestionList`. We generate it by:

1. Running each `Datasets/eval_v1.jsonl` row through the current best strategy.
2. Picking the suggestion that matches one of `expected_any_of`. If none match, hand-write the answer.
3. Human-review every example before committing — adapters memorise these.

Target 500–1000 high-quality examples for the first adapter. Diversity matters more than volume; spread across all tool families.

## Toolkit

The official Apple Foundation Models adapter toolkit is a Python project (not yet in this repo). Expected workflow:

```bash
git clone <apple toolkit URL>      # add the URL once Apple publishes it stably
cd foundation-models-adapter
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python -m examples.train_adapter \
  --train-data ../shguide/Adapters/train.jsonl \
  --eval-data  ../shguide/Adapters/valid.jsonl \
  --epochs 5 --learning-rate 1e-3 --batch-size 4 \
  --checkpoint-dir ../shguide/Adapters/checkpoints/

python -m examples.export_adapter \
  --checkpoint ../shguide/Adapters/checkpoints/best \
  --output ../shguide/Adapters/shguide-macos26.4.fmadapter
```

`.fmadapter` is the deployable package format. ~160 MB.

## Loading in shguide

Once we have an adapter:

```swift
let adapter = try SystemLanguageModel.Adapter(fileURL: adapterURL)
let model = SystemLanguageModel(adapter: adapter)
let session = LanguageModelSession(model: model, tools: tools, instructions: instructions)
```

Expose this through `FoundationModelsEngine` via an `adapter: URL?` init parameter; add a `Strategy.adapter` case to `Sources/ShguideEval/RunCommand.swift` for A/B testing.

## Distribution

A 160 MB adapter is too large for the Homebrew bottle. Use [Background Assets](https://developer.apple.com/documentation/backgroundassets) to fetch the adapter on first run; cache under `~/Library/Application Support/shguide/adapters/<os>/`.

## Not yet committed

When we are ready, this folder will gain:

- `Adapters/train.jsonl` and `Adapters/valid.jsonl` (gitignored if large)
- `Adapters/scripts/jsonl_from_eval.py` — converts the eval dataset into chat-pair training rows
- A `make adapter` target that runs the conversion + training end to end
