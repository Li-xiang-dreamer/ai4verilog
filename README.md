# ai4verilog

`ai4verilog` 是一个包含两类实验内容的小型项目：

1. 一个基于有限状态机实现的 32-bit 单精度浮点加法器 Verilog 示例。
2. 一个针对红外灰度矩阵数据的边缘增强 Python 脚本。

当前仓库更适合作为课程实验、功能演示和流程验证样例，而不是完整的产品级实现。尤其是 Verilog 部分，设计目标明确限定在“正数输入”的浮点加法场景。

## 项目概览

项目中已经落地了以下内容：

- `float_adder.v`：32-bit 浮点加法器 RTL。
- `tb_float_adder.v`：面向功能验证的 testbench。
- `infrared_edge_enhance.py`：读取 txt 灰度矩阵并执行预处理、边缘检测和增强。
- `sample_ir.txt`：红外图像样例输入。
- `outputs/`：已生成的图像处理结果和一张 Verilog 波形截图。
- `prompt/ex1.txt`：该浮点加法器需求的原始文字提示词。

## 仓库结构

```text
ai4verilog/
├── .gitignore
├── README.md
├── float_adder.v
├── tb_float_adder.v
├── infrared_edge_enhance.py
├── sample_ir.txt
├── prompt/
│   └── ex1.txt
└── outputs/
    ├── edge_response.png
    ├── enhanced.png
    ├── float_adder_waveform_case1.png
    ├── original.png
    ├── pipeline_overview.png
    └── preprocessed.png
```

## 依赖环境

### Verilog 仿真

- `iverilog`
- `vvp`

推荐使用 Icarus Verilog 进行编译与仿真。

### Python 图像处理

- Python 3.10+
- `numpy`
- `matplotlib`
- `opencv-python`

可使用如下命令安装：

```bash
python3 -m pip install numpy matplotlib opencv-python
```

## Verilog 部分

### 设计目标

[`float_adder.v`](./float_adder.v) 实现了一个 32-bit 单精度浮点加法器接口：

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

从 [`prompt/ex1.txt`](./prompt/ex1.txt) 可以看出，这个模块的需求前提是：

- 输入 `aIn`、`bIn` 为单精度浮点格式。
- 参与运算的数据假定为正数。
- `en` 用于发起一次输入握手。
- `busy=1` 时模块不接受新的输入。
- `out_vld` 在结果有效时拉高一个周期。

### 实现思路

模块通过状态机依次完成以下步骤：

- `IDLE`：等待输入请求。
- `LATCH`：锁存输入操作数。
- `UNPACK`：拆分指数和尾数。
- `ALIGN`：比较指数并对较小尾数右移对齐。
- `ADD`：完成尾数求和。
- `NORMALIZE`：规格化结果。
- `PACK`：重新打包为 32-bit 浮点格式。
- `OUT`：输出结果并拉高 `out_vld`。
- `DONE`：收尾并释放 `busy`。

实现里还包含一个 `shift_right_limit_24` 辅助函数，用于在指数差大于等于 24 时直接将较小尾数清零，避免越界移位。

### 功能验证

[`tb_float_adder.v`](./tb_float_adder.v) 覆盖了以下场景：

- 复位后空闲状态检查
- 基本浮点加法
- 不同指数下的尾数对齐
- 与 0 相加
- 较大数值加法
- `busy` 期间输入忽略检查
- `out_vld` 单周期脉冲检查

本地已执行的仿真命令：

```bash
iverilog -g2012 -o /tmp/ai4v_float_adder_sim tb_float_adder.v float_adder.v
vvp /tmp/ai4v_float_adder_sim
```

本次运行结果为：

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

仓库中还提供了一张波形截图：

- `outputs/float_adder_waveform_case1.png`

### Verilog 局限说明

该实现适合教学与演示，当前并不是完整 IEEE 754 加法器，主要限制包括：

- 默认只考虑正数输入，不处理符号位加减。
- 未系统覆盖 NaN、Infinity、非规格化数等完整边界行为。
- 规格化逻辑较简化，更适合展示基本流程而非高精度工业实现。
- 时序结构是串行状态推进，重点是可读性和可验证性，而不是吞吐率优化。

## Python 红外图像增强部分

[`infrared_edge_enhance.py`](./infrared_edge_enhance.py) 用于处理存储为 txt 矩阵的红外灰度图像数据，处理流程如下：

1. 读取二维灰度矩阵。
2. 归一化到 `[0, 1]`。
3. 使用高斯滤波预处理。
4. 可选使用双边滤波进一步抑制噪声。
5. 融合 Sobel、Scharr、Laplacian 三种边缘响应。
6. 通过细节增强和边缘注入生成增强结果。
7. 可视化并可选保存中间图与总览图。

### 输入与输出

- 输入样例：[`sample_ir.txt`](./sample_ir.txt)
- 输出目录：[`outputs/`](./outputs)

已存在的输出文件包括：

- `outputs/original.png`
- `outputs/preprocessed.png`
- `outputs/edge_response.png`
- `outputs/enhanced.png`
- `outputs/pipeline_overview.png`

### 使用方式

安装依赖后，可通过如下命令运行：

```bash
python3 infrared_edge_enhance.py sample_ir.txt --save-dir outputs --no-show
```

如果输入 txt 使用特定分隔符，可显式指定：

```bash
python3 infrared_edge_enhance.py sample_ir.txt --delimiter " " --save-dir outputs --no-show
```

如果希望关闭双边滤波：

```bash
python3 infrared_edge_enhance.py sample_ir.txt --disable-bilateral --save-dir outputs --no-show
```

### 当前环境验证情况

本地尝试运行脚本时，当前环境缺少 Python 依赖，因此未直接完成一次重跑。缺失信息如下：

```text
ModuleNotFoundError: No module named 'cv2'
```

也就是说，脚本本身已经在仓库中就绪，但运行前需要先安装 `opencv-python`，通常也需要一并安装 `numpy` 与 `matplotlib`。

## 快速开始

### 只验证 Verilog 模块

```bash
iverilog -g2012 -o /tmp/ai4v_float_adder_sim tb_float_adder.v float_adder.v
vvp /tmp/ai4v_float_adder_sim
```

### 只运行图像增强脚本

```bash
python3 -m pip install numpy matplotlib opencv-python
python3 infrared_edge_enhance.py sample_ir.txt --save-dir outputs --no-show
```

## 这个项目适合做什么

- AI 生成 Verilog 示例的整理与展示
- 基础数字设计实验的代码样例
- 浮点加法器状态机流程讲解
- 机器视觉预处理与边缘增强实验
- 将自然语言需求转成代码原型的教学展示

## 后续可扩展方向

- 为浮点加法器补全负数、规格化左移、舍入和特殊值处理
- 增加更多 testbench 用例与自动化回归脚本
- 为 Python 部分补 `requirements.txt`
- 提供 Jupyter Notebook 或命令行批处理版本
- 将 Verilog 和图像处理实验拆分为更清晰的子目录

## 说明

仓库当前分支中已经包含一组示例输出文件，便于直接查看结果。如果后续打算继续扩展这个项目，比较推荐优先补上：

1. `requirements.txt`
2. 更系统的 testbench 自动化
3. 更完整的模块功能边界说明
