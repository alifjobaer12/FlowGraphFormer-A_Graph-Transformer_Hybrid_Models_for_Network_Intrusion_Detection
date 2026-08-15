# FlowGraphFormer usage manual

## Before running anything

Keep original data outside generated report/model folders and launch Jupyter
from the project root. A fresh checkout can contain only notebooks and
documentation; the notebooks create their output directories as needed.

Back up important data independently. `00A_Label_Converter.ipynb` and
`00B_Dataset_Harmonizer.ipynb` intentionally rewrite `dataset/raw/*.csv`, though
both create dedicated backups before doing so.

## 00A — Label converter

Use this only when a release stores labels as numbers such as 0/1 while the
attack type is encoded in each filename. Review its scan report before accepting
filename-derived labels. Set `dry_run=True` first for unfamiliar releases.

Inputs: `dataset/raw/*.csv`

Outputs: rewritten raw CSVs, backups in `dataset/raw_backup_prelabel/`, and
reports in `reports/label_conversion/`.

## 00B — Dataset harmonizer

Use this when raw CSVs have inconsistent column names, feature sets, or attack
labels. Inspect fuzzy matches and unmapped columns in the report. A fuzzy match
is a hypothesis, not proof that two features have the same semantics.

Inputs: `dataset/raw/*.csv`

Outputs: harmonized raw CSVs, backups in `dataset/raw_backup/`, and reports in
`reports/harmonization/`.

## 01 — Preprocessing

Run all cells in order. Important configuration includes the random seed,
feature-selection toggle, number of selected features, split ratios, class
balancing, and visualization sample sizes.

The split must occur before training-only resampling. Validation and test data
must remain real and untouched. The notebook exports:

- baseline NumPy arrays;
- pre-SMOTE CSV reference splits;
- scaled Parquet features;
- a SMOTE-balanced Parquet training pair;
- label encoder, scaler, sampler, PCA, and UMAP artifacts;
- metadata, manifest, tables, plots, and validation results.

The final validation cell checks file existence and samples Parquet output for
NaNs. A passing sample check is useful but is not a proof that every row is
finite; use the earlier full data-quality checks as the authoritative audit.

## 02 — Baseline models

Run the setup, imports, and data-loading cells first. The notebook reads the
NumPy files under `dataset/processed/final/`.

`TRAIN_FRACTION=1.0` is the reproducible full-run default. Set it below 1 only
for a smoke test; validation and test sets are never reduced by that cell.

The optional libraries cell reports whether XGBoost, LightGBM, CatBoost, and
TabNet are installed. Do not run a corresponding training cell when its package
is unavailable. CatBoost and TabNet execution cells are disabled by default.
Enable them deliberately if they are part of the baseline experiment.

Run the comparison and visualization cells only after at least one model has
completed. Outputs are written beneath `reports/baseline_ml/`,
`results/baseline_ml/`, and `models/baseline_ml/`.

## 03 — Advanced modeling

Run setup through the fixed-fold and helper cells before any individual model.
Model training cells are otherwise independent and may be run in any order.

Key controls:

| Setting | Meaning |
|---|---|
| `TRAIN_*`, `VAL_*`, `TEST_*` | Files loaded from `dataset/processed/final/`. Feature/label row counts must match. |
| `N_FOLDS` | Number of shared CV folds. All compared models must use the same saved folds. |
| `CV_ON` | Use training only or training plus validation as the CV pool. |
| `USE_SMOTE_PER_FOLD` | Apply SMOTE inside each training fold. Keep false when the selected training files are already SMOTE-balanced. |
| `USE_FULL_DATASET` | Use every available row. |
| `SMOKE_TEST` | Use a small stratified sample for an end-to-end dry run. |
| `DEVICE_PREFERENCE` | `auto`, `cuda`, `xpu`, `mps`, or `cpu`. |
| `HYBRID_*` | Select automatic/manual members and stacking/soft-voting strategy. |
| `XAI_*` | Select models and sample sizes for explainability runs. |

Recommended workflow:

1. Set `USE_FULL_DATASET=False`, `SMOKE_TEST=True`, small epoch/patience values,
   and five folds. Run the complete path once.
2. Correct every failed validation or missing artifact.
3. Set `USE_FULL_DATASET=True`, `SMOKE_TEST=False`, and final hyperparameters.
4. Run the desired individual models.
5. Generate the comparison table, then build the hybrid.
6. Re-run comparison so the hybrid is included.
7. Run statistical tests, XAI, and the final checklist.

### TabPFN authentication

Set `TABPFN_TOKEN` outside notebook source. In Colab, add a Secret named
`TABPFN_TOKEN` and grant notebook access. Locally, set the environment variable
before launching Jupyter. Do not print the token.

**Setting `TABPFN_TOKEN` on Windows (local runs):**

1. Get an API key from https://ux.priorlabs.ai/account (register/accept the
   license first if you haven't).
2. Set it once as a permanent user-level environment variable in PowerShell:

   ```powershell
   [System.Environment]::SetEnvironmentVariable("TABPFN_TOKEN", "your-key-here", "User")
   ```

3. Close and reopen PowerShell (or restart VS Code / your terminal) so the new
   variable is picked up. Verify it's set with:

   ```powershell
   echo $env:TABPFN_TOKEN
   ```

4. If a token was ever pasted into a notebook cell, a Markdown cell, or a
   chat/AI tool, revoke it at https://ux.priorlabs.ai/account and issue a new
   one — removing it from the current file does not remove copies from
   backups, notebook history, cloud revisions, or shared conversations.

