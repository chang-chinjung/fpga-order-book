# fpga-order-book · v0.1

[English](README.md) | [繁體中文](README.zh-TW.md) | 简体中文

一个用 Verilator 验证的 FPGA 限价订单簿原型（**价位聚合层级**），
重点不是功能多，而是把「规格 → RTL → 比对 → 变异测试 → 覆盖率 → 时序」的流程走完并留下数字。

> **v0.1 的范围**：价位总量 + 最佳买卖价。**没有**订单个体、队列、queue position。
> 版本定义见 [docs/VERSIONS.md](docs/VERSIONS.md)。

## 测量结果（16 级，ECP5 LFE5U-85F，nextpnr）

| 指标 | 单级 | 两级流水线 |
|---|---|---|
| 功能比对 | 222 steps ✅ | 222 steps ✅ |
| 变异测试得分 | 100%（29 killed / 1 equivalent） | 100%（同上） |
| RTL 行覆盖率 | 100%（35/35） | 100%（44/44） |
| Fmax | 95.65 MHz | 154.58 MHz |
| **延迟** | **10.45 ns** | 12.94 ns |
| 吞吐 | 95.7 M events/s | 77.3 M events/s |

**注意**：两级流水线的 Fmax 更高，但延迟和吞吐都更差。**Fmax 不是目标。**
完整分析见 [docs/TIMING.md](docs/TIMING.md)（中文）。

## 这是什么／不是什么

| 是 | 不是 |
|---|---|
| 价位聚合与最佳价的硬件原型 | 完整的订单簿（没有 FIFO、队列位置） |
| 一套可重复的验证流程（参考模型 + 变异测试 + 覆盖率） | 交易系统（没有行情解析、风控、下单） |
| 时序与 PPA 分析的示例 | 可直接上线的 IP |

## 目录

```
rtl/         order_book.sv（单级）、order_book_pipe2.sv（两级）、bitmap_best.sv（实验）
tb/          testbench（读取 stim/exp，逐笔比对）
model/       Python 参考模型与激励生成器
tools/       变异测试、覆盖率报告
docs/        SPEC / ARCH / DV / TIMING / VERSIONS / PLAN / HANDOFF
constraints/ XDC / SDC
```

## 快速开始

需要 Verilator ≥ 5.0、Python 3、Yosys、nextpnr-ecp5。

```bash
make sim          # 单级版：222 steps 比对
make sim-pipe2    # 两级版：同一组激励
python3 tools/mutate.py         # 变异测试（30 个变异体）
python3 tools/mutate_pipe2.py
make coverage     # RTL 行覆盖率，按文件分别统计
make pnr          # ECP5 place & route + Fmax
```

Windows 上可通过 WSL 运行：

```powershell
wsl -e bash -lc 'cd /mnt/d/.../fpga/order-book && make sim'
```

## 验证方法（三层）

| 层 | 抓什么 | 抓不到什么 |
|---|---|---|
| Python 参考模型比对 | 实现层错误（位宽、边界、顺序） | 共同误解规格 |
| 不变量 | 结构性矛盾（valid 与数量、范围） | 同上 |
| 变异测试 | 「测试有没有牙齿」 | 同上 |

变异测试抓到的两个真实缺口（详见 [docs/ARTICLE_EN.md](docs/ARTICLE_EN.md)）：

1. 移除 `cmd_valid` gate 后测试仍然全绿 —— testbench 从未插入空闲周期。
2. ask 侧的 8-bit 截断存活 —— ask 侧从未测过大数量。

## 文档

设计文档以繁体中文撰写；英文文章涵盖主要结论与数字。

- [docs/ARTICLE_EN.md](docs/ARTICLE_EN.md) — 技术文章（英文）
- [docs/ARTICLE.md](docs/ARTICLE.md) — 技术文章（繁体中文）
- [docs/VERSIONS.md](docs/VERSIONS.md) — v0.1 / v1.0 的界线
- [docs/SPEC.md](docs/SPEC.md) — 需求规格（v1.0 目标）
- [docs/ARCH.md](docs/ARCH.md) — 架构设计
- [docs/DV.md](docs/DV.md) — 验证计划与结果
- [docs/TIMING.md](docs/TIMING.md) — 时序测量与分析
- [docs/PLAN.md](docs/PLAN.md) — v0.1 / v1.1 计划
- [docs/PUBLISH.md](docs/PUBLISH.md) — 公开仓库检查清单

## 许可证

MIT，见 [LICENSE](LICENSE)。

## 已知限制

- 只有 16 级的 prototype 做过完整验证；1,024 级 bitmap 仍是实验。
- `order_book_pipe3.sv` 是失败的时序实验，保留作为记录。
- 所有 Fmax 都是 nextpnr 布局布线后的估计，不是 Lattice Diamond 签核数字。
- 还没有真实交易所数据 replay。
