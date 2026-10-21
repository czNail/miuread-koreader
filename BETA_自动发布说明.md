# 觅阅 Beta 一次填写发布流程

本文件对应 2026-10-21 上传的 `miuread-koreader(20261021-073042).zip` 基线。
本次只调整 **Beta 发布自动化**，未修改运行时插件功能，也未更改稳定版 `release.yml`。

## 这份代码的状态

- 源码版本暂时仍为 `6.0.0-beta.1`：这是原始基线的状态，**不应在提交自动化改动时提前改为新版本**。
- 下一次真正发布时，Actions 会从你填写的版本号自动更新 `_meta.lua`、`config.lua`、`CHANGELOG.md`，随后测试、提交和打包。
- 已存在的 `v6.0.1-beta.1` Tag 不应复用或强制移动。建议新版本使用未被占用的后续版本号，例如 `6.0.1-beta.2`，以线上 Tags 为准。
- 本 ZIP 内含从原始上传包保留的 `.git`，当前工作分支为 `beta`，源码修改处于**未提交**状态，不代表已经推送 GitHub。

## 首次启用（只做一次）

在解压得到的 `miuread-koreader` 文件夹内打开终端：

```bash
git status --short
python3 -m unittest discover -s tools -p 'test_prepare_beta_release.py'
python3 tools/verify_600_beta1.py
git add .github/workflows/release-beta.yml tools/verify_600_beta1.py tools/prepare_beta_release.py tools/test_prepare_beta_release.py BETA_自动发布说明.md
git commit -m "ci: automate beta release preparation"
git push origin beta
```

如果提示远端 `beta` 已经有更新，请先整合远端的新提交并检查冲突，**不要强制推送**；如存在分支保护，应通过 PR 合并。

注意：GitHub 的 `workflow_dispatch` 手动运行功能需要对应的工作流在仓库默认分支（`main`）上可见。本仓库原本已有 `main` 上的同名工作流。请在 **Run workflow 中明确选择 beta 分支**；如果新 `release_notes` 输入框没有显示，请检查 GitHub 界面加载的工作流版本，必要时同步 `main` 上该工作流的输入声明（不要用 `main` 执行 Beta 发布）。

## 以后每次发布 Beta

GitHub → 仓库 → **Actions** → **Release beta full package** → **Run workflow**：

- **Branch**：选 `beta`。
- **version**：填新的、尚未被使用的版本号，如 `6.0.1-beta.2`。
- **release_notes**：填写真实更新说明，多条用 ` | ` 分隔，例如：
  `修复阅读器返回主页后列表不刷新的问题 | 保留阅读进度同步保护`

然后运行。工作流按以下顺序执行：

1. 校验版本输入与已存在的 Tag；
2. 生成两个 Lua 文件的版本与对应的 CHANGELOG 条目；
3. 校验版本一致性和原有发布材料；
4. 运行原有 Lua 回归测试和发布保留性检查；
5. 测试通过后，将版本材料提交至 `beta`（不强推）；
6. 确认 beta 当前 HEAD、创建新的 Tag；
7. 生成完整安装包，校验 ZIP 大小与 SHA-256，上传 Beta Release；
8. 更新固定 `beta-channel` 的 OTA 清单。

**不要再先手动创建并推送新 Tag。** 原来的 `push tag` 路径保留作兼容，但仍使用严格的源码版本校验，不会自动填写版本说明。日常发布应走 `Run workflow`。

## 修改文件清单

- `.github/workflows/release-beta.yml`：加入手动版本/说明输入和自动准备、提交步骤；保留现有发布验证链路。
- `tools/prepare_beta_release.py`：输入校验、生成版本与更新条目；同版本重新运行只接受相同说明。
- `tools/test_prepare_beta_release.py`：自动化单元测试。
- `tools/verify_600_beta1.py`：把原来的固定 `6.0.0-beta.1` 断言改成动态版本一致性断言，同时继续要求 6.0.0 基线记录保留。
- `BETA_自动发布说明.md`：本说明。

没有修改正式版工作流 `release.yml`、插件业务 Lua 文件或用户数据格式。

## 已做的离线验证

- 单元测试：7 项通过。
- 基线和模拟新版本的 `tools/verify_600_beta1.py`：各 54 项通过。
- `tools/test_extension_center_ux.py`：24 项通过。
- 在模拟的新版本目录执行工作流的元数据准备、发布校验、ZIP 构建和 manifest 验证步骤：通过。

尚未在 GitHub Runner 上真正执行发布、推送 Tag 或测试全部 Lua 运行时回归（本地无 Lua 5.1 / LuaJIT）。本包也没有真实发布 `6.0.1-beta.2`；这是下一次发布的版本号示例。
