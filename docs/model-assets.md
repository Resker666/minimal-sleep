# 本地声音模型来源与限制

## 内置模型

- 来源：[Google YAMNet classification TFLite v1](https://www.kaggle.com/models/google/yamnet/tfLite/classification-tflite/1)，下载接口为 `https://www.kaggle.com/api/v1/models/google/yamnet/tfLite/classification-tflite/1/download`。官方模型页标明 Apache-2.0。未使用第三方录音训练或微调。
- 原始下载归档 `yamnet-google-classification-tflite-v1.tar.gz`：3,240,957 字节，SHA-256 `1B971B2132760273A5FB8F5DC504E86783B27853BB3135D555AE06F1E1E365F3`。归档内的 `1.tflite` 复制为 `app/src/main/assets/yamnet-v1.tflite`：4,126,810 字节，SHA-256 `10C95EA3EB9A7BB4CB8BDDF6FEB023250381008177AC162CE169694D05C317DE`。
- 标签 `yamnet_label_list.txt` 从该 TFLite 文件自身附带的 ZIP 部分提取，复制为 `app/src/main/assets/yamnet-labels-v1.txt`：6,230 字节，SHA-256 `8E1267A120C1932B7273C0D0E0C5529EDBB9A35512B437B1C8982BAA59047051`。共 521 行；索引 0 `Speech`、38 `Snoring`、42 `Cough`、494 `Silence`。
- 运行时 `com.google.ai.edge.litert:litert:1.4.2` 及 `litert-api:1.4.2` 来自 [Google Maven](https://maven.google.com/web/index.html#com.google.ai.edge.litert:litert)，两者 POM 声明 Apache-2.0。仅作设备内推理；App 不请求网络权限。

## 输入与解释

采集使用现有的 16 kHz、单声道 PCM 16 位数据。事件保存后，同一段 PCM 被有界后台队列送入模型；每 15,600 个样本转换到约 [-1, 1] 浮点值并推理，末尾不足一窗以零补齐。不启动第二个麦克风。队列只允许一个运行、四个等待；拥塞时保留录音并标记分类跳过。

模型分数未经概率校准。当前阈值只是初始显示规则：人声与鼾声需相邻两个窗口达到阈值，咳嗽需一个较高窗口，其他环境声音需两个窗口支持；不够明确显示“未确定”。标签为“疑似”而非诊断。“人声/疑似梦话”并不能判定说话者是否睡着。播放声进入麦克风时保留原有播放区间与干扰标记；模型不会消除回声。真机已观察到合成海浪被误判为 `Speech 0.59`，因此受播放干扰的疑似人声、鼾声、咳嗽默认按“未确定（播放干扰）”显示和统计，原始模型候选仍可查看，用户可手动改标签。

目前缺少来源可核验且分开的鼾声、梦话、人声、咳嗽真机验收样本。阈值未经准确率调优，不能据此声称误报率、漏报率或临床性能。用户手动标签单独保存，原始模型标签、分数和版本仍可查看。
