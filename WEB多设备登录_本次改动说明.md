# 觅阅 Web 多设备登录修复（基于 2026-10-21 Beta 自动发布源码）

## 改动范围

本次仅为普通微信读书 Web 扫码登录增加每台安装实例独立的 `wr_fp` 设备身份。
原有的 Native 书架管理授权、下载、精确阅读进度和阅读时间上报算法未重构。

- `miuread/device_identity.lua`：读取系统 `/dev/urandom` 4 字节，生成 32 位无符号十进制设备指纹；持久保存到 Store 顶层 `device_fingerprint`，不是账号 Cookie 或 `login_session_id`；写入失败或无法校验落盘时拒绝发起新的二维码。
- `miuread/store.lua`：新增独立的安装级别配置默认值。Schema 仍是 136；退出/切换账号不会删除这个值。
- `miuread/auth.lua`：首次登录页面请求起即携带 `wr_fp`，UID 获取、扫码轮询、凭据验收、续期均保持相同指纹；校验新签发凭据实际保存了 `wr_fp`。
- `miuread/cookies.lua`：正常已授权网络响应不允许覆盖或清除当前会话的 `wr_fp`，现有 `wr_skey` 等处理逻辑保持不变。
- `tools/test_multidevice_web_login.lua`：新增脱网双安装实例测试、Cookie 不可意外改写、未能持久化时的 fail-closed 测试。
- `tools/test_shelf_client.lua`：更新模拟 Web QR 完成的测试夹具，同时验证同账号重登保留 Native 授权。
- `.github/workflows/release-beta.yml`：将新增回归测试纳入 Lua5.1 / LuaJIT Beta 发布校验，保留之前的自动发布改动。

## 升级与用户行为

1. 已登录的旧会话不强制退出，也不修改原来的服务器签发凭据。
2. 新版安装后，如果要验证多设备共存，需要在 **每一台设备**重新扫码一次，使微信读书在首次登录请求就收到各自的 `wr_fp`。
3. 同一台设备退出/重新登录会复用原指纹；第二个设备应该生成不同指纹。
4. **不要复制整个 `miuread.lua` 设置文件到另一台设备**当作部署方式，这会同时复制设备指纹和登录凭据；应分别安装/扫码。
5. 不新增或合并 Native 书架管理的第二套授权，不自动删除用户已有书架授权。
6. 没有经过真实微信读书服务端的跨设备长时间验证；此机制与上游 v1.6.0 的 Web 指纹思路一致，但服务端规则未来可能改变。

## 本地测试与发布

本 ZIP 保留上传时已有的 `.git`、`beta` 分支以及你尚未提交的 Beta 自动发布文件。本次补丁同样尚未提交，也没有创建 Tag、推送仓库或改线上 Release。

在解压得到的 `miuread-koreader` 目录执行：

```bash
python3 -m unittest discover -s tools -p 'test_prepare_beta_release.py'
python3 tools/verify_600_beta1.py
lua5.1 tools/test_multidevice_web_login.lua
lua5.1 tools/test_shelf_client.lua
luajit tools/test_multidevice_web_login.lua
luajit tools/test_shelf_client.lua
# 其他 Beta 回归测试由 GitHub Actions 运行

git status --short
git add .github/workflows/release-beta.yml tools/verify_600_beta1.py \
  tools/prepare_beta_release.py tools/test_prepare_beta_release.py BETA_自动发布说明.md \
  miuread.koplugin/miuread/auth.lua miuread.koplugin/miuread/cookies.lua \
  miuread.koplugin/miuread/store.lua miuread.koplugin/miuread/device_identity.lua \
  tools/test_multidevice_web_login.lua tools/test_shelf_client.lua \
  WEB多设备登录_本次改动说明.md
git commit -m "fix(auth): isolate WeRead Web QR sessions by installation fingerprint"
git push origin beta
```

不要 `git push --force`，也不要先创建发行 Tag。推送 Beta 分支后，再进入 GitHub Actions 的 **Release beta full package**，选择 `beta`、填写一个**尚未使用**的 Beta 版本号与更新说明。例如：

```
version: 6.0.1-beta.2
release_notes: 修复同一微信账号在多台 Kindle 登录后互相挤掉的问题 | 每台安装生成并保留独立 Web 设备身份 | 保留已有书架管理授权及阅读进度保护
```

源码 `_meta.lua` / `config.lua` 暂仍为 `6.0.0-beta.1`；这是你之前的自动发布流程的设计要求，Actions 会在正式运行发布时依据填写的版本号准备版本文件。务必先确认上述版本号未被使用。

## 真机验收（发布前）

- [ ] A 设备扫码后正常加载书架、打开书并下载；B 设备使用**同一个**微信读书账号扫码后，A 仍可以刷新、下载和续期。
- [ ] A、B 交替操作 30 分钟以上后仍有效；重启两台设备后分别正常。
- [ ] A 退出、重新扫码后，B 仍有效；两台设备各自的 `wr_fp` 不同，且会话可以共存。
- [ ] 单设备旧会话升级后不被强制登出；重登同一账号后 Native 书架管理授权仍在。
- [ ] 微信读书服务端出现鉴权错误时不会把旧凭据悄悄覆盖或清除用户的阅读进度。

注：离线测试仅证明客户端实现契约，不能证明微信读书服务端一定会接受/长期保留每个会话。
