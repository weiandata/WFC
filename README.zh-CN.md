# WFC

WFC 是一个强调可复核性的 R 语言社会调查加权包。2.0 版把一条规则变成
强制要求：只有已经声明用途的抽样设计变量，以及来源独立、证据完整并经过校验的
目标数据，才能用于生成权重。研究结果变量只能在权重锁定以后接入。

它同时服务两类使用者：

- 社会调查人员可以按清晰步骤操作，遇到问题时看到普通人能懂的停止原因和下一步；
- 统计团队和 AI Agent 可以读取稳定的对象、身份值、错误代码和完整审计字段。

同一个结果对象可以生成简短的决策者版本，也可以生成完整的统计人员版本，两个版本
必须相互一致。

## WFC 2.0 会阻止什么

公开加权函数不再接受原始数据框、普通目标对象、演示目标、被修改过身份的对象、
Agent 自我批准，以及运行时临时改变 ID 或基础权重。手工目标、目标收缩、内联目标
矩、手工流水线模式和运行时注入边际都不再受支持。

这些限制能够降低误用和常见滥用风险，但不能证明外部来源一定真实，也不能阻止有人
直接修改开源代码。因此，重要分析仍然需要有责任的人工审查。

## 安装

从 GitHub 安装开发版本：

```r
remotes::install_github("weiandata/WFC")
```

## 安全流程需要哪些文件

一次正式运行通常从四个文件开始：

1. 只包含 ID、校准变量和已声明抽样设计变量的调查设计表；
2. 单独保存研究结果变量的分析表；
3. 来自外部权威来源的 CSV 或 Excel 目标表；
4. 与目标表配套的 `.source.dcf` 来源证据记录。

如果不知道目标表格式，可以先生成模板：

```r
library(WFC)

dims <- wf_dims(
  age_group = c("18-34", "35-54", "55+"),
  region = c("north", "south")
)

wf_target_template(
  "population-margins-template.csv",
  dims = dims
)
```

模板会同时生成数据文件和 DCF 表单。目标数据定稿以后，需要填写来源信息并更新
校验值，而且应在查看研究结果之前取得这些文件。

WFC 自带 `safe-target-example.csv`、`safe-target-example.xlsx` 和各自独立的
`.source.dcf` 示例。它们只用于演示格式，不能进入正式规划。

<!-- SAFE_WORKFLOW_START -->

## 完整的受控流程

### 第一步：准备不含结果变量的设计数据

```r
library(WFC)

dims <- wf_dims(
  age_group = c("18-34", "35-54", "55+"),
  region = c("north", "south")
)

design_only <- read.csv("survey-design.csv")
analysis_data <- read.csv("survey-outcomes.csv")

design <- wf_prepare_design(
  design_only,
  id = "person_id",
  calibration = c("age_group", "region"),
  base_weight = "base_weight"
)
```

`design_only` 中的每一列都必须有明确的设计用途。满意度、支持率、得分、是否通过等
结果变量应保留在 `analysis_data` 中。

### 第二步：连同来源证据一起导入外部目标

人口计数目标的导入样本：

```r
target <- wf_import_target(
  data_file = "population-margins.csv",
  source_file = "population-margins.csv.source.dcf",
  dims = dims,
  key_map = c(age_group = "age_group", region = "region"),
  count = "population_count",
  production = TRUE
)
```

独立参考样本目标的导入样本：

```r
reference_target <- wf_import_reference(
  data_file = "reference-sample.csv",
  source_file = "reference-sample.csv.source.dcf",
  dims = dims,
  feature = "reference_weight",
  production = TRUE
)
```

导入时会检查来源字段是否完整、目标是否在查看结果之前选定、是否属于演示数据，
以及 SHA-256 是否匹配。软件不能替代人判断该来源在统计学上是否合适。

### 第三步：在不查看结果变量的情况下制定方案

