# 纯终端手动修复指南

这个指南给没有 AI agent 的用户使用。你可以自己在 Terminal 里完成诊断和修复。

适用现象：应用从 Finder、Dock、Spotlight 或 `open` 启动后马上退出，并且系统
日志里出现 AppleSystemPolicy 拒绝。

## 开始前

- 你需要管理员账号。
- `sudo` 可能会要求输入 Mac 密码。直接在 Terminal 输入即可，屏幕上不会显示。
- 不要把密码、token 或私人日志贴到公开 issue。
- 先拿一个受影响 app 测试。把下面路径换成你的 app 路径。
- 下面可复制命令兼容 macOS Terminal 默认的 `zsh`。

```sh
APP="/Applications/Antigravity.app"
```

## 第 1 步：确认现象

运行：

```sh
APP="/Applications/Antigravity.app"
open -n "$APP"
sleep 8
pgrep -afil "$(basename "$APP" .app)" || true
```

如果没有进程留下来，说明 app 可能被系统拒绝或自己崩溃了。

再开一个日志监听窗口：

```sh
/usr/bin/log stream --style compact --timeout 30 \
  --predicate 'eventMessage CONTAINS[c] "Security policy would not allow process" OR eventMessage CONTAINS[c] "AppleSystemPolicy"'
```

在另一个 Terminal 窗口启动 app：

```sh
open -n "$APP"
```

如果看到类似下面的日志，这个指南就适用：

```text
ASP: Security policy would not allow process: <pid>, /Applications/Your.app/Contents/MacOS/YourApp
```

## 第 2 步：检查签名和 Gatekeeper

运行：

```sh
spctl --status
spctl --assess --type execute -vv "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
xattr -l "$APP" 2>/dev/null || true
```

注意：

- `spctl --type execute` 显示 `accepted`，不代表 GUI 启动链一定正常。
- 某些 app 的 `spctl --type open` 可能显示 `rejected` 和 `Insufficient Context`；
  这本身不能证明 app 坏了。
- 如果直接执行二进制能启动，但 GUI 启动失败，优先怀疑 macOS 启动策略路径：

```sh
"$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
```

如果它成功启动，可以按 `Control-C` 停掉。

## 第 3 步：如果是复发，先试无 sudo 的用户级刷新

如果这是同一个问题再次出现，并且 `spctl --status` 已经显示
`assessments enabled`，可以先试这个影响更小的刷新。它不需要 `sudo`，不会删除
app，只会从顶层 app bundle 移除三类启动来源扩展属性。

```sh
for root in /Applications "$HOME/Applications"; do
  [ -d "$root" ] || continue
  find "$root" -maxdepth 1 -name '*.app' -print 2>/dev/null |
  while IFS= read -r app; do
    echo "$app"
    for attr in com.apple.quarantine com.apple.provenance com.apple.macl; do
      xattr -dr "$attr" "$app" 2>/dev/null || true
    done
  done
done

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -r -domain local -domain system -domain user

killall -u "$USER" cfprefsd sharedfilelistd 2>/dev/null || true
spctl --status
```

然后跳到验证步骤。如果受影响 app 仍然失败，再继续下面需要管理员权限的修复。

## 第 4 步：先做单个 app 的定向修复

这一步只清理受影响 app 上的 stale 启动来源扩展属性，并重新注册 LaunchServices。

```sh
APP="/Applications/Antigravity.app"

sudo /usr/sbin/spctl --master-enable

for attr in com.apple.quarantine com.apple.provenance com.apple.macl; do
  sudo xattr -dr "$attr" "$APP" 2>/dev/null || true
done

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -r -domain local -domain system -domain user

killall -u "$USER" cfprefsd sharedfilelistd 2>/dev/null || true
```

重启策略和信任评估服务。macOS 的 launchd 会自动把它们拉起来：

```sh
sudo killall syspolicyd 2>/dev/null || true
sudo killall com.apple.CodeSigningHelper 2>/dev/null || true
sudo killall trustd 2>/dev/null || true
sudo killall trustevaluationagent 2>/dev/null || true
sudo killall amfid 2>/dev/null || true

sleep 2
spctl --status
```

## 第 5 步：如果很多 app 都受影响

如果多个新安装 app 都同样失败，可以对 `/Applications` 和 `~/Applications` 顶层
app bundle 清理同样的扩展属性。

先读一遍下面命令。它只删除三类扩展属性：
`com.apple.quarantine`、`com.apple.provenance`、`com.apple.macl`。

```sh
find /Applications "$HOME/Applications" -maxdepth 1 -name '*.app' -print 2>/dev/null |
while IFS= read -r app; do
  echo "$app"
  for attr in com.apple.quarantine com.apple.provenance com.apple.macl; do
    sudo xattr -dr "$attr" "$app" 2>/dev/null || true
  done
done

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -r -domain local -domain system -domain user

sudo /usr/sbin/spctl --master-enable
sudo killall syspolicyd 2>/dev/null || true
sudo killall com.apple.CodeSigningHelper 2>/dev/null || true
sudo killall trustd 2>/dev/null || true
sudo killall trustevaluationagent 2>/dev/null || true
sudo killall amfid 2>/dev/null || true
```

## 第 6 步：验证

再次启动受影响 app：

```sh
APP="/Applications/Antigravity.app"
open -n "$APP"
sleep 8
pgrep -afil "$(basename "$APP" .app)" || true
```

检查最近是否还有新的拒绝日志：

```sh
/usr/bin/log show --last 2m --style compact \
  --predicate 'eventMessage CONTAINS[c] "Security policy would not allow process"' |
tail -80
```

成功状态通常是：

- app 进程还在运行；
- helper 进程可能也出现；
- 最近日志里没有这个 app 的新 `Security policy would not allow process`。

## 使用仓库脚本的方式

如果你愿意使用本仓库脚本：

```sh
git clone https://github.com/bozliu/macos-apple-systempolicy-launch-deny.git
cd macos-apple-systempolicy-launch-deny

scripts/diagnose-launch-policy.sh "/Applications/Antigravity.app"
scripts/repair-launch-policy-cache.sh
scripts/repair-launch-policy-cache.sh --apply
```

修复脚本默认是 dry-run。只有 `--apply` 那一次会真的修改状态。

## 如果仍然失败

先重启一次 Mac，然后再跑验证步骤。

如果仍然失败：

- 不要盲目删除 `/var/db/SystemPolicyConfiguration`；
- 记录准确 app 路径、bundle ID、macOS 版本和相关日志；
- 运行 `sudo sysdiagnose`；
- 通过 Apple Feedback Assistant 上报。

Apple 通常不通过公开 GitHub issue 处理 macOS 系统 bug。
