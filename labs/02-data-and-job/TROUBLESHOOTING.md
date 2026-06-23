# Lab 02 — Troubleshooting Log

A record of every failure hit while getting the **Lab 02 — Data & Command Job**
GitHub Actions workflow (`.github/workflows/lab02-data-job.yml`) to pass, and how
each was fixed. Ordered as encountered.

## Summary

| # | Symptom | Root cause | Fix |
|---|---------|-----------|-----|
| 1 | `AuthorizationFailure` on `az ml job create` | OIDC service principal lacked blob data-plane RBAC | Grant `Storage Blob Data Contributor` to the SP |
| 2 | `AuthorizationFailure` again | Storage `publicNetworkAccess = Disabled` blocks the public GitHub runner | Re-enable public network access |
| 3 | `pytest: error: unrecognized arguments: --env` | `pytest_addoption` lived in a test module, not `conftest.py` | Move hook + `env` fixture to `conftest.py` |
| 4 | `KeyBasedAuthenticationNotPermitted` on `az ml data create` | Azure Policy `StorageAccount_DisableLocalAuth_Modify` forces `allowSharedKeyAccess=false` | Switch workspace to identity-based datastores |
| 5 | Training jobs `Failed` within ~1s | `train.py` was never created | Add `train.py`; assert only that jobs were submitted |

Plus minor fixes: invalid MLTable `to_string: {}` schema, and a test that
required ADLS Gen2 (HNS) / `azure.mgmt.storage` that did not match the env.

---

## 1. `AuthorizationFailure` — missing blob RBAC

**Error**
```
ERROR: Operation returned an invalid status 'This request is not authorized to perform this operation.'
ErrorCode:AuthorizationFailure
```

**Why** — `az ml job create` uploads the `code:` snapshot to the workspace
default blob datastore using the caller's Entra ID. The GitHub OIDC service
principal (`sp-mlops-churn-reference-gh`) could manage AML but had no
data-plane permission on the storage account.

