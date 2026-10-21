# 觅阅 Beta 发布失败修复（2026-10-21）

## 已确认的失败原因

2026-10-21 GitHub Actions `release-beta.yml` 的失败不是多设备认证本身导致，而是直接推送 `v6.1.0-beta.1` Tag 时触发了 `push` 工作流；只有 `workflow_dispatch` 路径才会先自动更新源码里的 `miuread.koplugin/_meta.lua`、`miuread.koplugin/miuread/config.lua` 和 `CHANGELOG.md`。两份 Lua 仍为 `6.0.0-beta.1`，所以一致性校验正确地终止了发布。

另一个问题：仓库默认分支 `main` 的 `release-beta.yml` 仍使用旧的手动发布输入声明（只有版本号），而 `beta` 分支有“版本号+更新说明”。GitHub Actions 的 Run workflow 输入界面可能因此缺少更新说明。

## 本次修复

**只需替换一个文件，替换两次**：将本包的 `release-beta.yml` 分别放入仓库 `beta` 和 `main` 两个分支的 `.github/workflows/release-beta.yml`。两个分支的该文件保持完全相同。其余源码文件无需更改；已推送的多设备登录代码保留不动。

修复版只保留 `workflow_dispatch` 手动入口，不再监听任何 `v*-beta.*` Tag 的推送。新发布由 Actions 读取输入的版本号和更新说明，完成自动修改版本文件、生成 CHANGELOG、运行回归测试、提交到 beta、创建 Tag、打包和更新 OTA 清单。Tag 只在版本元数据已经提交后生成，避免再次出现“Tag 与源码版本不一致”。现有 Tag 不会被删除、移动或重写。

## 在 GitHub 网站上修改（推荐，避免本地旧 .git 与远程 beta 不一致）

1. 打开 `https://github.com/miumiupy98-art/miuread-koreader`，进入 **Code**，选择分支 `beta`。
2. 打开 `.github/workflows/release-beta.yml`，点编辑，**用本包 `release-beta.yml` 的全文覆盖**，提交到 `beta`。只改这个文件。
3. 切换到 `main`，在相同路径执行**同样的全文覆盖**，提交到 `main`。主程序和正式版 `release.yml` 不动。受保护分支需要通过 Pull Request 提交。
4. 进入 **Actions → Release beta full package → Run workflow**，选择 `beta` 分支。应该能看到 `version` 和 `release_notes` 两个输入框。
5. 推荐填写：版本 `6.1.0-beta.2`；更新说明 `改进 Web 多设备登录：每台安装实例保存独立设备指纹 | 保持原有 Native 书架授权与阅读进度逻辑不变`，点击 Run workflow。
6. 等待检查与自动发布。成功后检查生成的 Tag `v6.1.0-beta.2` 指向新的自动提交，Release 的完整包与 beta-channel 更新清单版本均为 `6.1.0-beta.2`。

## 现有失败 Tag 的处理

`v6.1.0-beta.1` 已存在且指向提交 `187cd956c5f783b73f3bbdc98bdb5a306779f5d0`，而当时的两个版本字段仍为 `6.0.0-beta.1`。**不要复用或强制移动这个 Tag**。选择 `6.1.0-beta.2` 是无破坏性的做法；截至准备本补丁时，公开仓库不存在同名 Tag 和 Release。

## 验证范围

- workflow YAML 结构解析通过（仅 workflow_dispatch，12 个步骤）；发布工作流契约测试 7 项通过；版本元数据准备测试 7 项通过。
- 使用原项目文件模拟 `6.1.0-beta.2` 自动准备后，两个 Lua 文件的版本与 CHANGELOG 一致；原 Beta verifier 54 项通过；扩展中心测试 24 项通过。
- **尚未实际在 GitHub Runner 运行新流程，也未创建远程 Tag 或 Release；没有执行两台 Kindle 的在线会话测试。**

## 若你在本地编辑

请使用**你已经推送后同步过远端 beta 分支的本地仓库**；不要直接把旧 ZIP 里保留的 `.git` 当作最新远端历史。正常 `git pull --ff-only` 后复制新 YAML、提交、推送；`main` 分支同理。切勿 `git push --force`，也不要修改 Tag。
