# macOS AppleSystemPolicy GUI 启动拒绝

这是一个中文辅助说明，英文版 [README.md](README.md) 是主文档。

本仓库记录一种 macOS 故障模式：新安装的应用从 Finder、Dock、Spotlight
或 `open` 启动时看起来像“闪退”，但应用二进制本身未必崩溃。真实现象可能是
GUI 启动路径被 AppleSystemPolicy 拒绝。

这不是 Apple 官方 bug 报告，也不能证明唯一根因。

## 症状

- 很多新安装的应用一打开就退出。
- `~/Library/Logs/DiagnosticReports` 下面没有普通崩溃报告。
- 直接执行应用主二进制有时能正常启动。
- `codesign`、`spctl --type execute` 或公证检查可能通过。

典型日志：

```text
AppleSystemPolicy: ASP: Security policy would not allow process: <pid>, /Applications/Antigravity.app/Contents/MacOS/Antigravity
```

## 这代表什么

这类信号更像 macOS 启动/安全策略问题，而不是单个 app 的代码问题。

本次观察到：

- `/Applications/Antigravity.app` 通过签名和公证检查。
- 直接执行二进制可以启动。
- 通过 LaunchServices 的 GUI 启动路径会被 AppleSystemPolicy 杀掉。
- 多个 app bundle 上残留了 `com.apple.provenance`、`com.apple.macl` 或
  `com.apple.quarantine` 扩展属性。
- Gatekeeper 评估状态一度为 disabled，修复时恢复为 enabled。
- 重启策略/信任评估服务并清理 stale 启动来源属性后，GUI 启动恢复。

## 诊断

检查 Gatekeeper 状态：

```sh
spctl --status
```

评估指定 app：

```sh
app="/Applications/Antigravity.app"
spctl --assess --type execute -vv "$app"
codesign --verify --deep --strict --verbose=2 "$app"
```

启动时观察系统策略日志：

```sh
/usr/bin/log stream --style compact --timeout 20 \
  --predicate 'eventMessage CONTAINS[c] "Security policy would not allow process" OR eventMessage CONTAINS[c] "AppleSystemPolicy"'
```

对比 GUI 启动和直接二进制启动：

```sh
open -n /Applications/Antigravity.app
/Applications/Antigravity.app/Contents/MacOS/Antigravity
```

如果直接执行可以跑，而 GUI 启动被拒绝，优先怀疑 LaunchServices、
Gatekeeper、provenance/quarantine 状态或系统策略缓存。

## 修复思路

本次有效的修复路径：

1. 重新启用 Gatekeeper 评估。
2. 清理 app bundle 上 stale 的启动来源扩展属性。
3. 重新注册 LaunchServices。
4. 重启策略和信任评估相关服务。
5. 用 `open`、进程检查和 fresh log 验证。

辅助脚本：

```sh
scripts/diagnose-launch-policy.sh "/Applications/Antigravity.app"
scripts/repair-launch-policy-cache.sh
scripts/repair-launch-policy-cache.sh --apply
```

修复脚本默认 dry-run，只有显式传入 `--apply` 才会实际操作。

## 是否应该报告给 Apple

Apple 通常不通过公开 GitHub issue 处理 macOS 系统 bug。若能稳定复现，建议用
Feedback Assistant，并附上：

- `sysdiagnose`
- macOS 版本和 build
- 受影响 app 路径和 bundle ID
- `spctl`、`codesign`、`log stream` 证据
- 直接二进制执行和 GUI 启动是否不同

## 不要误判

- 不要默认认为每个受影响 app 都坏了。
- `spctl --type execute` accepted 不等于 GUI 启动链一定正常。
- 不要把密码、token 或私人日志贴到公开报告里。
- 不要盲目删除 `/var/db/SystemPolicyConfiguration`。

## 本次环境

- macOS 26.5.1, arm64
- 受影响样本包含 Electron 风格 app 和 iOS wrapper app
- 主要恢复样本：Antigravity

## 状态

修复后，Antigravity 可通过 `open` 启动并保持运行，helper 进程正常出现；
验证窗口内没有再出现新的 AppleSystemPolicy deny。
