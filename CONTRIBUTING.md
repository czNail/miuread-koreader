# 分支与发布合并规则

`beta` 是持续开发和内测分支，`main` 是正式发布分支。

- 功能分支合入 `beta` 可以使用 Squash and merge。
- `beta` 合入 `main`，以及 `main` 的修复回合 `beta`，必须使用 **Create a merge commit**，保留两条分支的历史关系。发布准备分支也适用此规则。
- 正式发布流程如果在 `main` 生成了版本或更新记录提交，发布后应再将 `main` 合回 `beta`，保留 beta 的版本与通道身份。
- 不要对共享的 `beta`、`main` 强推或重写历史；不要用全局 ours/theirs 策略掩盖业务代码差异。

## 本次历史修复

此前的正式发布 PR #109、#133 将已有 beta 改动压缩成了新提交，后续比较因此重复包含旧改动。修复提交以当前 beta 为第一父提交、main 为第二父提交，连接现有历史。

核对基线：main `8aac230` 与 beta 的 `dde4418` 在 `miuread.koplugin/` 中只有 `_meta.lua` 和 `miuread/config.lua` 的版本与通道差异，业务代码完全相同。因此本次保留当前 beta `4aa6ead` 的完整文件树和后续改进，并补回 main 的正式版更新记录。

本次修复不创建版本标签、不发布安装包，也不将 beta 的版本与默认更新通道改成 stable。合并此修复 PR 时必须选择 **Create a merge commit**；Squash 或 Rebase 会再次丢失 main 的父提交关系。

修复合入 beta 后，`git merge-base --is-ancestor origin/main origin/beta` 应成功。此时即可正常创建 `beta` 到 `main` 的发布 PR；实际正式发布前仍需审核 beta 的功能、版本和发布说明。
