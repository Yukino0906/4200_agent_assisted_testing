# 4200A 接手说明（HANDOFF）

最后更新：2026-11-24。读者：实验室电脑上的 Claude Code，以及使用者本人。
原工作机上的会话记忆不会跟过来；这里写的就是全部上下文。**做出新决定或核对出新结果，
就更新本文件并 commit。**

## 0. 当前状态

- 工具包已写完：laptop（或实验室电脑）上的 MATLAB 通过 Keithley 的 **KXCI** 接口控制
  4200A-SCS。读数和 DC 扫描走 SMU；写脉冲走 4225-PMU（硬件计时的梯形脉冲）；每次读和写之前
  程序自动切换 RPM 通路。
- 已验证（只在软件里）：`test_dry_run` 68 passed / 0 failed（模拟器 + 软件模拟的 4200A，
  即 `KxciMock`），`test_examples` 7 / 0，checkcode 0。
- **还没在真 4200A 上连过。** `docs/07_bring_up.md` 的电阻核对 A–I 全部未做，记录表是空的。
- 第一步先跑 `check_setup`（见第 3 节）。

## 1. 硬件（使用者确认，含背板照片）

- 4200A-SCS：**1 块 SMU（SMU1）**，**1 块 4225-PMU**，**2 个 4225-RPM**。
- 背板左侧是内置 Windows 电脑的接口：**4 个 RJ45 网口**。其中一个插着灰色 CAT5e 跳线、
  橙灯亮，接的应是楼里网络，**不要拔、不要改它的网卡设置**。另外三个空着。
- 写着 "HDMI Cable with Ethernet" 的线是显示器线，不是网线。
- 背板右侧 GNDU 面板：**FORCE 上接了一根黄色三同轴线**，所以回路走 GNDU，对应
  `cfg.instrument.return_path = 'gndu'`（默认值）。待确认黄线接到探针台的哪里
  （第二根探针还是卡盘）。
- 实验室电脑（Windows）用网线接到 4200A 的一个空网口。

## 2. 网络

- **Claude Code 和 git 都要上网。** 如果实验室电脑唯一的有线网口改接了 4200A，它的有线网就断了：
  用 Wi-Fi，或加一个 USB 网卡。最稳的顺序是先 `git clone`，再换线。
- 直连的两端都设静态 IP，**不填网关**（这样上网仍走另一块网卡）：
  - 实验室电脑接 4200A 的那块网卡：`192.168.0.1`，掩码 `255.255.255.0`
  - 4200A 上刚变成"已连接"的那块网卡：`192.168.0.2`，掩码 `255.255.255.0`。
    需要管理员权限，请管设备的人操作。
- 备选：两边都设成自动获取时，通常会各自拿到 `169.254.x.x`，也能互通，用 4200A 的那个
  `169.254` 地址作为 host。
- 能 ping 通但连接被拒绝：先查 KXCI 有没有开、端口对不对；再查 4200A 的 Windows 防火墙
  （新网络常被当成"公用网络"，会拦 KXCI 端口）。

## 3. 第一次使用的顺序

1. **装好或确认**：MATLAB R2021a 及以上，带 Instrument Control Toolbox（没有的话用
   `cfg.instrument.transport = 'tcpclient'`）；NI-VISA（可选）；Git；Claude Code。
2. **自检**（不连仪器、不加电压）：
   ```bash
   matlab -batch "cd('<本仓库路径>'); check_setup('192.168.0.2')"
   ```
   要求 `test_dry_run: yes`，并看清各网卡的 IPv4。
3. **4200A 上**：KCon → KXCI Settings → 选 Ethernet，记下端口（Keithley 示例用 1225）→ 保存；
   **关掉 Clarius**，打开 KXCI。
