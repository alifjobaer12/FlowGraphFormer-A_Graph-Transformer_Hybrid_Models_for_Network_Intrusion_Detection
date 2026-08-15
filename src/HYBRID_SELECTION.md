# Manual hybrid selection

This is the manual alternative to automatic ensemble-member selection in
`03_Big_Modeling.ipynb`.

1. Run the desired individual advanced-model training and validation cells.
2. Review the cross-validation fold metrics in
   `reports/modeling/tables/*_cv_fold_metrics.csv` (the comparison cell also
   creates `all_models_cv_summary.csv`).
3. Choose two or three models using cross-validation performance. Consider error
   diversity; selecting near-identical models rarely improves an ensemble.
4. In the master-control cell, set:

```python
HYBRID_AUTO_SELECT = False
HYBRID_MEMBERS_MANUAL = ["gnnformer", "fttransformer", "graph-transformer"]
HYBRID_STRATEGY = "stacking"  # or "soft_voting"
```

5. Re-run the master-control cell and hybrid cell.
6. Re-run comparison so the hybrid appears alongside individual models.
7. In `04_ROC_Curves.ipynb`, use the same strategy and the same member order.

Stacking requires out-of-fold probability files for every member and trains a
logistic-regression meta-model. Soft voting averages class probabilities and
does not require a saved meta-model. Never choose members using held-out test
performance; that test set is reserved for the final unbiased report.

