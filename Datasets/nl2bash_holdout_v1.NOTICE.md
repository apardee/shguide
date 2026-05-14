# nl2bash_holdout_v1.jsonl — attribution

`Datasets/nl2bash_holdout_v1.jsonl` is a stratified sample drawn from the
nl2bash dataset: https://github.com/TellinaTool/nl2bash (commit on master at
time of sampling).

It is used here as a held-out evaluation set for shguide's forward-mode prompt
variants. The `goal` field is `all.nl` line N; `canonical_command` is `all.cm`
line N, lightly filtered (see `Sources/ShguideEval/SampleNL2BashCommand.swift`
for the exact rules) and stratified by first-binary command head.

The nl2bash dataset is MIT-licensed. The original license is reproduced below.

---

MIT License

Copyright (c) 2020 NL2Bash dataset

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
