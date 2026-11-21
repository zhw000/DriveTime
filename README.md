# DriveTime

DriveTime 是一款原�?iOS 驾车耗时与到达时间查询工具。它不做完整导航，只专注于回答一个问题：**从现在（或你计划的时间）出发，走真实道路路线，要多久才能到？**

- **原生 SwiftUI**，最�?iOS 17，无 WebView、无 Flutter/React Native、无网页套壳�?- 路线、距离、预计耗时、过路费和路况都来自真实地图服务�?*Apple MapKit** �?**高德地图 Web 服务（经 Cloudflare Worker 代理�?*�?- 不使用直线距�?÷ 固定速度伪�?ETA�?- 可以通过 GitHub Actions 在云端编译出真正面向 **iPhoneOS** �?`.app`，并打包�?**未签�?IPA**�?- 默认 Bundle ID �?`com.example.drivetime`，便于自行签名时替换�?
> **构建状态说�?*：仓库的 `iOS Device Build` 工作流已经成功完成过无签�?iPhoneOS 构建并生成通过结构校验�?IPA。最终一次提交的构建、单元测试和 UI 测试结果�?GitHub Actions 页面为准；本项目没有在真�?iPhone 上用你的证书安装验证过。详见“验证状态”一节�?
---

## 目录

1. [功能](#功能)
2. [真实数据原则与限制](#真实数据原则与限�?
3. [截图与界面](#截图与界�?
4. [工程结构](#工程结构)
5. [本地环境要求](#本地环境要求)
6. [生成 Xcode 工程](#生成-xcode-工程)
7. [GitHub Actions 构建](#github-actions-构建)
8. [下载未签�?IPA 并自行签名](#下载未签�?ipa-并自行签�?
9. [Bundle ID 与重签名](#bundle-id-与重签名)
10. [高德地图配置](#高德地图配置)
11. [坐标系](#坐标�?
12. [测试](#测试)
13. [验证状态与已知限制](#验证状态与已知限制)
14. [常见构建问题](#常见构建问题)
15. [真机验收清单](#真机验收清单)
16. [数据来源与隐私](#数据来源与隐�?

---

## 功能

### 已实�?
- **Apple MapKit 路线**
  - `MKLocalSearch` 地点搜索、`MKLocalSearchCompleter` 自动补全、`MKDirections` 驾车路线�?  - 请求明确设置 `.automobile`，不会把步行/公交路线当成驾车路线�?  - 多路线选择（当 MapKit 返回多条时）�?  - 真实折线几何，不使用直线代替�?  - �?ETA 查询接口（`calculateETA`）已�?provider 中独立实现，内部模型显式区分“有轨迹的路线”和“无轨迹�?ETA 查询”�?- **高德地图**
  - 按照高德 **Web 服务路径规划 2.0**（`/v5/direction/driving`）实现，不混�?v3 参数�?  - 使用 `strategy`�?2/33/34/35/36/38 等）驱动偏好�?  - 固定请求 `show_fields=cost,tmcs,polyline,navi,cities`�?  - 解析字符串形式的距离/耗时、过路费、收费里程、收费道路、红绿灯数量、分�?TMC 路况和折线�?  - 只展示服务实际返回的路线数量；不会把同一�?strategy 的一条路线伪装成多条�?  - 缺少费用、路况或轨迹时显示“暂无数据”或说明，不填假数字�?- **地点输入**
  - 起点/终点搜索、自动补全、交换起终点、当前位置、地图选点、最近地点、收藏地点�?  - 搜索防抖；过期请求不会覆盖最新结果；搜索任务可取消�?- **行程结果**
  - 大号预计车程、路线距离、预计到达时刻、出发时刻、路线偏好、数据来源、查询时间�?  - 预计到达 = **请求快照对应的出发时�?+ 地图服务返回的预计耗时**，不受渲�?网络延迟影响�?  - 路线备选比较（时间差、距离差均来自真实返回数据）�?  - 刷新路况，带客户端冷却、API 侧限频和服务�?Worker 限流�?  - SwiftData 历史记录、收藏路线、历史数据标记与重新查询�?- **计划出发时间**
  - 现在出发、稍后一小时、明天早上、自定义日期时间�?  - 当前 Apple/高德接入的驾车接口不提供可信的未来时刻交通预测时，界面会明确提示这是按当前路况的推算，不冒充预测�?- **UI**
  - SwiftUI 原生 Map、原�?Sheet detents、Dynamic Type、深色模式、Reduce Motion 处理、VoiceOver 标签、安全区与横屏布局�?  - 浅色为默认，自动适配深色�?  - 无账号、无广告、无分析 SDK、无无意义底�?Tab�?- **隐私与安�?*
  - 高德 Web Service Key 只存�?Cloudflare Worker Secret 中，不进�?App、UserDefaults、源码或 CI�?  - 可选代理访问令牌只保存�?iOS Keychain�?  - Worker 限制请求参数、字段、响应大小、方法、频率，并可要求 Bearer Token�?
### 不在本版本范�?
- 逐向语音导航、实时转向指令跟随、后台持续定位�?- 高德 iOS SDK 的离线地图或导航能力（本项目使用 Web 服务 + MapKit 渲染）�?- 账号同步、社交、广告、订阅�?- 真实未来时刻交通预测（当前接入的服务接口不提供）�?
---

## 真实数据原则与限�?
这些规则写进了实现和测试�?
1. **ETA 来自地图服务**。没有固定车速、经纬度直线距离或虚构系数修正�?2. **路线折线必须来自服务**。若高德没有返回完整 step/path 折线，会显示“未返回完整路线轨迹”，地图只画起终点，绝不把起终点连直线冒充路线�?3. **只有返回多条才展示多�?*。高�?v5 Driving 默认一�?strategy 返回一条方案；DriveTime 不会为凑“备选路线”重复请求或改写标题�?4. **缺失字段不补�?*。过路费、路况、收费里程等字段缺失时展示“暂无数据”，不显�?`¥0` 或虚假的“畅通”�?5. **未来出发不冒充预�?*。当前接口没有出发时刻预测参数；选择未来时间时，结果会标记为“未来时刻推算”，并提示按当前路况估算。ETA 公式仍使用已规划出发时刻，但数据基础是当前路况�?6. **服务错误不静默回退成模拟数�?*。自动模式从高德回退�?Apple 时，会在结果中显式写明“已改用 Apple 地图”�?7. **演示数据只在 DEBUG**。UI 自动化测试使用明确标注“演示数据”的 `-DriveTimeDemo` 启动参数；该代码�?Release 中编译剔除，正常启动不会触发�?
### 关于高德接口

使用到的高德官方文档�?
- 路线规划 2.0�?https://lbs.amap.com/api/webservice/guide/api/newroute>
- 驾车接口：`https://restapi.amap.com/v5/direction/driving`
- 搜索 POI 2.0�?https://lbs.amap.com/api/webservice/guide/api-advanced/newpoisearch>

注意：路线规�?2.0 �?v3 的字段、`strategy` 含义不同，不应混用。AMap 的距离、耗时等字段经常以字符串返回，DriveTime 有容错解码器�?
### 高德是否经过真实联调

- Worker 代理、请求构造、AMap 响应解析、错误码映射和字段缺失处理都有自动化测试�?- **仓库中没有高�?API Key，因此没有使用真实高德账号完成端到端路线查询�?* 配置有效 Key 后的真机结果需要你�?README 完成验证�?- Apple MapKit 路径不依赖仓库中的密钥，可在真机网络可用时直接使用�?
---

## 截图与界�?
UI 测试会在 iOS Simulator 中截取浅色首页、地点搜索、演示路线紧�?展开、设置、深色首页，并作�?GitHub Actions Artifact 上传�?
> 截图来自自动�?UI 测试。路线结果页使用明确标记�?DEBUG 演示数据；它只用于验证布局和交互，不代表真实路线�?
设计语言�?
- 米白/深墨色底、朱砂色主色，避免蓝紫渐变�?- 地图为主视图，搜索卡浮于其上，结果面板使用原�?`presentationDetents`�?- 细发丝分割线、克制的阴影�?Material，不使用大面积玻璃拟态�?- SF Symbols、系统字体、语义化 Dynamic Type，无第三方字体依赖�?- 尊重 Reduce Motion：地图视野、数字更新和面板展开使用系统动画或直接切换�?
---

## 工程结构

```
DriveTime/
  App/                     # App 入口、AppModel、AppSettings
  Models/                  # 地点、路线、ETA、交通、错误、Provider 能力
  Views/
    Home/                  # 首页搜索卡、地图、结�?Sheet、出发时�?    Search/                # 地点搜索、地图选点
    Settings/              # 设置
    History/               # 历史与收�?    Components/            # 通用原生组件
    Theme/                 # 颜色与排版令�?    RootView.swift
  ViewModels/              # RoutePlannerViewModel、PlaceSearchViewModel
  Routing/                 # RoutingProvider、AppleMap、AMap、解析器、Resolver
  Services/                # HTTP、定位、限�?  Persistence/             # SwiftData 模型、HistoryStore、Keychain
  Location/                # WGS-84 �?GCJ-02
  Utilities/               # 格式化、ETA、日志、App 信息
  Resources/               # Info.plist、Assets、AppIcon
DriveTimeTests/            # XCTest 单元测试
DriveTimeUITests/          # XCTest UI 冒烟与截图测�?backend/cloudflare-worker/ # 高德 Key 代理（Cloudflare Worker�?.github/workflows/         # iOS Device Build / iOS Simulator Tests / Release
scripts/                   # XcodeGen、未签名 IPA 打包与验�?project.yml                # Xcode 工程唯一事实来源
README.md
```

架构�?
- MVVM + Provider / Service / Repository�?- `RoutingProvider` 协议统一 Apple MapKit 与高德�?- `RoutePlannerViewModel` 协调地点、偏好、出发时间、取消、回退、历史、刷新冷却�?- `HistoryStore` 使用 SwiftData，所有持久化在主线程上下文中操作�?- 网络使用 async/await、URLSession、取消、超时和有限重试；无同步网络调用�?- UI 不直接解析服�?JSON，所有外部响应在 Routing 层转换为内部单位�?*距离米、耗时秒、日�?`Date`**�?
---

## 本地环境要求

- iOS 17.0+ 真机（签名后安装）�?- 若在 Mac 上构建：macOS 26 + Xcode 26.x。CI 固定使用 Xcode 26.6�?- XcodeGen **2.48.0**（`project.yml` 为唯一事实来源）�?- �?CocoaPods / SPM / 第三�?App 依赖�?
无需 Mac 的开发方式：�?Windows/Linux 修改代码，推送到 GitHub，用 Actions �?macOS Runner 构建�?
---

## 生成 Xcode 工程

仓库同时维护 `project.yml` �?CI 生成的项目。推荐的工程打开方式�?
```bash
# macOS
./scripts/generate-project.sh
open DriveTime.xcodeproj
```

`DriveTime.xcodeproj` �?XcodeGen 根据 `project.yml` 生成；不要手工在 Xcode 里添加源文件后忘记同步，否则 CI 重新生成时会丢失。新增文件放�?`DriveTime/` 下即可被自动包含（`Resources/Info.plist` 除外，它�?build setting 引用）�?
Bundle ID 只在 `project.yml` �?`PRODUCT_BUNDLE_IDENTIFIER`（以及测�?target）集中维护，不要把固�?Bundle ID 硬编码进业务源码�?
---

## GitHub Actions 构建

工作流：

| 文件 | 触发 | 作用 |
|---|---|---|
| `.github/workflows/ios-build.yml` | push main、PR、手�?| Release iPhoneOS 无签名设备构�?+ 未签�?IPA + checksums |
| `.github/workflows/ios-test.yml` | push main、PR、手�?| 模拟器构�?+ 单元测试 + UI 测试 + 截图 |
| `.github/workflows/release.yml` | `v*.*.*` tag、手�?| 构建、验证、上传未签名 IPA �?GitHub Release |

手动触发�?
```bash
gh workflow run ios-build.yml --repo <owner>/DriveTime
gh workflow run ios-test.yml --repo <owner>/DriveTime
```

下载 Artifact（需要已登录 GitHub CLI）：

```bash
gh run list --repo <owner>/DriveTime
gh run download <RUN_ID> --repo <owner>/DriveTime -n DriveTime-device-<RUN_NUMBER> -D ./download
```

如果使用网页：Actions �?选择运行 �?页面底部 Artifacts �?下载 ZIP �?解压得到 `DriveTime-unsigned.ipa`�?
### CI 构建参数

设备构建�?
```bash
xcodebuild \
  -project DriveTime.xcodeproj \
  -scheme DriveTime \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  build
```

这产出的是真正的 `Release-iphoneos/DriveTime.app`，不�?Simulator 产物�?
### 未签�?IPA 打包

```bash
scripts/package-unsigned-ipa.sh \
  build/Build/Products/Release-iphoneos/DriveTime.app \
  artifacts
```

脚本会：

1. 检�?`.app`、`Info.plist` 和可执行文件�?2. 检�?`CFBundleSupportedPlatforms.0 == iPhoneOS`、`DTPlatformName == iphoneos`�?3. 检查可执行文件包含 arm64，且 `vtool -show-build` 报告 `platform IOS`�?4. 生成规范�?`Payload/DriveTime.app`�?5. 移除可能残留�?`_CodeSignature` / `embedded.mobileprovision`（并明确报告）；
6. 使用 `ditto` 打包�?`DriveTime-unsigned.ipa`�?7. 调用 `scripts/verify-ipa.sh` 验证 ZIP 结构、平台、最低系统版本、arm64�?8. 输出大小�?SHA-256 �?`artifacts/checksums.txt`�?
本项目没�?App Extension、Watch App 或嵌入式 Framework，因�?IPA 结构较简单。以后若加入扩展/框架，必须逐个签名并匹�?entitlements�?
### Artifacts 内容

- `DriveTime-unsigned.ipa`
- `checksums.txt`
- `build.log`
- `DriveTime.xcodeproj`（CI 生成的可打开工程�?- `Release-iphoneos/DriveTime.app`
- 测试工作流另�?`TestResults.xcresult`、`test.log`、`test-summary.json`、UI 截图�?
### CI 安全

- 工作流默�?`permissions: contents: read`；只�?Release 工作流有 `contents: write`�?- 第三�?Action 固定�?commit SHA（见 `.github/workflows/`）�?- 不保存高�?Key 或其�?Secret 到仓库�?- PR 构建不需要任�?Secret；即使有，也不会�?fork PR 暴露�?- 不执行不可信 PR 中动态生成的高权限脚本；构建由受控的 `project.yml` + 本仓库脚本完成�?
### 发布未签�?IPA

```bash
git tag v0.1.0
git push origin v0.1.0
```

`release.yml` 会创建一�?prerelease，标�?`DriveTime v0.1.0`，正文明确写�?**Unsigned IPA �?Requires User Signing**。这不是可直接点击安装的正式发行版�?
---

## 下载未签�?IPA 并自行签�?
> 未签�?IPA 不能直接安装。你需�?Apple 开发证书、匹配的 Provisioning Profile 和设备授权�?
典型流程（使用自己的签名工具�?macOS）：

1. �?Actions Artifact �?Release 下载 `DriveTime-unsigned.ipa`�?2. 校验 SHA-256：`shasum -a 256 DriveTime-unsigned.ipa`，与 `checksums.txt` 对照�?3. �?Sideloadly、AltStore、ESign、TrollStore 或你自己�?`codesign` 流程签名�?4. 将签名后�?IPA 安装到设备�?
命令行示例（macOS，需自行替换证书、profile �?Bundle ID）：

```bash
unzip DriveTime-unsigned.ipa -d decoded
APP="decoded/Payload/DriveTime.app"

# 如需�?Bundle ID（同时要�?Provisioning Profile 覆盖这个 ID）：
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.yourname.drivetime" "$APP/Info.plist"

# entitlements 默认可为空；如果你需要额外能力，按你�?profile 配置
cat > /tmp/drivetime.entitlements <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST

codesign --force --sign "Apple Development: Your Name (TEAMID)" \
  --entitlements /tmp/drivetime.entitlements \
  --timestamp=none "$APP"

# 如以后加�?Frameworks/Extensions，先签名这些嵌套项，再签 App�?rm -rf signed && mkdir -p signed/Payload
cp -R "$APP" signed/Payload/
(cd signed && zip -qry ../DriveTime-signed.ipa Payload)
```

注意�?
- **Bundle ID 必须�?Provisioning Profile 匹配**；否则安装会报签�?描述文件错误�?- 免费 Apple ID 的签名通常 7 天过期，需重签�?- 重签名工具可能改�?Info.plist、注入库或修�?entitlements。DriveTime 不使用私�?API、不需要越狱、不包含特殊 entitlements�?- �?IPA 使用默认 Bundle ID `com.example.drivetime`；若你的证书不能使用它，请修改后重签。修�?`project.yml` 中的 Bundle ID 后重新由 CI 构建是最干净的方式�?- AMap Key 不在 IPA 中；重签名不会影响高�?Web API 代理�?*本工程没有链接高�?iOS SDK，因此不存在 AMap SDK �?Bundle ID 授权绑定问题�?*
- Apple MapKit 无需 API Key；但 Apple 地图/定位服务在中国大陆可用性受设备区域和系统服务影响�?
更多签名排错见“常见构建问题”�?
---

## Bundle ID 与重签名

默认�?
```
com.example.drivetime
Tests: com.example.drivetime.tests
UI Tests: com.example.drivetime.uitests`n```

如需长期使用自己�?Bundle ID�?
1. 编辑 `project.yml` �?`DriveTime` target �?`PRODUCT_BUNDLE_IDENTIFIER`（测�?target 可选同步）�?2. �?Apple Developer 后台注册 App ID，创建对�?Provisioning Profile�?3. 推送代码，�?CI 重新构建�?4. 签名时确�?profile 中的 Bundle ID 完全一致�?
不要在多�?Swift 源文件里写死 Bundle ID。App 的版本信息通过 `Info.plist` �?`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` 注入�?
工程使用 placeholder Team（空），不依赖任何固定开发者账号。CI 的无签名构建不要求证书�?
---

## 高德地图配置

高德地图在本项目�?*不是 SDK 集成，而是 Web Service 集成**�?
```
iOS App  �? Cloudflare Worker  �? restapi.amap.com
            (AMAP_KEY secret)
```

### 1. 获取高德 Key

1. 注册/登录 [高德开放平台](https://lbs.amap.com/)�?2. 控制台创建应用�?3. 添加 **Web 服务** 类型�?Key（不�?Android/iOS SDK Key）�?4. 视高德账号状态，可能需要实名或企业认证才能获得配额�?
### 2. 部署 Worker

```bash
cd backend/cloudflare-worker
npm install
npx wrangler login
npx wrangler secret put AMAP_KEY
npx wrangler secret put PROXY_ACCESS_TOKEN   # 推荐
npx wrangler deploy
```

详情�?[`backend/cloudflare-worker/README.md`](backend/cloudflare-worker/README.md)�?
### 3. �?App 中配�?
打开 DriveTime �?设置 �?高德路线代理�?
- 填入 Worker URL（必须为 `https://…`；本地开发允�?`http://127.0.0.1`）�?- 如果设置�?`PROXY_ACCESS_TOKEN`，将同一�?token 填入访问令牌。它保存�?iOS Keychain�?- 点“保存并测试连接”。Worker 已配�?Key 时会显示“AMap Key 已配置”。健康检查不消耗真实路线配额�?
也可以编译期注入默认 Worker URL�?
```bash
# 修改 project.yml �?DRIVETIME_PROXY_BASE_URL，或�?xcodebuild 参数中覆�?DRIVETIME_PROXY_BASE_URL="https://your-worker.workers.dev"
```

�?URL 不是秘密�?*不要�?AMAP_KEY �?PROXY_ACCESS_TOKEN 写进 project.yml/CI**。访问令牌建议只通过 App 设置写入 Keychain�?
### 4. 服务选择

- 设置 �?地图服务：自�?/ Apple 地图 / 高德地图�?- 自动：已配置代理且起终点都在中国大陆时优先高德；否则 Apple�?- 高德失败时，自动模式会回退 Apple，并在结�?`路线说明` 中明确写出；显式选择高德时直接显示错误，不会静默换服务�?- 设置页只展示当前服务实际支持的路线偏好（Apple 仅智能推荐）�?
### 5. 未配�?Key �?
- Apple MapKit 功能可用�?- 高德相关设置可保�?URL，但路线请求会返回清晰的“代理未配置/鉴权失败”错误；不会生成假路线�?- 参�?`PROXY_NOT_CONFIGURED` / `UNAUTHORIZED` / `AMAP_*` 错误码�?
### 高德 SDK vs Web Service

如果你以后改成高�?**iOS SDK**�?
- 需要高�?iOS Key + Bundle ID 绑定/安全码配置�?- 重签名改�?Bundle ID 后很可能需要重新申�?调整 Key�?- 那时不能继续�?Web Service �?Key 塞进客户端；两种认证体系不同�?
当前代码仅使�?Web Service 代理，不受上�?SDK Bundle ID 绑定影响�?
---

## 坐标�?
DriveTime 明确区分�?
- **WGS-84**：CoreLocation 原始 GPS 坐标（`CLLocation`）�?- **GCJ-02**：中国大陆法定地图坐标，Apple MapKit 中国底图 / `MKLocalSearch` / 高德 Web 服务使用�?- `CLLocationCoordinate2D` 本身不携带坐标系信息，因此内�?`GeoCoordinate` 显式保存 datum�?
处理策略�?
- 地点结果保留其来�?datum：Apple 地点�?AMap 地点标为 GCJ-02；当前位置标�?WGS-84；地图选点按是否在中国标为 GCJ-02/WGS-84�?- 显示�?Apple Map 前调�?`appleMapCoordinate`：WGS-84 + 中国大陆 �?GCJ-02；GCJ-02 保持；中国大陆之外保�?WGS-84�?- 发送给 AMap 前调�?`amapCoordinate`：转�?GCJ-02�?- 距离/同地点判断用 `groundDistance`，先把双方转�?WGS-84，避免混 datum 误差�?- 高德返回的折线直接标�?GCJ-02，并在中�?Apple 底图上直接绘制；不会二次偏移�?- 香港/澳门/台湾被排除在“自动使用高德中国大陆路线”的判定之外（保守矩�?+ 排除区）�?
这些逻辑有单元测试；但不排除 Apple 或高德未来调整坐标行为。若发现整体偏移，请优先核对 datum 而不是给路线加固定偏移量�?
---

## 测试

### 单元测试覆盖

`DriveTimeTests/` 包含�?
- 距离格式化（公制/英制�?- 秒数 �?小时/分钟/时钟文本
- ETA 加法、跨日到�?- 独立时区、夏令时跨段
- 24h/12h 时间格式
- 起终点交�?- 相同地点判断
- 无路线状�?- AMap 成功/错误响应 JSON、字符串数字、费用、收费道路、限行说�?- AMap 分段路况、路况级别、折线校验（坏点拒绝、不画直线）
- AMap POI 解析、空结果、无�?POI 跳过
- 高德 strategy 映射（v5 码）
- 多路线解�?- 请求取消（provider 收到取消�?- 刷新冷却
- 自动回退�?Apple 且显式提�?- 未来出发的“推算”标记与 ETA 时间快照
- SwiftData 历史记录写入/读取/收藏/删除/清空保留收藏
- 收藏地点坐标近似匹配
- Keychain 样式测试（使用内�?mock�?- WGS-84 �?GCJ-02 往返与香港/海外不偏�?
### UI 测试

`DriveTimeUITests/`�?
- 首页渲染、地点搜索入�?- 演示路线结果、明确“演示数据”标�?- 结果 Sheet 展开、路线备选、刷新按�?- 设置页与代理字段
- 深色模式首页
- 截图附件自动上传�?Actions Artifact

UI 测试使用 DEBUG-only `-DriveTimeDemo` 数据，正�?App 启动永不使用�?
### 如何本地运行测试

需�?macOS + Xcode�?
```bash
./scripts/generate-project.sh
xcodebuild test \
  -project DriveTime.xcodeproj \
  -scheme DriveTime \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

CI 会自动选择一个实际已安装�?iPhone Simulator，而不是硬编码不存在的设备�?
### 当前测试限制

- UI 测试只覆盖模拟器中的冒烟路径；没有对你的真机屏幕尺寸、Dynamic Island 机型、通知/设置系统弹窗做逐项人工验收�?- 没有使用真实高德 Key 做在线集成测试�?- 没有在真实设备上验证 Apple 地图定位权限弹窗、运营商网络和真实交通数据�?- 没有进行完整�?VoiceOver 手动走查、超大字号布局矩阵或所有横屏尺寸验证�?- 没有进行长时间稳定�?内存压力测试�?
---

## 验证状态与已知限制

### 已完成并可验�?
- 真实 Xcode 工程�?`project.yml` 生成�?- GitHub Actions �?`macos-26` + Xcode 26.6 上完成过一�?**Release iPhoneOS** 无签名构建�?- `scripts/package-unsigned-ipa.sh` �?`scripts/verify-ipa.sh` �?CI 上实际运行并通过，确�?IPA 内是 `iPhoneOS`、arm64、非 Simulator 产物�?- Apple MapKit 与高�?Provider 的真实网络实现存在；Apple 路径不依�?Key；高德路径依赖你�?Worker 部署�?- 单元测试�?UI 测试已写入并接入 CI；最终通过情况请查�?Actions 的最新运行结果�?- 本地代码无法�?Windows 上编�?iOS；所有编译结论来�?GitHub Actions�?
### 尚未验证 / 已知限制

- **未用你的开发者证书在真实 iPhone 上安装验证�?* 签名后的安装受证书、Profile、设备、Bundle ID、Entitlements 影响�?- **未使用真实高�?Key 进行在线路线查询�?* 高德端到端需按本文配�?Worker 后验证�?- Apple MapKit 不返回逐路段交通状态，因此 Apple 路线的“路况”区域显示暂无逐段数据；可以开�?Apple 地图路况图层，但那是底图图层，不等于路线 TMC�?- AMap 驾车 v5 无未来交通预测参数；未来出发的结果是“当前路况推算”，不是预测�?- AMap 驾车接口可能只返回一条路线；不会伪造多方案�?- 过路费、收费道路仅在高德返回时展示；Apple 只提供是否收费（无金额）�?- 未集成高�?iOS SDK，因此没�?AMap 底图�?SDK 导航能力�?- 未做完整�?iPad 专门布局（目标设备族�?iPhone），横屏 layout 已做基础适配�?- Demo 数据只用�?DEBUG UI 测试，不属于产品功能�?- Git 仓库�?Xcode 工程�?XcodeGen 生成；最终工程以 CI Artifact 或本地重新生成结果为准�?
---

## 常见构建问题

### `xcodegen: command not found`

CI 会自动下载固定版�?2.48.0；本地执行：

```bash
./scripts/generate-project.sh
```

不要�?Windows 上运�?XcodeGen；它只提�?macOS 二进制�?
### `Signing for "DriveTime" requires a development team`

CI 使用无签名设备构建，不应该出现。如果你�?Xcode 本地构建真机�?
- �?Xcode Signing & Capabilities 选择你的 Team �?Bundle ID；或
- 只用 CI 构建未签�?IPA 后自行签名�?
### `No such module 'XCTest'`

通常是测�?target 缺少 test host 或使用了错误 SDK。先�?CI �?`xcodebuild test` 配置；不要用 `iphoneos` 直接�?XCTest�?
### Simulator 设备不存�?
CI 会通过 `scripts/pick-simulator.py` 动态选择已安�?iPhone 模拟器。本地不要硬编码 `iPhone 15` 等旧名称，使�?`xcrun simctl list devices available` 查看�?
### 未签�?IPA 安装失败

- 必须先签名，不能双击 IPA 直接安装�?- Bundle ID �?profile 不匹配、设备未加入 profile、证书过期、entitlements 不匹配都会失败�?- 删除�?App/描述文件后重试；免费证书�?7 天需重签�?- 如果签名工具修改�?Info.plist 后安装失败，检查版本号、Bundle ID 和最�?iOS 版本�?
### `Device is not supported` / arm64 错误

确认使用的是 `Payload/DriveTime.app`，不是模拟器 `.app`。运行：

```bash
file Payload/DriveTime.app/DriveTime
vtool -show-build Payload/DriveTime.app/DriveTime
```

应看�?arm64 �?`platform IOS`。CI �?`verify-ipa.sh` 会做同样检查�?
### AMap �?`UNAUTHORIZED` / `10001`

- 确认 Worker secret 里是 **Web 服务** Key，不�?iOS SDK Key�?- 如果设置�?`PROXY_ACCESS_TOKEN`，App 设置里的 token 必须完全一致�?- �?`curl` 测试 `/v1/health`；配置了 Key �?`configured=true`�?- Worker 日志中不要打�?Key；如果自行修�?Worker，务必避免日志泄露�?
### AMap �?`AMAP_10003` / 配额不足

高德账号每日配额�?QPS 限制。等待恢复、升级配额，或切�?Apple 地图�?
### 地图空白/路线不显�?
- 模拟�?真机需要网络才能下载底图；路线 JSON 和底图是两回事�?- 检查是否返回了 `polyline`；高德缺少轨迹时 UI 会明确提示，不会画直线�?- Apple 地图在中国大陆的可用性受系统地区设置影响�?
### 未来出发结果为何提示“推算�?
这是有意设计。当前接口没有经过验证的未来交通预测参数；提示避免把当前拥堵当作明天早高峰事实�?
---

## 真机验收清单

下载并签名安装后，建议按顺序验证�?
1. **冷启�?*：App 打开不崩溃，首页显示地图、DriveTime 标题、起终点输入�?2. **搜索地点**：起点输入“台州市路桥区”或任意地址，能看到自动补全/搜索结果；选择后起点显示正确�?3. **终点搜索**：搜索“杭州市西湖区”等；选择终点�?4. **计算**：点击“计算车程”，显示真实来源的预计车程、距离、抵达时间；地图绘制道路折线，不是直线�?5. **服务来源**：结果面板显示“Apple 地图”（或“高德地图”）；查询时间合理�?6. **备选路�?*：如果服务返回多条，能看到并切换；时�?距离差来自真实数据。Apple 在多数路线会返回备选�?7. **刷新**：等待冷却结束后刷新，ETA/到达时刻更新；连续点击有冷却提示，不会狂发请求�?8. **交换**：交换起终点并再次查询，路线方向正确�?9. **相同地点**：起点终点相�?极近时显示明确提示，不请求�?10. **当前位置**：允许定位后使用当前位置；如果拒绝权限，有设置引导�?11. **地图选点**：拖动地图选点，名�?坐标正确；在中国大陆路线不出现整体偏移�?12. **计划出发**：选择未来时间，界面明确显示“未来时刻推�?仅供参考”，不是伪造的预测�?13. **历史记录**：查询成功后进入历史，能看到标记为历史的摘要；点按重新查询获取实时数据；删除/清空可用�?14. **收藏**：收藏路线和地点，重新打开 App 后仍存在�?15. **设置**：切换地图服务、距离单位、时间格式、深色模�?系统深色；清空历史�?16. **高德**：配�?Worker + Key + token 后，切换高德并查询中国大陆路线；确认来源为高德、费�?路况缺失时显示“暂无数据”；断开 Worker 看错误或自动回退提示�?17. **布局**：Dynamic Island 机型、横屏、键盘弹出、大字号下无遮挡/无不可点击内容�?18. **离线**：断网查询显示友好网络错误；恢复网络后可重试�?19. **VoiceOver**：关键按钮有标签；地图与结果面板可导航�?20. **隐私**：App 不要求登录；设置中隐私说明与实际行为一致�?
未进行上述真机测试之前，不应把“CI 编译通过”等同于“真机所有功能验证通过”�?
---

## 数据来源与隐�?
- **Apple 地图**：地点搜索、路线规划、ETA、地图底图。使用时�?Apple �?MapKit 条款约束。地图上�?Apple logo/法律链接由系统地图组件提供；结果页另附来源说明�?- **高德地图**：仅在用户配�?Worker 代理后用于路�?地点查询，并受高德开放平台条款约束�?- **DriveTime**�?  - 无账号、无广告、无分析 SDK�?  - 位置仅用于把当前位置设为起点，不保存轨迹，不做后台定位�?  - 路线查询会发往你所选的地图服务（Apple 直接；高德经你配置的 Worker）�?  - 历史记录、收藏保存在设备本地 SwiftData；卸�?App 会移除（Keychain 中可选的代理 token 可能由系统保留，取决�?iOS 行为）�?  - 代理 URL 与访问令牌可随时在设置中清除；AMap Key 永远不会下发到设备�?
---

## 开发路线（后续可扩展）

- 真实未来出发交通预测（需要支持出发时刻的服务�?Apple 明确可用的预测接口）�?- 更多 AMap 路线策略的参数级 UI（如多策略组合）以及服务实际支持时的多方案对比�?- 路线导航转向列表、分步预览、路况动态刷新�?- 国际化、iPad 多栏布局、无障碍大字号布局回归�?- 真实高德 Key 的端到端集成测试（使用测试账号，不进入客户端）�?- 可�?App Intents / 小组件显示常用路�?ETA�?
---

## 许可与免责声�?
本项目为个人开发交付，不附带任何地图服务密钥。使�?Apple MapKit 与高德服务须遵守各自条款。未签名 IPA 不是可安装的正式发行版；签名、安装与设备授权由使用者自行完成。地图数据、ETA、路况和费用受服务商实时状态影响，不构成出行安全保证�?
