# 仓库拆分记录

2026-11-19，采用用户选择的方案 A：`Resker666/minimal-sleep` 保留 Android，
`Resker666/minimal-sleep-ios` 独立维护 iOS。Mac 是开发环境，不是新增的应用目标。

## 来源与历史

- 播放主干来源：`eea22b14acb46fb0f4e2e7e8d1fc728b1cbc3528`。
- 夜间录音分支来源：`95ab67906136e81041df685ed30dc47a113108cc`。
- 新提交分离当前工作树，保留原提交祖先；不改写原仓库历史、不强推。
  因此旧历史中仍能看到 Android 文件，这不构成当前构建依赖。
- 播放主干与录音开发分支分别保存。录音功能是否合入需单独审阅、验证。
- 原 Issues、PR、Android Releases 留在原仓库；历史 CI 链接仍指向原验证记录。

## 路径与资源

保留 `ios/` 以避免无关 Xcode 路径改动。两段 Ogg 从原
`app/src/main/assets/local-sounds/` 逐字节复制至本仓库 `assets/source-audio/`；
不再要求克隆 Android。三段 WAV、Swift 源码、XCTest、Xcode 工程、Bundle ID
和版本号均按对应来源保留。派生清单只改源路径，预期输出哈希不变。

每端维护自己的 README、AGENTS、CI、素材清单和许可证。暂不采用共享素材仓库
或 Git 子模块，后续素材变更需要显式决定是否同步。

## 完成门槛

新远端的两条分支、独立克隆、音频生成和平台 CI 均确认后，才合入 Android 清理 PR。
本记录描述迁移约定，远端创建、CI 和实际测试状态以对应验证记录及 PR 为准。

回退可关闭未合并的清理 PR，或对已合并迁移提交做 revert；不要删除开发分支或强推历史。
