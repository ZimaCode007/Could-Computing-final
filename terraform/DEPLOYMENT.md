# 部署文档：高可用可扩展学生档案 Web 应用（AWS Academy Capstone）

对应任务书《Building a Highly Available, Scalable Web Application》的 Phase 2-4，全部用 Terraform 实现（IaC 工具：Terraform，AWS Provider ~> 5.0）。

## 1. 架构总览

```
Phase 2（单机 POC）
  VPC(10.0.0.0/16) → 1个公有子网(us-east-1a) → 1台EC2（Node app + 本地MySQL）

Phase 3（拆分应用层与数据层，在 Phase2 的 VPC 基础上扩展）
  同一 VPC 追加：
    - 第2个公有子网(us-east-1b)
    - 2个私有子网(us-east-1a/1b) → RDS MySQL（单AZ，禁用增强监控）
  新增：Secrets Manager 密钥(Mydbsecret) 存 DB 连接信息
  新增：Cloud9 环境，用于把 Phase2 的数据迁移到 RDS
  新增：第2台EC2（挂 LabInstanceProfile，从 Secrets Manager 读取DB连接信息）

Phase 4（负载均衡 + 弹性伸缩，复用 Phase3 的 VPC/子网/RDS）
  ALB（跨2个公有子网）→ Target Group → Auto Scaling Group（min2/max4）
  Launch Template（同一份 Phase3 user-data + LabInstanceProfile）
  Target Tracking 扩缩容策略（CPU 目标 50%）
  替代 Phase3 的单机 Web 实例作为流量入口
```

三个环境状态相互依赖（通过 `terraform_remote_state` 读取本地 state 文件，非独立）：

```
phase2 (VPC/IGW 的所有者)
   ↑ 被引用
phase3 (在 phase2 的 VPC 里加子网/RDS/Secrets/Cloud9)
   ↑ 被引用
phase4 (在 phase3 的子网/RDS安全组上加 ALB/ASG)
```

**因此销毁顺序必须反过来：先 destroy phase4，再 phase3，最后 phase2。**

## 2. 仓库结构

```
terraform/
├── modules/
│   ├── network/    VPC、公/私有子网、路由表、IGW（供 Phase2 使用；Phase3 直接在其 VPC 上加资源，不复用此模块）
│   ├── security/   通用安全组：cidr_ingress_rules（按CIDR放行）+ sg_ingress_rules（按来源安全组放行）
│   ├── compute/     单台 EC2（Phase2/Phase3 使用）
│   ├── secrets/     Secrets Manager 密钥 + 版本
│   └── database/    RDS 子网组 + 实例
├── envs/
│   ├── phase2/      单机 POC
│   ├── phase3/      拆分层 + RDS + Secrets + Cloud9
│   └── phase4/      ALB + ASG
└── scripts/
    ├── userdata-phase2.sh   官方脚本：本机装 MySQL，起 STUDENTS 库
    ├── userdata-phase3.sh   官方脚本：只装 mysql-client，DB 连接信息靠 Secrets Manager
    └── cloud9-scripts.yml   官方 Cloud9 脚本合集（建密钥、压测、迁移数据）
```

## 3. 前置条件

- AWS Academy Learner Lab，点 **Start Lab**
- 本机安装 Terraform（`brew install hashicorp/tap/terraform`）、AWS CLI（`brew install awscli`）
- 从 Vocareum「AWS Details → AWS CLI」复制临时凭据，写入 `~/.aws/credentials`（含 `aws_session_token`，几小时过期需要重新复制）
- 确认账号里已有密钥对 `vockey`（`aws ec2 describe-key-pairs`）
- 拿到自己的公网 IP（`curl ifconfig.me`）用于限制 SSH 来源

## 4. 部署步骤

### Phase 2

```bash
cd terraform/envs/phase2
cp terraform.tfvars.example terraform.tfvars
# 编辑 terraform.tfvars: allowed_ssh_cidr = "你的IP/32", key_name = "vockey"
terraform init
terraform plan -out=phase2.tfplan
terraform apply "phase2.tfplan"
```

创建资源（10个）：VPC、IGW、1个公有子网、路由表、`web-sg`（80/22）、1台 t3.small EC2。

验证：
```bash
terraform output web_url
# 等1-2分钟user-data跑完（装Node/MySQL/建库/拉代码），再用浏览器打开
```

### Phase 3

```bash
cd ../phase3
cp terraform.tfvars.example terraform.tfvars   # 同样填 allowed_ssh_cidr / key_name
terraform init
terraform plan -out=phase3.tfplan
terraform apply "phase3.tfplan"
```

创建资源（22个）：第2个公有子网、2个私有子网、`web-sg`/`db-sg`、随机生成的DB密码写入 Secrets Manager（`Mydbsecret`）、RDS MySQL、新EC2（挂`LabInstanceProfile`）、Cloud9环境。

**数据迁移（Task 6，手动一次性操作，不放进 Terraform）**：

