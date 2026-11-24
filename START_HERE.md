# 从这里开始（新电脑）

在实验室电脑上接手这个 4200A 控制包的全部步骤。GitHub 上每个代码块右上角都有复制按钮。

## 1. 先确认能上网

Claude Code 和 git 都要联网。如果这台电脑的网线改插到 4200A 以后就没网了，
**先完成第 2、3 步再换线**，或者让它用 Wi-Fi 上网。

## 2. 安装

- Git：<https://git-scm.com/download/win>
- Claude Code
- MATLAB R2021a 及以上，最好带 Instrument Control Toolbox；NI-VISA 可选

## 3. 下载这个仓库

```bash
git clone https://github.com/Yukino0906/4200_agent_assisted_testing.git C:\4200_agent_assisted_testing
```

## 4. 打开 Claude Code

```bash
cd C:\4200_agent_assisted_testing
```

```bash
claude
```

## 5. 第一条消息

最短的说法，直接打这一句就行：

```text
按 START_HERE.md 开始
```

它会照下面"给 agent 的第一次运行步骤"去做。想把要求写全的话，也可以发这一段：

```text
这是 4200A-SCS 的 agent 控制包，从另一台电脑接手过来。请先读 HANDOFF.md、AGENTS.md、docs/05_safety.md 和 docs/07_bring_up.md。然后用 where matlab 找到本机的 MATLAB，在后台运行 check_setup('192.168.0.2')（超时给 15 分钟），把结果告诉我：MATLAB 版本、Instrument Control Toolbox 和 NI-VISA 是否可用、test_dry_run 是否 0 failed、各网卡的 IPv4、能否 ping 通 4200A。在我明确同意之前，不要连接仪器、不要打开任何输出、不要改本机或 4200A 的网络设置。
```

## 6. 之后

- 网络设置、4200A 上的 KCon/KXCI、连接测试、电阻核对：按 [HANDOFF.md](HANDOFF.md) 第 2–3 节。
- 每次有改动或核对结果，commit 并 push 回这个仓库。push 需要登录 GitHub（`git push` 时会弹出登录窗口）。
- 这是**公开仓库**：不要提交测量数据（`data/` 已被忽略）、器件编号或个人信息。

---

## 给 agent 的第一次运行步骤

使用者说"按 START_HERE.md 开始"时，按顺序做，回复用中文：

1. 读 `HANDOFF.md`、`AGENTS.md`、`docs/05_safety.md`、`docs/07_bring_up.md`。
2. 用 `where matlab` 找 MATLAB；找不到就问使用者 `matlab.exe` 的路径。
3. 在后台运行（超时 15 分钟）：
   `matlab -batch "cd('<本仓库路径>'); check_setup('192.168.0.2')"`
4. 报告：MATLAB 版本；Instrument Control Toolbox 和 NI-VISA 是否可用；`test_dry_run` 是否
   0 failed；各网卡的 IPv4；能否 ping 通 `192.168.0.2`。ping 不通是正常的，说明网络还没配好，
   照 `HANDOFF.md` 第 2 节给出下一步。
5. 在使用者明确同意之前：不连接仪器，不打开任何输出，不改本机或 4200A 的网络设置。
