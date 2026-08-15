# ============================================================
# run_all_notebooks.ps1
# Runs all FlowGraphFormer notebooks sequentially overnight.
# - Checks/installs required Python packages first
# - Registers venv as a Jupyter kernel (so notebooks find it)
# - Executes each notebook in-place (saves outputs below cells)
# - If a cell errors, it's skipped and execution continues
# - Logs everything with timestamps to a log file
# ============================================================

# ---- CONFIG: edit these paths ----
$ProjectRoot  = "C:\Users\Alif\FlowGraphFormer"   # <-- change to your project root
$VenvPath     = "C:\Users\Alif\FlowGraphFormer\venv"  # <-- change to your venv folder
$KernelName   = "flowgraphformer"
$LogDir       = Join-Path $ProjectRoot "logs"
$Timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile      = Join-Path $LogDir "run_all_notebooks_$Timestamp.log"

# Notebooks in the order you want them executed
$Notebooks = @(
    "00_Dataset_Harmonizer.ipynb",
    "00b_Label_Converter.ipynb",
    "01_Preprocessing_local.ipynb",
    "03_Big_Modeling.ipynb",
    "04_ROC_Curves.ipynb"
)

# Packages required to run this pipeline locally.
# Format: "pip-install-name==version" or just "pip-install-name" (latest).
# Edit this list to match what your notebooks actually import.
#
# NOTE: pandas + pyarrow are PINNED together on purpose. Installing them
# separately (e.g. upgrading only one later) is what caused the
# "ArrowKeyError: No type extension with name arrow.py_extension_type found"
# error you hit — that's a known incompatible-version bug between the two.
# If you need newer versions, upgrade both together and re-test Cell 3.
$RequiredPackages = @(
    "notebook",
    "nbconvert",
    "ipykernel",
    "pandas==2.2.3",
    "pyarrow==17.0.0",   # pinned WITH pandas above — do not split these
    "fastparquet",       # fallback engine if pyarrow ever breaks again
    "numpy",
    "scikit-learn",
    "imbalanced-learn",
    "torch",
    "catboost",
    "tabpfn",
    "shap",
    "lime",
    "matplotlib",
    "seaborn",
    "nbformat",
    "joblib"
)

# TabPFN API token — set this as a REAL Windows environment variable instead
# of pasting it into the notebook. In PowerShell (run once, permanently):
#   [System.Environment]::SetEnvironmentVariable("TABPFN_TOKEN","your-new-key","User")
# Then just leave this line as-is; the script will pass it through if present.
if ($env:TABPFN_TOKEN) {
    Write-Host "TABPFN_TOKEN found in environment - will be available to notebooks."
} else {
    Write-Host "WARNING: TABPFN_TOKEN not set as an environment variable."
    Write-Host "Cell 16 (TabPFN) will warn/skip token setup unless it's already cached from a prior run."
}

# Max time (seconds) any single cell is allowed to run before nbconvert times out
# -1 = no timeout (recommended for training notebooks left running overnight)
$CellTimeout = -1

# ---- GPU memory settings (fixes the TabPFN CUDA OOM you hit locally) ----
# Your local GPU has much less VRAM than Colab's T4, so models that assume
# T4-sized memory (like TabPFN doing all-at-once attention over the test set)
# will crash locally unless we cap batch sizes and reduce fragmentation.
$env:PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True"
$env:TABPFN_MAX_BATCHED_TEST_ROWS = "2000"   # lower than the 32768 default; tune up if you have more VRAM

# Folders your notebooks expect to already exist (edit to match your actual
# CONFIG paths - these come from your dataset/processed, reports/tables,
# reports/figures, reports/predictions, reports/stats, models dirs)
$RequiredFolders = @(
    "dataset\raw",
    "dataset\processed",
    "models",
    "reports\tables",
    "reports\figures",
    "reports\predictions",
    "reports\stats"
)

# ============================================================
# SETUP
# ============================================================
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Write-Log "===== Starting overnight notebook run ====="
Write-Log "Project root: $ProjectRoot"
Write-Log "Venv path: $VenvPath"
Write-Log "Log file: $LogFile"

# ---- Activate venv (in case script was launched without activating first) ----
$ActivateScript = Join-Path $VenvPath "Scripts\Activate.ps1"
if (Test-Path $ActivateScript) {
    Write-Log "Activating venv: $ActivateScript"
    & $ActivateScript
} else {
    Write-Log "WARNING: Could not find venv activate script at $ActivateScript"
    Write-Log "Continuing with whatever Python/pip is currently on PATH."
}

# Confirm python/pip resolve to the venv
$pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
$pipPath    = (Get-Command pip -ErrorAction SilentlyContinue).Source
Write-Log "Using python: $pythonPath"
Write-Log "Using pip: $pipPath"

if (-not $pythonPath) {
    Write-Log "FATAL: python not found on PATH. Activate your venv manually then rerun this script."
    exit 1
}

# ============================================================
# STEP 0: ENSURE EXPECTED FOLDERS EXIST
# ============================================================
Write-Log "-----------------------------------------------"
Write-Log "Ensuring required project folders exist..."
foreach ($folder in $RequiredFolders) {
    $fullPath = Join-Path $ProjectRoot $folder
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        Write-Log "CREATED missing folder: $fullPath"
    } else {
        Write-Log "OK (exists): $fullPath"
    }
}

