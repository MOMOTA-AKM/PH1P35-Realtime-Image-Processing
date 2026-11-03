# 基于安路 PH1P35 的实时数字图像处理系统

以 MIPI 摄像头采集、图像处理、DDR 帧缓存和 HDMI 显示为主线，以蓝绿车牌识别与稳定跟踪为自主创意应用。

本仓库公开项目新增的图像算法、识别控制逻辑和代表性模块测试。原厂视频平台、第三方 IP、Logo、字体点阵和标定素材不随公开仓库分发；本仓库的 MIT 许可证不适用于这些外部依赖。完整上板构建需要自行取得兼容且获准使用的平台依赖，见 [第三方依赖说明](THIRD_PARTY.md)。

## 功能

- 1280×720 实时视频通路，COLOR 彩色与 EDGE Sobel 边缘模式。
- 蓝绿车牌候选定位、位置关联、平滑跟踪和按需 ROI 采样。
- 自适应前景提取、字符分割与归一化、多特征模板匹配。
- 最近五次有效整牌结果中三次一致确认，历史文字保持。
- 目标框、模式、识别结果及 OCR 任务耗时显示，LED 和数码管状态输出。
- 紧凑字库、串行运算和共享地址计算。

## 平台

| 项目 | 配置 |
|---|---|
| 开发板 | HX1P35A，PH1P35MDG324，速度等级 -3 |
| 摄像头 | SC520CS，2-Lane MIPI RAW10 |
| 综合工具 | Tang Dynasty 6.2.1（6.2.168116） |
| 显示 | HDMI，1280×720；像素时钟约 75 MHz |
| 交互 | 按键一 COLOR，按键二 EDGE |

白平衡、MIPI、DDR、HDMI 等属于外部平台依赖；闭环自动曝光、帧差运动检测和数值坐标显示未包含在自研功能中。COLOR 不是全屏二值化。OCR 耗时测量 ROI 采样启动至 OCR 完成，不是采集至显示的端到端延迟。视频持续输出，完整 OCR 按需执行。

## 目录

```text
rtl/        图像、识别、跟踪与控制模块
sim/        无照片素材依赖的代表性测试
tools/      依赖导入、TD 工程生成和构建入口
docs/       模块说明和参考验证结果
```

## 运行模块仿真

需要可用且已授权的 ModelSim/Questa。在 `sim` 目录执行：

```powershell
vsim -c -do core.do
```

也可使用 XSim：

```powershell
python tools/test_xsim.py --vivado "D:/Xilinx/Vivado/2023.2"
```

该入口覆盖 11 个代表性模块测试，不依赖原厂视频 IP、Logo 或 OCR 模板素材；编译使用 `LPR_BEHAVIORAL_RAM` 同步行为存储模型。2026-11-03 在 XSim 2023.2 下独立复跑，11 项均通过。它不代表完整摄像头链路、布局布线网表或板级验证。原始完整版记录与本仓库实际复跑结果分别见 [验证说明](docs/VALIDATION.md)。

## 完整工程构建

从官方/权利人渠道取得可使用的 SC520 平台及配套数据。若已有本项目 v24 完整工程，可导入本地副本：

```powershell
python tools/import_dependencies.py --from-project "C:/FPGA/sc520_plate_only"
python tools/prepare_project.py --variant cn
powershell -NoProfile -File tools/build.ps1 -TdRoot "C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116"
```

导入工具不会下载依赖，也不改变第三方许可；需要保持匹配的官方目录结构、配置、字库和模板。`prepare_project.py` 会生成/更新被 Git 忽略的顶层、约束、工程与初始化文件，请勿将手工修改仅保存在这些生成文件中。

连接摄像头 MIPI 排线、HDMI 显示器及 USB供电与下载通信线；管脚以本地导入的匹配版本约束为准。完整构建输出在 `build/public`，使用 TD Programmer 加载 `hx1p35_lpr.bit`。上板前检查最终 setup/hold 时序报告。

## 许可

自研源码及本仓库新编写的说明采用 [MIT](LICENSE)。外部平台、字体、模板、照片、Logo 等保留各自权利与许可，详见 [THIRD_PARTY.md](THIRD_PARTY.md)。请勿将本仓库许可证扩展到本地导入的依赖文件。
