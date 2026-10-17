# 6.0.0-beta.1 Verification

- `tools/verify_600_beta1.py`: validates 6.0.0-beta.1 identity, Schema 136, inherited progress/shelf/bookstore contracts, lean-package boundaries, same-account Native shelf-auth preservation, independent shelf-auth revocation, bookstore copy polish, and StorePerf log throttling.
- Historical contract tests for beta.19 mapping and 5.9.1-beta.1 progress recovery no longer pin the current release to an old version string; they continue to validate the retained behavior.
- Release workflow still installs Lua 5.1 and LuaJIT and runs the production regression set before packaging.

## 译文批量下载（2026-10-17）

- `python tools/test_translation.py`：运行全部离线翻译回归，需要 `lupa`、`lxml`、`tinycss2`、`cssselect2`。窗口规划覆盖连续短章、长章、缺失字数、目录页、书末、单章/范围边界与已有译文；模拟官方响应验证逐章完成、已完成下一章复用、一次会员检查、后续章超时保留已完成部分、整批等待上限和取消传播。
- 阅读集成验证显示模式与离线下载独立、所有译文任务后台运行、当前章已有译文时主动补齐后续章节、全部已缓存时跳过下载，以及普通显示模式切换的原有行为。智能窗口约 8,000 字、至少 3 章且最多 20 章，边界只属于内部策略。
- 真实 EPUB 回归验证整批只暂存一个新文件、实际就绪章数、已有译文丢失时拒绝替换、原文与批注位置迁移、原子安装及重开后的显示模式。离线测试不等于微信读书服务或 Kindle 真机验收。
- 真机复核：选择连续短章的外文书，点击“先下载接下来几章”；下载期间继续翻页并切换阅读方式，然后点击“应用译文”，检查当前位置、后续多章译文、原有划线与所选阅读方式。旧版不支持原生 reload 回调时须保留待应用内容并提示手动关闭再打开。
- 整本后台任务：离线覆盖超过 20 章及 5 分钟的完整范围、当前章优先、补齐此前章节、目录页起读、后续章超时后继续处理、已完成生成断点复用与版本过期判断。真实下载器准备方法验证逐章保存断点、中断后续传、书籍版本/目录变化时作废旧结果、存储失败时停止请求；内容缓存仅在译文版本足够且正文确有译文时复用。
- 整本真机复核：在完整原文 EPUB 的中间章节点击“下载整本译文”，确认可继续阅读，下载管理可暂停/继续，后台完成不弹出模态框；随后一键应用，抽查书首、当前位置和书末译文。单章版/范围版须保持原文件范围，不将局部文件误标为全书已完成。
- `tools/test_translation_ux.lua` 随翻译回归运行：覆盖未下载、部分可用、已全部下载、排队、准备中、暂停、中断和待应用等状态，以及跨书/跨路径任务隔离、手动暂停原因解除、原生 reload 的关闭/保存/安装/重开顺序、失败与旧版兜底。真实 EPUB 回归额外验证一键应用使用最终位置、保留阅读方式，以及排队任务在阅读其他书籍时完成也必须迁移原有阅读记录。
- 仅译文可用性：同章及跨章节的部分未配对译文不再禁用所有已验证的段落。Lua、实际 CSS 匹配和真实 EPUB 打包回归验证只隐藏已确认对应的原文，未配对内容保留双语；完全未配对时可点击查看原因，并区分未下载、待应用与检查失败。下载后发现完全不支持仅译文时仍保留有效译文，安装使用双语并明确提示，不让已选模式导致译文不可见。
