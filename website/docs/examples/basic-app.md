---
title: Basic App Example
---

Path: `example/basic_app`

This example is the fastest way to inspect core API usage in a console app.

## Run

```bash
cd example/basic_app
dart pub get
dart run

# Embedding example
dart run bin/llamadart_embedding_example.dart -i "hello world" -i "rag"

# Embedding parity-oriented run (CPU + explicit knobs)
dart run bin/llamadart_embedding_example.dart \
  --cpu --ctx-size 2048 --threads 12 --threads-batch 12 \
  --batch-size 2048 --ubatch-size 2048 --max-seq 2 \
  -i "hello world" -i "semantic search"
```

## Test

```bash
cd example/basic_app
dart test
```

## What it demonstrates

- Engine initialization.
- Model loading and teardown.
- Streaming token generation.
- Single and batched embeddings.
- Small-footprint project setup for non-Flutter Dart apps.
