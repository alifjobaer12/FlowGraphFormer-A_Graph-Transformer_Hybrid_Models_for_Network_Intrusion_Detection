# FlowGraphFormer

FlowGraphFormer is a notebook-based research pipeline for network-intrusion
detection. It prepares the CIC-IDS2017 flow dataset, trains conventional baselines
and seven advanced models, evaluates a hybrid ensemble, produces statistical
tests and explainability reports, and draws validation/test ROC curves.

## Dataset: CIC-IDS2017

This project uses the
[CIC-IDS2017 intrusion-detection dataset](https://www.unb.ca/cic/datasets/ids-2017.html)
published by the Canadian Institute for Cybersecurity at the University of New
Brunswick. Download the dataset from the official page and select the
machine-learning CSV archive (`MachineLearningCSV.zip`). This pipeline consumes
the labeled flow CSV files produced with CICFlowMeter; it does not require the
full packet-capture (PCAP) archive.

CIC-IDS2017 contains benign traffic and common network attacks collected over
five days, from July 3 through July 7, 2017. The environment models the activity
of 25 users across protocols such as HTTP, HTTPS, FTP, SSH, and email. Monday
contains benign activity only, while attacks were conducted from Tuesday
through Friday. The CSV representation provides more than 80 flow features and
a label for each flow.

The attack scenarios include FTP and SSH brute force, several denial-of-service
attacks, Heartbleed, web attacks, infiltration, botnet traffic, port scanning,
and distributed denial of service (DDoS). The class distribution is strongly
imbalanced, so this project performs stratified splitting and applies sampling
only to training data. The untouched validation and test sets are used to avoid
inflated evaluation results.

### Expected files

After downloading and extracting the archive, copy these eight CSV files into
`dataset/raw/` without renaming them:

```text
dataset/raw/
  Monday-WorkingHours.pcap_ISCX.csv
  Tuesday-WorkingHours.pcap_ISCX.csv
  Wednesday-workingHours.pcap_ISCX.csv
  Thursday-WorkingHours-Morning-WebAttacks.pcap_ISCX.csv
  Thursday-WorkingHours-Afternoon-Infilteration.pcap_ISCX.csv
  Friday-WorkingHours-Morning.pcap_ISCX.csv
  Friday-WorkingHours-Afternoon-PortScan.pcap_ISCX.csv
  Friday-WorkingHours-Afternoon-DDos.pcap_ISCX.csv
```

The spelling and capitalization above match the distributed files, including
`Infilteration` and `DDos`. Raw and processed datasets are excluded by
`.gitignore` because they are large and should be obtained from the official
source. They are not redistributed with this repository.

### Attribution

If you use this project or dataset in research, cite the dataset's associated
paper as requested by its authors:

> Iman Sharafaldin, Arash Habibi Lashkari, and Ali A. Ghorbani, "Toward
> Generating a New Intrusion Detection Dataset and Intrusion Traffic
> Characterization," 4th International Conference on Information Systems
> Security and Privacy (ICISSP), Portugal, 2018.

## Run order

| Order | Notebook | Required? | Purpose |
|---:|---|:---:|---|
| 1 | `00A_Label_Converter.ipynb` | Conditional | Convert numeric 0/1 labels when the attack name exists only in the CSV filename. |
| 2 | `00B_Dataset_Harmonizer.ipynb` | Conditional | Harmonize columns and labels when combining dataset releases with different schemas. |
| 3 | `01_Preprocessing_local.ipynb` | Yes | Clean, encode, select features, split, balance training data, scale, visualize, and export artifacts. |
| 4 | `02_Baseline_Models.ipynb` | Recommended | Train conventional reference models for comparison. |
| 5 | `03_Big_Modeling.ipynb` | Yes for advanced experiments | Train CatBoost, five neural architectures, TabPFN, and the hybrid ensemble; run statistics and XAI. |
| 6 | `04_ROC_Curves.ipynb` | After model training | Reload saved models and generate validation/test ROC comparisons. |

The first two notebooks rewrite files in `dataset/raw/` only after making
backups. Skip `00A` when labels are already attack-name strings. Skip `00B`
when all raw CSV files already share the same schema and label vocabulary.

## Quick start

1. Download `MachineLearningCSV.zip` from the
   [official CIC-IDS2017 page](https://www.unb.ca/cic/datasets/ids-2017.html),
   extract it, and place the eight CSV files listed above in `dataset/raw/`.
2. Run the conditional preparation notebooks when applicable.
3. Run `01_Preprocessing_local.ipynb` from top to bottom.
4. Run `02_Baseline_Models.ipynb` for reference results.
5. In `03_Big_Modeling.ipynb`, first use smoke-test settings, then run the
   full experiment after the smoke test passes.
6. Run `04_ROC_Curves.ipynb` after the required model files exist.

For configuration details and troubleshooting, see [MANUAL.md](MANUAL.md).
For the manual hybrid workflow, see
[HYBRID_SELECTION.md](src/HYBRID_SELECTION.md).

## Data and artifact contract

Preprocessing writes its final hand-off files to `dataset/processed/final/`:

- NumPy: `X_{train,validation,test}.npy` and
  `y_{train,validation,test}.npy` for the baseline notebook.
- Parquet/CSV: scaled feature splits, labels, and SMOTE-balanced training
  data for advanced modeling.
- `metadata.json` and `manifest.csv` describing the exported data.

Model and report outputs are generated under:

```text
models/
  baseline_ml/
  encoders/
  trained/
reports/
  baseline_ml/
  label_conversion/
  harmonization/
  modeling/
  preprocessing/
results/
  baseline_ml/
```

The dataset, models, and reports directories are created by the notebooks and
may not exist in a fresh source-only checkout.

## Main models

- Baselines: Random Forest, Extra Trees, HistGradientBoosting, MLP, plus
  optional XGBoost, LightGBM, CatBoost, and TabNet.
- Advanced: CatBoost, FT-Transformer, TabM-style ensemble, TabGT-style model,
  GNNFormer-style model, feature GraphTransformer, and TabPFN.
- Ensemble: stacked logistic-regression meta-model or soft voting over two or
  three selected advanced models.

TabM, TabGT, and GNNFormer are compact research reproductions of their core
ideas, not imports of official implementations. Treat comparisons accordingly.

## Running unattended overnight

`run_all_notebooks.ps1` runs every notebook in order via `jupyter nbconvert`,
saves outputs in place, skips any cell that errors instead of stopping, and
logs progress — useful for leaving the full pipeline running overnight. See
"Running the full pipeline unattended" in [MANUAL.md](MANUAL.md) for setup and
usage.

## Environment

The notebooks support Google Colab and local Jupyter sessions. In local mode,
launch Jupyter from this project directory so `Path.cwd()` resolves correctly.
Core dependencies include NumPy, pandas, PyArrow, scikit-learn,
imbalanced-learn, Matplotlib, Seaborn, joblib, tqdm, and PyTorch. Individual
notebooks install or report optional packages such as CatBoost, XGBoost,
LightGBM, TabNet, TabPFN, SHAP, LIME, UMAP, statsmodels, and mlxtend.

## Security

Never paste API tokens into notebook source or Markdown. TabPFN authentication
must come from a `TABPFN_TOKEN` environment variable or a Colab Secret with
that name. If a token has ever been saved in a notebook, revoke it at the
provider and issue a new one; removing it from the current file does not remove
copies from backups, notebook history, cloud revisions, or shared downloads.

On Windows, set the variable once with:

```powershell
[System.Environment]::SetEnvironmentVariable("TABPFN_TOKEN", "your-key-here", "User")
```

then restart your terminal. See "TabPFN authentication" in
[MANUAL.md](MANUAL.md) for full steps.