1. 打开 Cloud9（AWS 控制台 → Cloud9 → 找到环境 → Open）
2. 从 Phase2 旧实例导出（Cloud9 与 Phase2 实例同一 VPC，可用内网IP）：
   ```bash
   mysqldump -h <Phase2实例私网IP> -u nodeapp -p --databases STUDENTS > data.sql
   # 密码: student12
   ```
3. 导入新 RDS：
   ```bash
   mysql -h <rds_address输出> -u nodeapp -p STUDENTS < data.sql
   # 密码: 从 Secrets Manager 取 → aws secretsmanager get-secret-value --secret-id Mydbsecret --region us-east-1
   ```
4. 验证：`terraform output web_url` 打开 `/students`，应该能看到迁移的数据

### Phase 4

```bash
cd ../phase4
cp terraform.tfvars.example terraform.tfvars   # 同样填 allowed_ssh_cidr / key_name
terraform init
terraform plan -out=phase4.tfplan
terraform apply "phase4.tfplan"
```

创建资源（14个）：`alb-sg`/`asg-web-sg`、ALB、Target Group、Listener、Launch Template、ASG（min2/max4/desired2）、Target Tracking 策略（CPU 50%）。

验证：
```bash
terraform output alb_url    # 浏览器打开，测试增删改查
```

压测验证扩容（本机装 loadtest 即可，ALB 是公网地址，不需要在 Cloud9 里跑）：
```bash
npm install -g loadtest
loadtest --rps 1000 -c 500 -k -t 120 <alb_url>/students
```
CPU 超过 50% 后，几分钟内 ASG 的 Desired Capacity 会自动从 2 涨到 4；压力消退后会自动缩回。

## 5. 部署中遇到的问题与修复

| 问题 | 原因 | 修复 |
|---|---|---|
| `security` 模块 `for_each` 报错 | 用"字段是否为 null"做过滤，遇到还没创建出来的资源ID（如引用另一个还不存在的安全组）时 Terraform 无法在 plan 阶段判断 | 拆成 `cidr_ingress_rules` / `sg_ingress_rules` 两个独立变量，for_each 的 key 只依赖静态可知的列表下标 |
| 安全组 `description` 含撇号报错 | AWS 安全组规则描述只允许 `a-zA-Z0-9.\_\-:/()#,@[]+=&;{}!$*` 字符集 | 改用不含撇号的英文描述 |
| 改 `description` 触发安全组重建 | AWS 安全组的 `description` 字段不可变更，改了会强制替换资源 | 改规则时避免顺带改 description，保持最小变更 |
| Cloud9 连不上 Phase2 实例的 MySQL | Phase2 的 `web-sg` 只开了80/22，没开3306 | 给 Phase2 的 `web-sg` 加一条仅限 VPC 内网CIDR访问3306的规则 |
| Cloud9 连不上新 RDS | `db-sg` 只放行了 Web 层的安全组，没放行 Cloud9 自己的安全组 | 用 `data "aws_security_group"` 按 Cloud9 环境的自动标签动态查到其安全组ID，加一条规则放行 |
| Phase3 网站显示"读取学生列表失败" | **不是权限问题**（用 SSM 直接在实例上重放 API 调用验证过，密钥能正常读到）。真实原因是时序竞争：EC2 的 user-data 只在开机瞬间读一次 Secrets Manager，而 RDS 建库耗时约6分钟，密钥比 app 启动晚创建，app 读取失败后永久 fallback 到不存在的 `localhost` | 重启实例（`aws ec2 reboot-instances`），触发 `/etc/rc.local` 重新执行 `npm start`，此时密钥已存在，读取成功 |
| Phase4 部署时同样的时序问题是否会重现 | 不会，因为 Phase4 创建时 RDS 和 Secret 早已存在（Phase3 已经跑过），ASG 实例首次启动就能正确读到密钥 | 无需处理 |

## 6. 关键设计取舍

- **Terraform 用本地 state + `terraform_remote_state` 串联三个环境**，而不是三个完全独立的 VPC——更贴近任务书"在已有基础上扩展"的原意，代价是 Phase2 不能随意 `destroy`（Phase3/4 都依赖它的 VPC/IGW）。
- **数据库迁移不放进 Terraform**：一次性、需要交互输入密码，写成 `null_resource`/`local-exec` 反而不安全也不好维护，保持为手动 runbook。
- **不用 NAT Gateway**：私有子网只放 RDS，RDS 不需要出网，省掉 NAT 的固定小时费。
- **Secrets Manager 密钥名固定为 `Mydbsecret`**：因为下载到的官方 Node.js 代码（`app/config/config.js`）把这个名字硬编码在里面，Terraform 侧的 `secret_name` 变量默认值与之对齐。

## 7. 清理

按依赖关系反向销毁：

```bash
cd terraform/envs/phase4 && terraform destroy
cd ../phase3 && terraform destroy
cd ../phase2 && terraform destroy
```

或者不销毁，直接在 Vocareum 页面点 **End Lab**（资源保留，不计入进行中的使用但仍占用 Lab 总预算，下次 Start Lab 还在）。
