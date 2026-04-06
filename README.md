# ai4verilog

`ai4verilog` 当前 README 仅介绍仓库中的 Verilog 相关内容，核心是一个基于状态机实现的 32-bit 单精度浮点加法器示例，以及配套的 testbench 和仿真说明。

## 项目概览

当前 Verilog 相关文件如下：

- `float_adder.v`：32-bit 单精度浮点加法器 RTL。
- `tb_float_adder.v`：功能验证 testbench。
- `prompt/ex1.txt`：该模块的原始需求描述。
- `outputs/float_adder_waveform_case1.png`：一次仿真的波形截图。

## 设计目标

[`float_adder.v`](./float_adder.v) 实现的接口如下：

```verilog
module float_adder(
    input               clk,
    input               rst_n,
    input               en,
    input      [31:0]   aIn,
    input      [31:0]   bIn,
    output reg          busy,
    output reg          out_vld,
    output reg [31:0]   out
);
```

根据 [`prompt/ex1.txt`](./prompt/ex1.txt) 中的需求，这个模块的设计前提包括：

- 输入 `aIn`、`bIn` 为 32-bit 单精度浮点数。
- 运算场景假定为正数相加。
- `en` 用于发起一次输入请求。
- `busy=1` 时模块处于工作状态，不接受新的输入。
- `out_vld` 在结果有效时拉高一个周期。

## 实现思路

模块使用时序状态机分阶段完成浮点加法运算，主要状态包括：

- `IDLE`：等待输入。
- `LATCH`：锁存输入数据。
- `UNPACK`：拆分指数与尾数。
- `ALIGN`：对较小操作数进行尾数右移对齐。
- `ADD`：完成尾数求和。
- `NORMALIZE`：对结果进行规格化。
- `PACK`：重新打包为 32-bit 浮点格式。
- `OUT`：输出结果并拉高 `out_vld`。
- `DONE`：结束本次计算并释放 `busy`。

实现中还定义了一个 `shift_right_limit_24` 函数，用于在指数差过大时限制移位范围，避免 24-bit 尾数移位溢出。

## 功能验证

[`tb_float_adder.v`](./tb_float_adder.v) 主要验证以下行为：

- 复位释放后模块处于空闲状态。
- 基本浮点加法结果正确。
- 指数不同场景下的尾数对齐正确。
- `0` 参与运算时结果正确。
- `busy` 拉高期间新输入会被忽略。
- `out_vld` 仅保持一个周期。
- 结果输出后 `busy` 能正确释放。

已覆盖的样例包括：

- `1.0 + 2.0`
- `1.5 + 2.25`
- `0.5 + 0.25`
- `4.0 + 0.125`
- `1.0 + 0.0`
- `255.0 + 1.0`
- `busy` 期间二次输入忽略场景

## 仿真环境

推荐使用 Icarus Verilog：

- `iverilog`
- `vvp`
或者Vivado使用
## 运行方式

编译并运行 testbench：

```bash
iverilog -g2012 -o /tmp/ai4v_float_adder_sim tb_float_adder.v float_adder.v
vvp /tmp/ai4v_float_adder_sim
```

如果需要查看波形，可在仿真后使用生成的 `tb_float_adder.vcd` 配合 GTKWave 等工具打开。

## 本地验证结果

本地已执行上述仿真命令，结果如下：

```text
[TB][PASS] reset release: outputs returned to idle state.
[TB][PASS] 1.0 + 2.0: out=0x40400000, latency=8 cycles.
[TB][PASS] 1.5 + 2.25: out=0x40700000, latency=8 cycles.
[TB][PASS] 0.5 + 0.25: out=0x3f400000, latency=8 cycles.
[TB][PASS] 4.0 + 0.125: out=0x40840000, latency=8 cycles.
[TB][PASS] 1.0 + 0.0: out=0x3f800000, latency=8 cycles.
[TB][PASS] 255.0 + 1.0: out=0x43800000, latency=8 cycles.
[TB][PASS] busy-ignore: second request while busy was ignored as expected.
[TB] simulation done: pass=8, fail=0
```

仓库内还保留了一张示例波形图：

- `outputs/float_adder_waveform_case1.png`

## 当前限制

这个实现更适合教学、演示和基础实验，不是完整的 IEEE 754 工业级浮点加法器。当前限制主要包括：

- 仅面向正数输入场景。
- 未完整处理符号位加减。
- 未系统覆盖 NaN、Infinity、非规格化数等特殊情况。
- 规格化与边界处理仍是简化实现。
- 设计重点是流程清晰和 testbench 可验证性，而不是高吞吐或高性能流水化。

## 后续可扩展方向

- 增加负数与减法相关处理逻辑。
- 补充更多特殊值与边界条件测试。
- 增加自动化回归脚本。
- 完善舍入、规格化左移与异常值处理。
- 将当前状态机实现扩展为更高性能的流水方案。
