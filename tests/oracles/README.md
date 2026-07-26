# Executable Vector Oracles

`vector_oracles.py` independently recomputes every expected result in all nine JSONL vector suites from active DSL policies. `tools/verify_vectors.py` streams all 595,000 cases and fails on any semantic mismatch, duplicate ID, malformed case, missing suite or unexpected suite.
