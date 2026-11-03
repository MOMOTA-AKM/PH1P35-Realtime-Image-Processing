# 主要模块

| 模块 | 功能 |
|---|---|
| lpr_cn_video | 视频坐标、模式切换、任务协同、OSD及OCR耗时 |
| lpr_sobel_support | 流式3×3 Sobel及候选结构支持 |
| lpr_cn_detector | 蓝绿颜色候选定位与几何筛选 |
| lpr_cn_tracker | 目标关联、平滑框、漏检保持和身份版本 |
| lpr_cn_sampler | 稳定性、间隔与忙闲采样准入 |
| lpr_cn_segment | 前景提取、字符投影、裁剪及归一化 |
| lpr_cn_bitmap | 二值ROI同步存储及启动自检 |
| lpr_divider | 串行归一化除法 |
| lpr_green_gray_roi | 绿牌局部灰度阈值 |
| lpr_green_components | 有界连通域清理 |
| lpr_cn_ocr | 模板读取、多特征评分和整牌编码 |
| lpr_cn_vote | 滑动窗口投票确认 |
| lpr_mode_seg | 模式数码管扫描显示 |
| sc520_exposure_refresh | 固定曝光/增益参数刷新，不是闭环自动曝光 |

工程综合入口 hx1p35_lpr_top 需要从外部平台生成。原厂ISP内的自动白平衡属于平台集成功能。
