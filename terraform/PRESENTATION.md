# Presentation 运行文档

## 0. 演讲前准备（提前 15 分钟做完）

- [ ] Vocareum 页面点 **Start Lab**，等绿灯
- [ ] 复制新的临时凭据覆盖 `~/.aws/credentials`（**本机凭据目前已过期**，`aws sts get-caller-identity` 报错就是没刷新）
  ```bash
  aws sts get-caller-identity --region us-east-1   # 验证凭据有效
  ```
- [ ] 确认三层环境都还活着，没有被误删：
  ```bash
  cd terraform/envs/phase2 && terraform output web_url
  cd ../phase3 && terraform output web_url
  cd ../phase4 && terraform output alb_url
  ```
- [ ] 确认 ASG 处于 baseline（2 台，CPU 低），别在别人压测/上次 demo 的余波里开场：
  ```bash
  aws autoscaling describe-auto-scaling-groups --region us-east-1 \
    --auto-scaling-group-names capstone-phase4-asg \
    --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Running:length(Instances)}' --output table
  ```
  如果不是 2/2，等它自然缩容，或者见第5节"应急处理"
- [ ] 装好压测工具（如果本机还没装）：`npm install -g loadtest`
- [ ] 准备两个终端窗口 + 一个浏览器标签页（见第2节)
- [ ] 提前 3-5 分钟在后台偷跑一次压测（见第4节"抢跑"说明），避免现场从 0 等 CloudWatch 评估窗口

## 1. 三个环境的访问域名

| Phase | 内容 | 访问地址 | 说明 |
|---|---|---|---|
| Phase 2 | 单机 POC | http://18.233.155.137 | Web+DB同机，IP 是 EC2 自动分配的公网IP |
| Phase 3 | 拆分层 | http://3.80.86.31 | Web连RDS，走Secrets Manager取密码 |
| Phase 4 | ALB+ASG | http://capstone-phase4-alb-1378455252.us-east-1.elb.amazonaws.com | **正式演示用这个**，ALB域名是AWS自动生成的 |

> IP/ALB域名如果重新 `apply` 过会变，正式讲之前务必用上面第0节的 `terraform output` 命令重新取一遍最新值。

## 2. 窗口布局建议

```
┌─────────────────────┬─────────────────────┐
│  终端 A：压测命令      │  终端 B：实时监控面板   │
│  (loadtest)          │  (watch-asg.sh)      │
├─────────────────────┴─────────────────────┤
│  浏览器：AWS 控制台 EC2 → Auto Scaling      │
│  Groups → capstone-phase4-asg → Activity   │
└─────────────────────────────────────────────┘
```

再开一个浏览器标签页停在 `http://<ALB_URL>/students`，随时可以切过去展示"网站正常访问、增删改查"。

## 3. 讲解流程（建议控制在 8-10 分钟）

**第1步 - 架构讲解（2分钟）**
打开 `DEPLOYMENT.md` 里的架构图或你自己画的架构图，讲清楚三层：
> "Phase2 是单机验证可行性；Phase3 把数据库拆到 RDS、密码放进 Secrets Manager 不写死在代码里；Phase4 加了负载均衡和自动扩缩容，这是最终形态。"

**第2步 - 功能演示（1分钟）**
切到浏览器 `http://<ALB_URL>/students`，现场点一下增删改查其中一两项，证明"高可用架构下功能没打折"。

**第3步 - 展示当前 baseline（1分钟）**
```bash
./terraform/scripts/watch-asg.sh
```
留在屏幕上，指着说："现在 desired=2，CPU 个位数，这是正常负载下的状态。"

**第4步 - 打压测流量（讲解同时进行，不用等）**
切到终端 A：
```bash
loadtest --rps 1000 -c 500 -k -t 300 http://<ALB_URL>/students
```
一边讲一边看请求数、延迟往上跳：
> "现在模拟大量并发学生同时查档案，可以看到延迟和错误率都在上升，说明流量已经超过两台实例的承载能力。"

**第5步 - 等待扩容触发，同时讲解原理（3-5分钟，跟第4步并行）**
这段时间可以讲 Target Tracking 的原理，避免死等：
> "CPU 使用率被 CloudWatch 每分钟采样一次，Target Tracking 策略设定的目标是 50%，连续几个周期超过阈值后会触发扩容告警,ASG 收到告警后调用 Auto Scaling API 增加 Desired Capacity,新实例走 Launch Template 起来，健康检查通过后才会挂到 ALB 上开始接流量。"

**第6步 - 展示扩容瞬间（高潮点）**
切到终端 B 的 `watch-asg.sh` 或者浏览器里的 Activity 页面，指着新出现的 `Launching a new EC2 instance` 事件和 `Desired: 2 → 4`：
> "可以看到系统自动从 2 台扩到 4 台，不需要人工干预。"

**第7步 - 收尾（1分钟）**
> "压力消退之后，Target Tracking 策略也会自动把实例数缩回 2 台，全程没有人工操作，这就是我们要的弹性伸缩。"

## 4. "抢跑"说明（如果演讲时间很紧）

上次实测从压测开始到 Desired Capacity 真的变化，大约需要 **5-6 分钟**（CloudWatch 数据聚合 + 评估窗口 + 实例预热）。如果你的演讲环节留给这部分不到 5 分钟：

- 在演讲**正式开始前 5-6 分钟**，先在后台跑起压测（同样的命令，加 `&` 或者单独开一个不投屏的窗口）
- 讲到第4步时，直接说"压测已经在跑了"，切到终端 B 展示已经在发生或即将发生的扩容，不用现场从 0 等

## 5. 应急处理

- **压测没触发扩容**：多半是 CPU 没冲过 50%。可以临时把 `envs/phase4/variables.tf` 里 `target_cpu_utilization` 改成 20 再 `terraform apply`（几秒钟生效，不会重建实例），下次压测会更容易触发。**演示完记得改回 50 再 apply 一次**。
- **AWS 控制台 Activity 页面看不到事件**：确认看的是 `capstone-phase4-asg` 这个 ASG，不是别的。
- **网站打不开/延迟极高，演示效果差**：这其实是压测本身的正常现象（500并发下延迟会到几秒甚至更高），可以顺势讲："这也是为什么需要横向扩容——单纯堆并发下，两台实例已经不够用了。"
- **凭据中途过期**：Vocareum 重新复制一份到 `~/.aws/credentials`，Terraform/AWS CLI 立刻生效，不影响正在运行的压测和 ASG（那些是 AWS 侧独立运行的，跟你本机凭据没关系）。

## 6. 演讲结束后

```bash
# 检查 ASG 是否已经缩回 baseline
aws autoscaling describe-auto-scaling-groups --region us-east-1 \
  --auto-scaling-group-names capstone-phase4-asg \
  --query 'AutoScalingGroups[0].DesiredCapacity' --output text

# 如果改过 target_cpu_utilization 记得改回 50 并重新 apply
cd terraform/envs/phase4 && terraform apply
```
