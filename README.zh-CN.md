# WFC 中文简介

<!-- badges: start -->
[![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Lifecycle: stable](https://img.shields.io/badge/lifecycle-stable-brightgreen.svg)](https://lifecycle.r-lib.org/articles/stages.html#stable)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![R >= 3.6.0](https://img.shields.io/badge/R-%3E%3D%203.6.0-blue.svg)](https://cran.r-project.org/)
<!-- badges: end -->

[English](README.md) | **简体中文**

状态：活跃维护（Active）

负责团队：WeianData Engineering

`WFC` 是一个面向工作流的 R 包，用于调查数据的加权与迭代比例拟合（raking）。
它强调一条严谨的 **预检查 → 执行 → 诊断** 流水线，用于多来源调查校准；采用与数据结构
无关（schema-agnostic）的维度定义和规范化的目标对象，使 raking 与事后分层（post-stratification）
两个引擎共享一致的接口契约。

> 说明：本项目的代码、测试、英文文档与配置一律使用英文；本文件是仓库中唯一的中文说明文件。

## 为什么用 WFC

多数加权脚本会“悄无声息”地出错：某个类别在目标中缺失、某个单元格样本太少无法估计，
或修剪（trimming）后组内总量发生漂移。`WFC` 把这些失败模式变成一等公民、可复核的步骤。

- **先预检查，再校准。** `wf_precheck()` 在计算任何权重之前，比对样本与目标并报告不兼容之处。
- **一套目标契约，多种数据来源。** 可从外部总体数据、加权参考样本或手工边际表构建规范化的 `wf_target`。
- **可复核的类别合并。** 事先声明合并阶梯（collapse ladder），依据预检查结果得到建议的合并方案，
  并一致地应用到样本与目标上。
- **raking 与事后分层共用一个调度器。** 无论使用哪种方法，`wf_calibrate()` 都返回同样的 `wf_weights` 契约。
- **把诊断变成习惯。** `wf_diagnose()` 以权重与边际诊断为每条工作流收尾。

## 安装

从 GitHub 安装开发版：

```r
# install.packages("remotes")
remotes::install_github("weiandata/WFC")
```

或从源码压缩包安装：

```r
install.packages("WFC_1.0.0.tar.gz", repos = NULL, type = "source")
```

## 工作流概览

```text
声明维度 ──► 构建目标 ──► 预检查 ──► （合并类别）──► 校准 ──► 诊断
 wf_dims()   wf_target_*()  wf_precheck()  wf_suggest_    wf_rake() /   wf_diagnose()
                                           collapse()     wf_poststrat()
                                           wf_apply_      wf_calibrate()
                                           collapse()
```

## 快速上手

```r
library(WFC)

data(wfc_example)

dims <- wfc_example$dims
target <- wf_target_population(
  pop = wfc_example$population,
  key_map = c(gender = "gender", age = "age"),
  count = "count",
  dims = dims,
  by = "province"
)

precheck <- wf_precheck(wfc_example$sample, target, id = "id")
precheck

weights <- wf_rake(wfc_example$sample, target, id = "id")
wf_diagnose(weights, target = target)
```

## 引导式工作流与双语输出

WFC 在同一套目标构造器、预检查、校准引擎、诊断与报告之上，提供一次调用的
引导式入口。它不会绕过阻断性预检查：自动整改只能使用 `wf_dims()` 中事先声明的
类别合并映射，每项决定都会以稳定的机器可读键记入账本。

```r
guided <- wf_autoweigh(
  sample = wfc_example$sample,
  population = wfc_example$population,
  dims = dims,
  key_map = c(gender = "gender", age = "age"),
  count = "count",
  by = "province",
  id = "id",
  interactive = FALSE
)

guided$weights
guided$ledger[c("step", "action", "detail_key", "detail")]
```

`method = "auto"` 只有在同时提供已审核的 `ladder` 与 `min_cell` 时才选择事后分层；
否则选择 raking，且绝不会自动选择有界 logit 校准。设置 `interactive = TRUE` 可在
应用已声明合并和有限截尾建议之前要求确认。

面向人的报告、引导说明和图形标签支持英文与简体中文；对象字段、条件类、
账本动作键与 `detail_key` 始终保持英文，便于稳定的程序处理。

```r
wf_report(guided$weights, guided$target, lang = "zh_CN")
plot(guided$diagnostics, lang = "zh_CN")

options(wfc.lang = "zh_CN")
```

## 生态互操作

WFC 在严格、与行顺序无关的 ID 匹配后，将结果转换为 survey 包的标准设计对象。
所有生态包仍然只是建议依赖：不安装 survey、srvyr 或 generics 时，WFC 核心仍可正常安装与加载。

```r
analysis <- wfc_example$sample
analysis$outcome <- as.numeric(analysis$age == "young")

survey_design <- as_svydesign(
  guided$weights,
  analysis,
  id = "id"
)
survey::svymean(~outcome, survey_design)
```

`as_svrepdesign()` 可将 `wf_replicate_weights` 转换为标准 `svyrep.design`，保留
bootstrap、JK1/JKn 或 BRR 的缩放设置，并重现 `wf_variance()` 的不确定性。输出是普通
survey 对象，因此安装 srvyr 后可直接使用 `srvyr::as_survey(survey_design)` 包装。

`generics` 可用时，WFC 会条件注册返回基础 `data.frame` 的 broom 风格方法：

```r
generics::tidy(guided$weights)
generics::glance(guided$diagnostics)
augmented <- generics::augment(
  guided$weights,
  data = analysis,
  id = "id"
)
```

所有桥接与回填方法都要求单元 ID 唯一且集合完全一致，不会静默丢弃未匹配行。

## 事后分层（Post-stratification）

事后分层使用联合总体单元格，而非边际总量。构建目标时设置 `keep_joint = TRUE`，
声明一个可复核的合并阶梯，然后规划并执行单元格级校准。

```r
target_joint <- wf_target_population(
  pop = wfc_example$population,
  key_map = c(gender = "gender", age = "age"),
  count = "count",
  dims = dims,
  by = "province",
  keep_joint = TRUE
)

ladder <- wf_collapse_ladder(
  dims,
  level1 = list(age = c(young = "all", old = "all"))
)

plan <- wf_plan_poststrat(
  wfc_example$sample,
  target_joint,
  min_cell = 2,
  ladder = ladder
)
plan

post <- wf_poststrat(
  wfc_example$sample,
  target_joint,
  min_cell = 2,
  ladder = ladder,
  id = "id"
)
wf_diagnose(post)
```

## 基础 API（Foundation API）

手工边际表可直接转换为目标，并通过统一调度器进行校准。也可以在校准前把目标向参考目标收缩。

```r
manual <- data.frame(
  dimension = c("gender", "gender", "age", "age"),
  category = c("female", "male", "young", "old"),
  value = c(55, 45, 60, 40)
)

target_manual <- wf_target_manual(manual, dims)
weights_manual <- wf_calibrate(
  wfc_example$sample,
  target_manual,
  method = "raking",
  id = "id"
)
wf_diagnose(weights_manual)
```

## 生产化与性能

重复性生产轮次可用 `wf_pipeline()` 声明，用 `wf_run()` 执行，并通过
`wf_validate()` 与参考版本比较权重漂移。`wf_audit_export()` 可导出包含来源、
输入哈希与元数据的 JSON 审计记录。

```r
spec <- wf_pipeline(
  target = list(
    mode = "population",
    key_map = c(gender = "gender", age = "age"),
    count = "count",
    by = "province"
  ),
  stages = list(calibrate = list(method = "raking", id = "id")),
  validate = list(max_deff = 6, max_margin_dev = 0.01)
)

round1 <- wf_run(spec, wfc_example$sample, dims = dims,
                 population = wfc_example$population)
wf_validate(round1, weights, target = target)
```

较长的分组校准和重复权重 refit 支持可选 fork 并行和 `cli` 进度条：

```r
weights_parallel <- wf_rake(
  wfc_example$sample,
  target,
  id = "id",
  parallel = TRUE,
  progress = TRUE
)
```

## 易用性基础（0.10）

0.10 在现有统计引擎之上增加审核与沟通工具。`wf_auto_trim()` 只推荐、不会自动应用
截尾上限；`wf_suggest_ladder()` 生成供人工复核的合并阶梯草案；`wf_report()` 可生成
面向管理者或分析人员的结构化质量报告。

```r
trim_advice <- wf_auto_trim(
  wfc_example$sample,
  target,
  id = "id",
  caps = c(2, 4, 8)
)
plot(trim_advice)

report <- wf_report(weights, target, audience = "manager")
report

ladder_draft <- wf_suggest_ladder(
  wfc_example$sample,
  target,
  dims,
  min_cell = 25
)
ladder_draft
```

`wf_weights`、`wf_diagnostics`、融合结果和倾向权重结果也都提供了 base R `plot()` 方法。

## 函数速查

| 阶段 | 函数 | 用途 |
| --- | --- | --- |
| 引导 | `wf_autoweigh()` | 运行目标构建、预检查、已声明整改、校准、诊断、报告和决定记录。 |
| 桥接 | `as_svydesign()` | 按严格 ID 将校准权重转换为标准 survey 设计。 |
| 桥接 | `as_svrepdesign()` | 将 WFC 重复权重转换为不确定性等价的 survey 重复设计。 |
| 整理 | `generics::tidy()` / `glance()` / `augment()` | 将 WFC 结果投影为稳定基础表，或按 ID 回填分析数据。 |
| 维度 | `wf_dims()` | 声明校准维度及可选的合并阶梯。 |
| 目标 | `wf_target_population()` | 从外部总体数据构建规范化目标。 |
| 目标 | `wf_target_reference()` | 从加权参考样本构建目标。 |
| 目标 | `wf_target_manual()` | 从手工长格式边际表构建目标。 |
| 目标 | `wf_target_shrink()` | 将目标向参考目标收缩。 |
| 预检查 | `wf_precheck()` | 校准前检查样本与目标的兼容性。 |
| 合并 | `wf_collapse_ladder()` | 声明事后分层的合并阶梯。 |
| 合并 | `wf_suggest_collapse()` | 依据预检查结果给出合并建议。 |
| 合并 | `wf_suggest_ladder()` | 根据稀疏支持度生成可复核的事后分层阶梯草案。 |
| 合并 | `wf_apply_collapse()` | 将合并方案应用到样本与目标。 |
| 校准 | `wf_calibrate()` | 调度到具体校准方法（raking、事后分层、greg、logit、soft、ebal）。 |
| 校准 | `wf_rake()` | 分组 raking（迭代比例拟合）。 |
| 校准 | `wf_plan_poststrat()` | 规划事后分层的单元格解析。 |
| 校准 | `wf_poststrat()` | 执行单元格级事后分层。 |
| 生产 | `wf_pipeline()` | 声明可序列化的加权轮次。 |
| 生产 | `wf_run()` | 执行声明式流水线。 |
| 生产 | `wf_validate()` | 与参考版本比较权重漂移。 |
| 生产 | `wf_audit_export()` | 写出 JSON 审计记录。 |
| 组合 | `wf_compose()` | 将多个加权阶段相乘为一个可审计结果。 |
| 融合 | `wf_blend()` | 在估计量层面融合线上与线下两个来源。 |
| 倾向 | `wf_target_propensity()` | 将线上样本与概率参考样本堆叠为成员模型规格。 |
| 倾向 | `wf_propensity()` | 产出逆倾向伪设计权重，附重叠与平衡诊断。 |
| 流失 | `wf_attrition()` | 为面板未留存估计逆留存权重。 |
| 影响 | `wf_influence()` | 排序高影响样本单元，辅助截尾和审核。 |
| 方差 | `wf_replicates()` | 生成重新校准的 bootstrap/jackknife/BRR 重复权重。 |
| 方差 | `wf_variance()` | 将重复权重与估计量组合为估计值、标准误与置信区间。 |
| 建议 | `wf_auto_trim()` | 根据偏差—方差前沿推荐截尾上限。 |
| 诊断 | `wf_diagnose()` | 诊断校准后的权重与边际。 |
| 报告 | `wf_report()` | 生成管理者/分析者质量报告对象、Markdown 或 HTML。 |
| 可视化 | `plot()` | 绘制权重、诊断、截尾前沿、融合敏感性或倾向质量。 |

所有导出函数均带有完整文档。在 R 中可用 `?wf_rake`、`help(package = "WFC")`
或 `example(wf_target_population)` 查看。

## 数据政策

`private-data/` 下的私有源电子表格和 RData 文件**不会提交**到仓库，也**不会**随 R 包发布。
所有示例与测试仅使用由 `data-raw/make-wfc-example.R` 生成的模拟数据集 `wfc_example`。

## 项目状态

1.0.0 冻结了 WFC 核心的公开 API。稳定范围包括 raking、事后分层、手工目标与目标收缩、
合并规划、权重组合、双源融合、倾向得分与面板流失校正、重复权重方差、有界校准、
软校准、熵平衡、生产流水线、漂移验证、审计导出、质量报告、截尾建议、阶梯草案、
诊断图、survey/srvyr 桥接、broom 风格投影、双语人机输出以及可选并行执行。
因 CRAN 上存在同名包，本包已于 0.9.0 从 `weightflow` 更名为 `WFC`。完整变更见
[`NEWS.md`](NEWS.md)。

设计文档位于 [`inst/design/`](inst/design/)（英文），其中
[`wfc_future_design.md`](inst/design/wfc_future_design.md) 为 0.10 → 1.0 的未来路线
（引导式工作流、生态桥接、生产基础设施、软校准等），对应的参考原型实现位于
[`inst/reference/`](inst/reference/)。

## 参与贡献

欢迎贡献。请先阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md) 了解开发环境、
测试驱动流程与语言政策，并在提交 issue 或 pull request 前阅读
[行为准则](.github/CODE_OF_CONDUCT.md)。面向自动化 agent 的仓库约定见 [`AGENTS.md`](AGENTS.md)。

## 许可证

基于 [MIT 许可证](LICENSE.md) 发布。© 2026 惟安数据科技（北京）有限公司（WEIAN DATA TECH）。本项目版权 100% 归惟安数据科技所有。