4. **ping**：`ping 192.168.0.2`。
5. **连接测试**（只给 0 V，探针放下也安全）：
   ```matlab
   cd <本仓库路径>; setup_paths
   cfg = default_config();
   cfg.mode.simulate_instrument = false;
   cfg.mode.dry_run             = true;
   cfg.instrument.host = '192.168.0.2';
   cfg.instrument.port = 1225;
   cfg.instrument.resource_candidates = {sprintf('TCPIP0::%s::%d::SOCKET', ...
       cfg.instrument.host, cfg.instrument.port)};
   cfg.instrument.resource = cfg.instrument.resource_candidates{1};
   test_instrument_connection(cfg)
   ```
   改 host 时必须同时改 `resource_candidates`：资源字符串是在 `default_config()` 里拼好的，
   事后只改 host 不会生效。
6. **电阻核对**：按 `docs/07_bring_up.md` 用 100 kΩ 和 1 kΩ 电阻做 A–I，填记录表。
   核对出的设置改进 `config/default_config.m`，并把 `docs/04_kxci_cheatsheet.md` 里对应条目
   从 UNVERIFIED 改为已验证（写日期）。
7. 以上都通过之后，才上器件。

## 4. 尚未验证的假设（核对清单的对应项）

| 假设 | 当前设置 | 核对项 |
|---|---|---|
| 网口上 KXCI 对每条命令都回一个确认字符串 | `ack_mode = true`，`ack_pattern = '^ACK'` | A |
| `TI1` 的回复格式（裸数字或 4145 式前缀 `NAI+…`） | 解析器两种都接受 | B |
| RPM 切到 SMU 通路的代码 | `cfg.pmu.rpm_code_smu = 3` | C |
| 第二根探针接 RPM2 时，PMU CH2 在 SMU 读数时保持 0 V | 默认不用（`'gndu'`） | D |
| PMU 实际脉宽、电流符号和大小 | 梯形的 FWHM | E、F |
| PMU 超量程时软件电流上限能触发 | `max_current_A ≤ 0.95 × 量程` | G |
| MATLAB 被杀后输出能关掉 | `test_instrument_connection` | H |
| 被拒收的命令能被发现 | 不匹配 ack 即计为错误 | I |

## 5. 规则摘要（完整版见 `AGENTS.md` 和 `docs/05_safety.md`）

- 电压不超过器件文件里的 `cfg.safety.max_abs_voltage`；代码拒绝任何高于 5 V 的值。
- **PMU 没有硬件限流。** forming 和第一次 SET 只用 SMU；PMU 的电流上限由使用者给出。
- 三个确认开关（`compliance_confirmed`、`limits_confirmed`、`pmu.no_compliance_acknowledged`）
  只有使用者能打开，或者使用者在对话里明确批准后由 agent 打开；每个器件、每个会话单独批准。
- 电阻核对没过，不上器件；标着 UNVERIFIED 的设置只能因核对结果而改。
- 测量运行时不改任何 `.m` 文件；后台硬件任务的超时必须长于整个流程。
- MATLAB 被杀以后，先跑 `test_instrument_connection` 把输出全关掉。
- 同一时间只有一个程序控制仪器：Clarius 关掉，不开第二个 MATLAB。
- `data/raw/` 只追加，不改不删；`data/` 不进 git（见 `.gitignore`）。

## 6. 已知坑

- 改 host 不改 `resource_candidates`，连接会去旧地址（第 3 节第 5 步）。
- 很长的批处理里第一次开图形窗口，`test_examples` 曾偶发一次 "Out of memory"；单独重跑通过。
- `matlab -batch` 结束时可能返回非零退出码，但其实已经跑完：以 `run_summary.txt` 和日志为准。
- 判断后台任务是否还活着，看最新 `data/raw/*` 目录里的文件是否还在增长，不要只看进程列表。

## 7. 给 agent 的工作方式

- 回复使用者用中文；代码、注释、文件名用英文。
- MATLAB 路径：先运行 `where matlab`，找不到就问使用者。
- 第一次在这台电脑上运行时：先读本文件、`AGENTS.md`、`docs/05_safety.md` 和
  `docs/07_bring_up.md`；跑 `check_setup`；把结果告诉使用者；**未经使用者明确同意，
  不连仪器、不打开任何输出、不改本机或 4200A 的网络设置。**
- 每完成一项核对，就更新本文件第 0 节和 `docs/07_bring_up.md` 的记录表，并 commit。