`03_Big_Modeling.ipynb`'s TabPFN cell reads `os.environ.get("TABPFN_TOKEN", "")`
automatically; nothing else needs to change in the notebook itself. Setting it
as a User-level variable means it stays set across reboots and future terminal
sessions, so this is a one-time step, not a per-run step.

TabPFN input rows/features are capped by its controls. Record those caps when
reporting results because they make its training regime different from models
that consume the full feature and row set.

## 04 — ROC curves

This notebook loads validation/test splits and saved models, performs inference,
and writes per-model and combined ROC figures under
`reports/modeling/figures/roc_avg/`.

Its feature filenames, TabPFN feature cap, architecture definitions, and hybrid
member order must match the run that created the model artifacts. For stacking,
member order is part of the meta-model input contract and filename.

Models with missing or incompatible artifacts are skipped and recorded in the
summary rather than stopping the entire notebook. A CUDA-origin TabPFN pickle
has a CPU-loading fallback, but cross-version pickles can still be incompatible;
use the same Python/package versions for training and inference when possible.

## Running the full pipeline unattended (Windows, overnight)

`run_all_notebooks.ps1` (kept alongside the notebooks) executes every notebook
in order via `jupyter nbconvert`, saves outputs in place below each cell, skips
any cell that errors instead of stopping, and logs progress to
`logs/run_all_notebooks_<timestamp>.log`. Use this to leave the whole pipeline
running overnight without babysitting it.

### One-time setup

1. Make sure `TABPFN_TOKEN` is set as described above (User-level env var).
2. Open the script and edit these two lines near the top to match your machine:

   ```powershell
   $ProjectRoot = "C:\path\to\FlowGraphFormer"
   $VenvPath    = "C:\path\to\FlowGraphFormer\venv"
   ```

3. Check `$Notebooks` (the run order) and `$RequiredFolders` match your actual
   project layout. `$RequiredPackages` should match what the notebooks import;
   `pandas` and `pyarrow` are intentionally pinned to versions known to work
   together — do not let one of them auto-upgrade independently later.
4. If your venv doesn't have Jupyter yet, the script installs it automatically
   on first run; you don't need to `pip install` anything by hand first.

### Running it

Open PowerShell in the project folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_all_notebooks.ps1
```

The script will, in order:

1. Create any missing project folders (`dataset/processed`, `reports/tables`,
   etc.) so a notebook can't fail on a missing directory partway through the
   night.
2. Check every package in `$RequiredPackages` and install anything missing.
3. Register the venv as a named Jupyter kernel and force every notebook to use
   it, avoiding "kernel not found" errors from old Colab metadata.
4. Set `PYTORCH_CUDA_ALLOC_CONF` and `TABPFN_MAX_BATCHED_TEST_ROWS` so
   GPU-memory-heavy cells (especially TabPFN) behave on a local GPU that is
   smaller than the Colab T4.
5. Run each notebook top to bottom with `--execute --allow-errors`: outputs
   (including any error traceback) are saved directly under each cell in the
   `.ipynb` file itself, and a cell that errors is skipped rather than halting
   the run.
6. Write a per-notebook and overall summary (status, duration) to the log file.

Leave the PC on and check the log file in the morning. Open each `.ipynb`
afterward — a skipped cell's traceback is visible right there in that cell's
output, so you can see exactly what needs fixing without re-running anything.

### Notes specific to this pipeline

- The script does not distinguish "ran cleanly" from "ran with some cells
  skipped due to errors" in its exit-code check — always open the notebooks
  and scan for red traceback output, don't rely on the log alone to mean
  success.
- `03_Big_Modeling.ipynb` is the long pole: with `SMOKE_TEST=False` and
  `USE_FULL_DATASET=True`, TabPFN and the attention-based models can each take
  hours locally without a CUDA-class GPU. Consider running a `SMOKE_TEST=True`
  pass first (per the recommended workflow above) before committing a full
  night to the real run.
- If a notebook depends on files written by an earlier one (per the run-order
  table in `README.md`), keep `$Notebooks` in that same order — the script
  runs them strictly sequentially, so an earlier failure that skips a
  file-writing cell will cascade into `FileNotFoundError`s in later notebooks.

## Interpretation rules

- Keep the test set isolated until final evaluation; do not select models or
  tune thresholds on test results.
- Use macro metrics for class-balanced interpretation and weighted metrics only
  when deployment prevalence is the intended weighting.
- A high score on synthetic/oversampled training data is not evidence of
  generalization.
- Paired tests are meaningful only when models use identical folds or identical
  test instances, as appropriate.
- Report skipped models, failed folds, row/feature caps, and simplified model
  implementations as limitations.

## Troubleshooting

`FileNotFoundError`: confirm preprocessing completed and notebook launch
directory is the project root.

Mismatched row counts: do not pair a pre-SMOTE feature file with a post-SMOTE
label file. Use the pairs listed in preprocessing's `manifest.csv`.

CUDA out of memory: reduce neural batch size or ROC inference batch size, then
restart the kernel to clear fragmented allocations.

Missing optional model: install the package in the current kernel, restart if
required, and rerun imports. Record package versions for reproducibility.

NaN/Inf failure: return to preprocessing and inspect the full data-quality and
scaling reports. Do not replace invalid logits as a substitute for repairing
invalid input or unstable training.

