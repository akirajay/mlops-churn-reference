# Lab 01 – Foundation CI/CD 排障记录

本文档记录在搭建 `Lab 01 - Foundation` GitHub Actions 流水线（OIDC 登录 + Bicep 部署）过程中遇到的全部问题、根因与最终修复方案，供后续复用。

- 仓库：`akirajay/mlops-churn-reference`
- 工作流：`.github/workflows/lab01-foundation.yml`
- 区域：`japaneast`
- 最终结果：`validate → deploy-shared → deploy-dev → deploy-prod` 全部 ✅

---

## 1. 计算实例（Compute Instance）名称冲突

- **现象**：部署 `compute` 模块时报名称已被占用，`ci-akira` 在订阅内全局唯一，dev/prod 复用同名导致冲突。
- **根因**：Azure ML Compute Instance 名称需在区域/订阅范围唯一，原模板对 dev、prod 使用了相同的 `ci-akira`。
- **修复**：
  - `infra/main.bicep`：向 compute 模块传入 `ciName: 'ci-akira-${envName}'`。
  - `infra/modules/compute.bicep`：新增 `param ciName string = 'ci-akira'`，资源名改为 `${workspaceName}/${ciName}`，并输出 `ciName`。

## 2. OIDC 缺少 `ref:refs/heads/main` 联合凭据（AADSTS70025）

- **现象**：`azure/login` 在 push 到 `main` 触发的 job 上失败，报联合凭据不匹配。
- **根因**：仅配置了 `environment:dev`、`environment:prod`、`pull_request` 三个 subject，缺少分支级 subject。
- **修复**：为应用注册新增联合凭据 subject `repo:akirajay/mlops-churn-reference:ref:refs/heads/main`。

## 3. 服务主体缺少 `roleAssignments/write` 权限

- **现象**：workspace/部署过程中创建角色分配失败，提示无 `Microsoft.Authorization/roleAssignments/write` 权限。
- **根因**：SP 仅有 Contributor，无法写角色分配。
- **修复**：在 `rg-churn-dev`、`rg-churn-prod` 上为 SP 追加 **User Access Administrator** 角色。

## 4. `deploy-shared` 的 environment 绑定导致 OIDC subject 不匹配（AADSTS700213）

- **现象**：`deploy-shared` job 绑定了 `environment: dev`，但实际请求的 OIDC subject 与联合凭据不符。
- **根因**：job 上的 `environment:` 绑定会把 OIDC subject 变为 `environment:<name>`，与 shared 部署期望的 subject 不一致。
- **修复**：移除 `deploy-shared`、`deploy-dev`、`deploy-prod` 上的 `environment:` 绑定，统一使用仓库级 secrets 与分支/环境联合凭据。
- **✅ 已恢复**：prod 审批门禁已重新启用（见下「加固项」）：`deploy-prod` job 重新绑定 `environment: prod`，并在 GitHub prod environment 上配置 Required reviewers。因 `environment:prod` 联合凭据初始化时已建，恢复绑定无需再改 `az ad`。

## 5. GitHub Secrets 配置错误

- **现象**：
  - 新建的 secret 名称为空，`azure/login` 取不到 client-id。
  - `AADSTS700016`：应用 `fc1dd5b1...` 在目录中找不到（使用了错误 appId）。
- **根因**：secret 命名/取值错误，且一度写入了过期/错误的 appId。
- **修复**：
  - 统一使用 `AZURE_OIDC_CLIENT_ID` / `AZURE_OIDC_TENANT_ID` / `AZURE_OIDC_SUBSCRIPTION_ID`。
  - 将仓库级及 dev/prod 环境级 secrets 全部重置为正确值：
    - appId `fd96d8e2-b2e4-4014-ae06-363110409199`
    - tenant `d6c16817-6d80-4c2e-815e-532071cc2b98`
    - subscription `562e89f8-4e92-4863-8637-3817bca9bc99`

## 6. 存储账户 `isHnsEnabled` 只读属性无法更新（AccountPropertyCannotBeUpdated）

- **现象**：`deploy-dev` 失败，`storage` 模块报：
  > The property 'isHnsEnabled' was specified in the input, but it cannot be updated as it is read-only.
- **根因**：dev 存储账户已存在，`isHnsEnabled` 在已创建账户上为只读，重复部署时尝试写入即报错。
- **修复**：从 `infra/modules/storage.bicep` 移除 `isHnsEnabled: false`（新建账户默认即为 false，无需显式声明）。

## 7. Key Vault 名称非法（VaultNameNotValid）

- **现象**：`kv` 模块报名称 `kv-churn-dev-m7kjfr6dfkwre` 非法。
- **根因**：Key Vault 名称要求 3–24 个字母数字、以字母开头、不允许连续连字符；原命名带连字符且超长。
- **修复**：`infra/main.bicep` 中改为去连字符并截断：
  `'kv${replace(suffix, '-', '')}${substring(uniqueString(resourceGroup().id), 0, 8)}'`，
  得到如 `kvchurndev<8位>`（18 字符，合规）。

## 8. CI 跑的是旧提交（修改未提交）

- **现象**：本地已修复 Key Vault / 存储命名，但 CI 仍报旧的命名错误。
- **根因**：`infra/main.bicep`、`infra/modules/*.bicep` 的修复仅在本地，尚未 commit/push，CI 检出的是旧版。
- **修复**：将所有 infra 修复一并提交并推送，CI 重新检出后通过。

---

## 环境/工具注意事项

- **gh CLI**：设置 `$env:GH_PAGER='cat'` 避免进入备用缓冲区；避免使用 `gh run watch`（会打开备用缓冲区）。
- **pytest**：使用 `python -m pytest` 运行（非 `uv`）。
- **`az ad` 受 CAE 挑战阻塞**：出现 `TokenCreatedWithOutdatedPolicies`（InteractionRequired）时无法用 `az ad` 创建联合凭据 / 查询 SP。
  - **彻底解法**：在执行 `az ad` 操作前先重新认证：
    ```pwsh
    az logout
    az login --scope https://graph.microsoft.com/.default
    ```
    重新获取带最新策略的 token 即可绕过 CAE 挑战。

## 最终验证

- dev / prod 基础设施均部署成功，`labs/01-foundation/verify` 下 4 个 pytest 用例全部通过。
- GitHub Actions run 全链路成功：`validate → deploy-shared → deploy-dev → deploy-prod`。

## 加固项（已应用）

- **prod 审批门禁**：`deploy-prod` 重新绑定 `environment: prod`，并在 GitHub prod environment 配置 Required reviewers（`akirajay`）。push 到 main 时 prod 部署会暂停等待人工批准。`environment:prod` 的 federated credential 初始化时已建，无需再动 `az ad`。
- **concurrency 防并发**：workflow 顶层新增 concurrency group，避免连续 push 触发重复/并发部署：
  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: false
  ```
  `cancel-in-progress: false`：部署进行中不取消，避免中途打断留下半成品资源。
