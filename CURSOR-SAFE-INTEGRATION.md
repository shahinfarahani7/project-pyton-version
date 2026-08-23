# Safe integration into an existing Cursor project

Do not extract this archive over the current project directory. Import it in an
isolated Git worktree, review the diff, run the gates, and merge only after the
integration commit is stable.

## 1. Protect the current project

Run these commands from the existing Cursor project:

```bash
git status
git add -A
git commit -m "checkpoint before EdgeMint integration"
git tag before-edgemint-final-import
```

If `git status` is not clean after the commit, stop and resolve or stash the
remaining files before continuing.

## 2. Create an isolated integration worktree

```bash
git worktree add ../edgemint-integration -b integrate/edgemint-final
mkdir -p ../edgemint-final-source
unzip EdgeMint-final-2026-08-22.zip -d ../edgemint-final-source
```

The archive has one top-level directory named `project-pyton-version`.

## 3. Copy into the isolated branch

The following intentionally does not use `--delete` and does not copy local
environment files:

```bash
rsync -a --itemize-changes \
  --exclude='.git/' \
  --exclude='.env' \
  --exclude='.env.*' \
  ../edgemint-final-source/project-pyton-version/ \
  ../edgemint-integration/
```

Review before committing:

```bash
cd ../edgemint-integration
git status --short
git diff --stat
git diff
```

Preserve the existing project's deployment secrets and environment values.
Only compare them manually with `.env.example` and `.env.docker.example`.

## 4. Validate and create the import commit

```bash
python tools/verify_task_catalog_infrastructure.py
python tools/run_56_task_protocol_load.py
python tools/verify_package.py
git add -p
git commit -m "integrate EdgeMint final package"
```

Use `git add -p` to exclude unrelated or unwanted changes. Run any existing
project-specific CI commands in this worktree as well.

## 5. Merge with conflicts contained

Return to the original project and merge without auto-committing:

```bash
cd -
git merge --no-commit --no-ff integrate/edgemint-final
git status
```

Resolve conflicts one file at a time, rerun tests, then commit. If the merge is
not acceptable, `git merge --abort` returns the project to the checkpoint.

## Recommended conflict ownership

- Keep the current project's values for `.env*`, deployment credentials, CI
  secrets, signing configuration, and machine-specific SDK paths.
- Prefer the EdgeMint package for worker lease bootstrap, task contracts,
  model adapters, task validators, and the new real-execution test runners.
- Manually merge shared API schemas, dependency manifests, Docker Compose,
  database migrations, and generated clients; do not choose an entire side
  without reviewing downstream effects.
- Regenerate generated clients after resolving the source OpenAPI/protobuf
  contracts instead of manually merging generated output when possible.

