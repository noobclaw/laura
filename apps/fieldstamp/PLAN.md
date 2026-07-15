# FieldStamp — 产品规划 (v1)

## 一句话定位
给工程 / 勘测 / 保险 / 物业 / 执法现场人员的「拍一张就是一份可存档证据」的离线 GPS 取证相机——每张照片在拍摄瞬间把 GPS 坐标、海拔、方位角、时间戳、项目名烧进画面像素,全部本地归档,可导出 PDF 巡检报告 / CSV 台账,一次买断、零上传。

## 为什么是它(队列取项)
BACKLOG 排名 #3(指数 78),是 ⚪排队 中指数最高、且「落地无外部依赖阻塞」的未做项(#1 echo-jot 卡端侧 whisper 在做、#2 Remcard 已做)。信号:App Store 美区付费榜 GPS 取证相机簇(Solocator / MilGPS / Site Audit Pro)连续多日升温,付费面被反复实证;头部竞品 Solocator 转订阅遭差评、Site Audit Pro 重且贵——「干净买断 + 离线 + 不啰嗦」中间地带空着。纯本地传感器计算,天然零服务端。

## 功能清单(v1 只做核心)
- **取景 + 实时信息带**:全屏相机预览,底部实时叠一条信息带(GPS 经纬度 + 海拔 + 方位罗盘 + 时间 + 当前项目名);GPS 定位状态(已定位/搜星中 + 精度 ±米)可见。
- **烧水印拍摄**:按快门在拍摄瞬间把上述字段用 Canvas 合成进照片像素(非事后 P 图,取证可信),再本地落库为 JPEG。
- **本地归档**:按项目分组的照片网格墙;无 GPS 定位的照片有角标提示;点开看大图 + 全部元数据 + 加备注 + 删除 + 分享单张。
- **导出**:多选一批照片 →
  - **分享原图**(免费,水印已烧入,直接可用)
  - **PDF 巡检报告**(Pro):每页一图 + 坐标/时间/方位/精度/备注表格
  - **CSV 台账**(Pro):文件名/项目/时间/经纬度/海拔/精度/方位/备注
- **项目 / 工单管理**:多项目切换(免费仅默认 1 个,Pro 解锁多项目)。
- **设置**:坐标格式(十进制;DMS 度分秒为 Pro)、海拔单位(米/英尺)、Pro 解锁、"烧水印原理" 说明、隐私声明。

## 页面结构
- **底部两 Tab**:相机 / 相册(壳 AppBar 提供标题 + 设置入口)。
- 相机屏:顶部项目条(点击切换/新建项目)→ 预览 + 底部实时信息带 → 大快门键。
- 相册屏:项目条 + 照片网格;多选模式顶栏(分享/PDF/CSV/删除)。
- 照片详情:独立页,大图 + 元数据列表 + 备注编辑 + 分享/删除。
- 设置内子页:项目管理页、烧水印原理页。

## 技术要点
- Flutter 3.44;`camera`(预览+拍照)、`geolocator`(GPS/海拔/精度)、`flutter_compass`(磁力计方位)。
- 水印**拍摄瞬间合成**:`dart:ui` Canvas 叠字 → `image` 包在后台 isolate(`compute`)重编码 JPEG,避免主线程卡顿。
- `pdf` 包本地生成巡检报告(图片下采样到 1200px 控体积)、CSV 手写拼装;`share_plus` 走系统分享面板导出(无 INTERNET)。
- 本地存储:元数据 JSON + 照片 JPEG 存 app 沙盒 `getApplicationDocumentsDirectory()`。
- **零上传硬保证**:AndroidManifest 只声明 CAMERA + 定位权限,并用 `tools:node="remove"` 剥离任何三方库可能注入的 INTERNET → 商店「无网络访问」卖点可验证。
- iOS Info.plist 已加 NSCameraUsageDescription / NSLocationWhenInUseUsageDescription(为后续 App Store 构建备好)。

## 定价
- **免费**:可拍、全水印(带小 "FieldStamp" 角标)、单默认项目、看相册、分享原图。
- **一次性买断 Pro $6.99**(偏刚需定价,对标 Solocator 订阅疲劳):解锁多项目 / PDF 巡检报告 / CSV 台账 / DMS 坐标 / 去掉照片上的 FieldStamp 角标。
- (v1 内购为本地占位开关,正式版接入应用内购买。)

## 商店关键词
gps camera, geotag camera, field camera, timestamp camera, survey photo, geotag photo, gps photo stamp, 取证相机, 定位水印相机, 工地拍照, 巡检, 现场取证

## 已知取舍 / v2
- PDF 默认字体不含 CJK:项目名/备注若含中文,PDF 内可能显示空白(v2 内嵌中文字体)。CSV 与照片烧字用系统字体不受影响。
- EXIF GPS 写入(`native_exif`)留 v2;v1 以「烧入像素 + 元数据台账」作为取证记录。
- UTM 坐标、自定义水印字段勾选/logo 叠加留 v2。
- 未在真机验证(本机 8GB 不能出包);方位字段单位、camera/geolocator 权限弹窗需装机确认。