# ============================================================
# STEP 1: CHECK + INSTALL REQUIRED PACKAGES
# ============================================================
Write-Log "-----------------------------------------------"
Write-Log "Checking required packages..."

# Get list of already-installed package names (lowercased, no version) via pip
$installedRaw = & pip list --format=freeze 2>$null
$installedNames = @{}
foreach ($line in $installedRaw) {
    if ($line -match "^([^=]+)==") {
        $installedNames[$matches[1].ToLower()] = $true
    }
}

foreach ($pkg in $RequiredPackages) {
    # Strip version pin to get the base package name for the "is it installed" check
    $pkgName = ($pkg -split "==")[0].ToLower()

    if ($installedNames.ContainsKey($pkgName)) {
        Write-Log "OK (already installed): $pkg"
    } else {
        Write-Log "MISSING: $pkg -> installing now..."
        $installLog = Join-Path $LogDir "pip_install_$($pkgName)_$Timestamp.log"

        try {
            & pip install $pkg *>&1 | Tee-Object -FilePath $installLog | Out-Null
            $exitCode = $LASTEXITCODE
        } catch {
            Write-Log "ERROR launching pip install for $pkg : $_"
            $exitCode = -999
        }

        if ($exitCode -eq 0) {
            Write-Log "INSTALLED: $pkg"
        } else {
            Write-Log "FAILED TO INSTALL: $pkg (exit $exitCode) — see $installLog"
            Write-Log "Continuing anyway; notebooks needing this package may fail/skip cells."
        }
    }
}

# ============================================================
# STEP 2: REGISTER VENV AS A JUPYTER KERNEL
# ============================================================
Write-Log "-----------------------------------------------"
Write-Log "Registering venv as Jupyter kernel '$KernelName'..."

try {
    & python -m ipykernel install --user --name=$KernelName --display-name "Python ($KernelName venv)" *>&1 |
        Tee-Object -FilePath (Join-Path $LogDir "kernel_register_$Timestamp.log") | Out-Null
    Write-Log "Kernel registered as '$KernelName'."
} catch {
    Write-Log "WARNING: Kernel registration failed: $_"
    Write-Log "nbconvert will fall back to whatever kernel is specified in each notebook's metadata."
}

# ============================================================
# STEP 3: RUN NOTEBOOKS SEQUENTIALLY
# ============================================================
$OverallStart = Get-Date
$Results = @()

foreach ($nb in $Notebooks) {

    $nbPath = Join-Path $ProjectRoot $nb

    if (-not (Test-Path $nbPath)) {
        Write-Log "SKIPPING (file not found): $nb"
        $Results += [PSCustomObject]@{ Notebook = $nb; Status = "NOT FOUND"; DurationMin = 0 }
        continue
    }

    Write-Log "-----------------------------------------------"
    Write-Log "STARTING: $nb"
    $start = Get-Date

    # jupyter nbconvert:
    #   --to notebook                 -> output is still a .ipynb (not html/pdf)
    #   --execute                     -> actually run all cells
    #   --allow-errors                -> if a cell throws, log the error IN the notebook and move to next cell
    #   --output                      -> overwrite the same file in place, so outputs are saved under each cell
    #   --ExecutePreprocessor.timeout -> per-cell timeout in seconds (-1 = unlimited)
    #   --ExecutePreprocessor.kernel_name -> force our registered venv kernel
    $args = @(
        "nbconvert",
        "--to", "notebook",
        "--execute",
        "--allow-errors",
        "--ExecutePreprocessor.timeout=$CellTimeout",
        "--ExecutePreprocessor.kernel_name=$KernelName",
        "--output", $nb,
        "--output-dir", $ProjectRoot,
        $nbPath
    )

    try {
        $proc = Start-Process -FilePath "jupyter" -ArgumentList $args `
                    -NoNewWindow -Wait -PassThru `
                    -RedirectStandardOutput (Join-Path $LogDir "$($nb)_stdout.log") `
                    -RedirectStandardError  (Join-Path $LogDir "$($nb)_stderr.log")

        $exitCode = $proc.ExitCode
    }
    catch {
        Write-Log "FATAL error launching jupyter for $nb : $_"
        $exitCode = -999
    }

    $end = Get-Date
    $durationMin = [math]::Round(($end - $start).TotalMinutes, 2)

    if ($exitCode -eq 0) {
        Write-Log "COMPLETED: $nb (took $durationMin min) — all cells ran (errors, if any, were skipped and saved in the notebook)"
        $Results += [PSCustomObject]@{ Notebook = $nb; Status = "COMPLETED"; DurationMin = $durationMin }
    } else {
        Write-Log "FAILED TO RUN: $nb (exit code $exitCode, took $durationMin min) — check $($nb)_stderr.log"
        $Results += [PSCustomObject]@{ Notebook = $nb; Status = "FAILED (exit $exitCode)"; DurationMin = $durationMin }
    }
}

$OverallEnd = Get-Date
$totalMin = [math]::Round(($OverallEnd - $OverallStart).TotalMinutes, 2)

Write-Log "-----------------------------------------------"
Write-Log "===== ALL NOTEBOOKS FINISHED ====="
Write-Log "Total time: $totalMin minutes"
Write-Log ""
Write-Log "Summary:"
foreach ($r in $Results) {
    Write-Log ("  {0,-35} {1,-20} {2} min" -f $r.Notebook, $r.Status, $r.DurationMin)
}

Write-Log "===== Script complete. You can review each notebook's outputs directly (saved in-place). ====="