```r
cell_plan <- wf_plan_cells(
  design,
  target,
  dims,
  min_cell = 5,
  max_weight_ratio = 4
)

plan <- wf_plan_weights(
  design,
  target,
  dims,
  method = "raking",
  bounds = c(0.3, 3),
  min_cell = 5,
  cell_plan = cell_plan
)

plan$ready
plan$issues
is.null(plan$weights)
```

规划阶段不会计算权重，只会记录确切输入、检查结果、方法、限制和确定性的类别合并，
供审查者检查。

### 第四步：由独立的人工审查者批准

```r
approval <- wf_approve_plan(
  plan,
  approver = "审查者完整姓名",
  role = "统计学专家",
  note = "已检查来源、样本支持、方法、限制和预期用途"
)
```

AI Agent 可以准备方案，但不能替自己生成这份批准。姓名和职责必须对应真实的人工
审查者。

### 第五步：只执行未被修改的方案

```r
locked <- wf_execute_plan(
  plan,
  approval,
  design,
  target
)
```

只要设计数据、目标、方案或批准中的任何一项被修改，身份链就会失效，执行会停止。

### 第六步：权重锁定以后再接入结果变量

```r
analysis_ready <- wf_attach_weights(
  analysis_data,
  locked,
  id = "person_id",
  weight_name = ".weight"
)

impact <- wf_assess_impact(
  locked,
  analysis_data,
  id = "person_id",
  outcomes = c("satisfaction", "approved")
)
```

影响评估只能描述已锁定权重带来的变化，不能重新规划、重新批准或改写权重。

### 第七步：为不同读者生成不同层次的结果

```r
decision_view <- wf_report(
  locked,
  audience = "decision"
)

statistical_view <- wf_report(
  locked,
  audience = "statistician"
)

impact_detail <- wf_report(
  impact,
  audience = "statistician"
)

wf_audit_export(locked, "weighting-audit.json")
```

决策者版本重点显示当前状态、主要风险和下一步。统计人员版本提供完整表格、收敛信息、
身份值和来源记录，便于继续分析。

<!-- SAFE_WORKFLOW_END -->

## 统计专业人员的直接入口

专业用户仍然可以直接调用 `wf_calibrate()`、`wf_rake()`、`wf_poststrat()`、
`wf_auto_trim()` 或 `wf_autoweigh()`，但前两个输入仍必须是未被修改的 `design` 和
`target`：

```r
raked <- wf_rake(design, target, tol = 1e-8)

bounded <- wf_calibrate(
  design,
  target,
  method = "logit",
  bounds = c(0.3, 3)
)

trim_review <- wf_auto_trim(
  design,
  target,
  caps = c(2, 4, 6, 8)
)
```

ID 和基础权重列由 `wf_prepare_design()` 统一声明，后续不能临时覆盖。

## AI Agent 接入方式

Agent 应保存完整 WFC 对象及其身份值。可交接给人工审查者的最小对象示例如下：

```r
handoff <- list(
  plan = plan,
  plan_identity = plan$identity,
  design_identity = design$identity,
  target_identity = target$identity,
  required_human_action = "审查并批准未被修改的方案"
)
```

如果 Agent 尝试自我批准，WFC 会返回 `wf_error_safety`。Agent 应读取稳定字段并停止：

```r
refusal <- tryCatch(
  wf_approve_plan(
    plan,
    approver = "Automated agent",
    role = "assistant",
    actor_type = "agent"
  ),
  wf_error_safety = function(condition) condition$data
)

refusal[c("code", "severity", "field", "next_actions")]
```

Agent 不得修改身份值、伪造人工姓名、放宽限制、更换目标，或在看到结果以后重新尝试。

## 从 WFC 1.x 迁移

请参阅[从 WFC 1.x 迁移到 WFC 2.0](docs/migration/wfc-1-to-2.md)。用于预设理想结果的
行为没有兼容开关，也没有受支持的替代路径。

## 许可证

WFC 采用 GPL (>= 2) 许可证。版权与贡献者信息见 `inst/COPYRIGHTS` 和
`DESCRIPTION`。