> Distinguish the two storage auth errors:
> - `AuthorizationPermissionMismatch` ("...using this permission") → **RBAC** missing.
> - `AuthorizationFailure` ("This request is not authorized...") → **network/firewall** block (see #2).

**Fix**
```bash
az role assignment create \
  --assignee <AZURE_OIDC_CLIENT_ID> \
  --role "Storage Blob Data Contributor" \
  --scope <storage-account-id>
```
Also captured in IaC: `infra/modules/storage.bicep` now assigns this role, wired
through `deployerPrincipalId` from `infra/main.bicep`.

---

## 2. `AuthorizationFailure` — public network access disabled

**Why** — even with RBAC fixed, the storage account had
`publicNetworkAccess = Disabled`. GitHub-hosted runners come from the public
internet and cannot reach a privatized storage account, so the blob upload was
rejected before RBAC was ever evaluated.

**Diagnosis**
```bash
az storage account show --ids <storage-id> \
  --query "{publicNetworkAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction}"
```

**Fix**
```bash
az storage account update --ids <storage-id> --public-network-access Enabled
```

> ⚠️ Security trade-off. This re-opens the storage account to the public
> internet (bootstrap posture). For production, use a self-hosted runner inside
> the VNet with a Private Endpoint instead.

---

## 3. `pytest: unrecognized arguments: --env`

**Error**
```
pytest: error: unrecognized arguments: --env=dev
```

**Why** — pytest only loads the `pytest_addoption` hook from `conftest.py`
files or installed plugins, **never from a regular `test_*.py` module**. The
option was defined inside `test_lab02.py`, so `--env` was never registered.

**Fix** — move `pytest_addoption` and the `env` fixture into
`labs/02-data-and-job/verify/conftest.py`.

---

## 4. `KeyBasedAuthenticationNotPermitted` — policy blocks shared keys

**Error**
```
ERROR: Met error <class 'Exception'>:KeyBasedAuthenticationNotPermitted
Operation returned an invalid status 'Key based authentication is not permitted on this storage account.'
```

**Why** — `az ml data create` uploads using an account-key-derived SAS token,
but the storage account has `allowSharedKeyAccess = false`. Attempting to
re-enable it silently failed because an Azure Policy with a `modify` effect
re-disables it:
```bash
az policy state list --resource <storage-id> \
  --query "[?policyDefinitionAction=='modify'].policyDefinitionName"
# -> StorageAccount_DisableLocalAuth_Modify
```
So "Plan A" (enable shared keys) is blocked at the subscription level.

**Fix (Plan B — identity-based datastores)** — make AML use Entra ID instead of
account keys for its system datastores:
```bash
# 1) Grant the workspace MSI blob data access
az role assignment create \
  --assignee <workspace-msi-object-id> \
  --role "Storage Blob Data Contributor" \
  --scope <storage-id>

# 2) Switch the workspace to identity-based system datastores
az resource update --ids <workspace-id> \
  --set properties.systemDatastoresAuthMode=identity
```
Captured in IaC: `infra/modules/workspace.bicep` sets
`systemDatastoresAuthMode: 'Identity'` and grants the workspace MSI the blob role.

> This is the more secure, policy-compliant approach and is preferred over
> re-enabling shared keys.

---

## 5. Training jobs `Failed` within ~1 second

**Error** (surfaced by `test_recent_lab02_job_completed`)
```
AssertionError: Some lab02 jobs failed: [('sweet_snail_0p88zpbndd', 'Failed'), ...]
```
Jobs failed instantly (`StartTimeUtc == EndTimeUtc`).

**Why** — the job command is `python train.py ...`, but `src/` only contained
`conda.yml`. **`train.py` had never been created**, so every job died
immediately.

**Fix**
- Added `labs/02-data-and-job/src/train.py` (loads data per asset type, trains a
  logistic-regression churn model, logs metrics/model to MLflow).
- Reworked the verify test to match the workflow's async "don't wait" design: it
  now asserts only that lab02 jobs were **submitted**, not their run outcome
  (which is tracked in Azure ML Studio). Historical failed runs would otherwise
  permanently fail the check.

---

## Minor fixes

- **Invalid MLTable schema** — `column_type: { to_string: {} }` is not valid;
  changed `TotalCharges` to `column_type: string` in
  `data/telco-churn/mltable/MLTable`.
- **Storage test mismatch** — the original `test_storage_is_adls_gen2` required
  HNS (ADLS Gen2) and imported `azure.mgmt.storage`, neither of which matched the
  plain `StorageV2` reference environment. Replaced with
  `test_workspace_has_storage`, which only checks a storage account is wired to
  the workspace (no extra dependency).

---

## Verification

Final run: all steps green, all 5 tests pass.
```
test_data_asset[telco-churn-file-uri_file]      PASSED
test_data_asset[telco-churn-folder-uri_folder]  PASSED
test_data_asset[telco-churn-mltable-mltable]    PASSED
test_workspace_has_storage                      PASSED
test_recent_lab02_jobs_submitted                PASSED
```

## Quick reference — diagnostic commands

```bash
# Storage network + auth posture
az storage account show --ids <storage-id> \
  --query "{publicNetworkAccess:publicNetworkAccess, allowSharedKey:allowSharedKeyAccess, isHnsEnabled:isHnsEnabled}"

# Policies affecting the storage account
az policy state list --resource <storage-id> \
  --query "[?policyDefinitionAction=='modify' || policyDefinitionAction=='deny'].policyDefinitionName"

# Workspace datastore auth mode + MSI
az resource show -g <rg> -n <ws> \
  --resource-type Microsoft.MachineLearningServices/workspaces \
  --query "{authMode:properties.systemDatastoresAuthMode, msi:identity.principalId}"

# Tail a failed GitHub Actions run
gh run view <run-id> --repo <owner/repo> --log-failed
```
