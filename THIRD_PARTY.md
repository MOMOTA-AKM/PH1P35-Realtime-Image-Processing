# 第三方依赖与来源边界

本项目的视频平台来自 HX1P35A 配套 SC520 摄像头例程 `lab_ex3_osd_SC520`。来源目录中存在 Anlogic 版权标记及 MiLianKe 的 `All rights reserved` 声明；本次检查未发现覆盖整个第三方目录的公开再分发许可证。因此公开仓库不分发以下文件，不对其追加 MIT 授权。

| 外部内容 | 原工程位置 | 获取/使用方式 |
|---|---|---|
| MIPI/CSI/RAW10、ISP、DDR、HDMI、PLL/FIFO IP及原厂顶层 | vendor/ | 通过安路/HX1P35A 配套资料及相关权利人渠道取得，并遵守原许可 |
| 摄像头寄存器表、I²C总线、Logo等 | vendor/ | 使用对应 SC520CS 例程，保留来源声明 |
| 字体点阵、OCR模板及其标定数据 | assets/cn/、*.mem、lpr_cn_font.v | 使用获准的匹配数据；生成脚本曾使用 Windows 字体，不据此推定其可再分发 |
| 顶层、引脚约束和 TD 工程 | rtl/hx1p35_lpr_top.v、constraints/、td_project/ | 导入平台后由 tools/prepare_project.py 生成 |
| 示例照片、测试卡及原始素材 | assets/、大型仿真mem文件 | 未放入公开仓库 |

已有 v24 完整工程的用户可使用 `tools/import_dependencies.py` 在本机导入依赖。导入不代表获得新的授权，忽略列表也不代表允许公开上传这些内容。若后续获得明确再分发许可，再按文件补充来源、许可和适用范围。

`rtl/` 中公开的是新增算法/控制逻辑；`tools/prepare_project.py` 为项目集成生成器，生成结果引用外部平台。安路品牌与 Logo 不因本项目开源而获得额外商标授权。
