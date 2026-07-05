# Deployment Guide: Highly Available, Scalable Student Records Web App (AWS Academy Capstone)

Implements Phases 2-4 of the *Building a Highly Available, Scalable Web Application* assignment entirely in Terraform (IaC tool: Terraform, AWS Provider ~> 5.0).

## 1. Architecture Overview

```
Phase 2 (single-instance POC)
  VPC(10.0.0.0/16) -> 1 public subnet (us-east-1a) -> 1 EC2 (Node app + local MySQL)

Phase 3 (decouple app and data tiers, extends Phase 2's VPC)
  Adds to the same VPC:
    - a 2nd public subnet (us-east-1b)
    - 2 private subnets (us-east-1a/1b) -> RDS MySQL (single AZ, enhanced monitoring disabled)
  New: Secrets Manager secret (Mydbsecret) holding DB connection info
  New: Cloud9 environment, used to migrate Phase 2's data into RDS
  New: a 2nd EC2 (attached to LabInstanceProfile, reads DB connection info from Secrets Manager)

Phase 4 (load balancing + elastic scaling, reuses Phase 3's VPC/subnets/RDS)
  ALB (spanning 2 public subnets) -> Target Group -> Auto Scaling Group (min 2 / max 4)
  Launch Template (same Phase 3 user-data + LabInstanceProfile)
  Target Tracking scaling policy (CPU target 50%)
  Replaces Phase 3's standalone web instance as the traffic entry point
```

The three environments' Terraform state depend on each other (via `terraform_remote_state` reading each other's local state files — they are not independent):

```
phase2 (owns the VPC/IGW)
   ^ referenced by
phase3 (adds subnets/RDS/Secrets/Cloud9 into phase2's VPC)
   ^ referenced by
phase4 (adds ALB/ASG on top of phase3's subnets/RDS security group)
```

**Because of this, teardown must happen in reverse: destroy phase4 first, then phase3, then phase2.**

## 2. Repository Layout

```
terraform/
├── modules/
│   ├── network/    VPC, public/private subnets, route tables, IGW (used by Phase 2; Phase 3 adds
│   │               resources directly into that VPC instead of reusing this module)
│   ├── security/   Generic security group: cidr_ingress_rules (allow by CIDR) +
│   │               sg_ingress_rules (allow by source security group)
│   ├── compute/     Single EC2 instance (used by Phase 2/Phase 3)
│   ├── secrets/     Secrets Manager secret + version
│   └── database/    RDS subnet group + instance
├── envs/
│   ├── phase2/      Single-instance POC
│   ├── phase3/      Decoupled tiers + RDS + Secrets + Cloud9
│   └── phase4/      ALB + ASG
└── scripts/
    ├── userdata-phase2.sh   Official script: installs MySQL locally, creates the STUDENTS DB
    ├── userdata-phase3.sh   Official script: installs only mysql-client; DB connection info
    │                        comes from Secrets Manager
    └── cloud9-scripts.yml   Official Cloud9 script bundle (create secret, load test, migrate data)
```

## 3. Prerequisites

- An AWS Academy Learner Lab session — click **Start Lab**
- Terraform installed locally (`brew install hashicorp/tap/terraform`) and AWS CLI (`brew install awscli`)
- Copy the temporary credentials from Vocareum ("AWS Details -> AWS CLI") into `~/.aws/credentials`
  (must include `aws_session_token`; it expires after a few hours and needs to be re-copied)
- Confirm the account already has the `vockey` key pair (`aws ec2 describe-key-pairs`)
- Get your own public IP (`curl ifconfig.me`) to restrict SSH access to it

## 4. Deployment Steps

### Phase 2

```bash
cd terraform/envs/phase2
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: allowed_ssh_cidr = "YOUR_IP/32", key_name = "vockey"
terraform init
terraform plan -out=phase2.tfplan
terraform apply "phase2.tfplan"
```

Creates 10 resources: VPC, IGW, 1 public subnet, route table, `web-sg` (80/22), 1 `t3.small` EC2 instance.

Verify:
```bash
terraform output web_url
# Wait 1-2 minutes for user-data to finish (installs Node/MySQL, creates the DB, pulls the app code),
# then open it in a browser.
```

### Phase 3

```bash
cd ../phase3
cp terraform.tfvars.example terraform.tfvars   # fill in allowed_ssh_cidr / key_name again
terraform init
terraform plan -out=phase3.tfplan
terraform apply "phase3.tfplan"
```

Creates 22 resources: a 2nd public subnet, 2 private subnets, `web-sg`/`db-sg`, a randomly generated
DB password stored in Secrets Manager (`Mydbsecret`), RDS MySQL, a new EC2 instance (attached to
`LabInstanceProfile`), a Cloud9 environment.

**Data migration (Task 6, a manual one-time operation — intentionally not automated in Terraform)**:

1. Open Cloud9 (AWS Console -> Cloud9 -> find the environment -> Open)
2. Export from the old Phase 2 instance (Cloud9 shares the same VPC, so you can use its private IP):
   ```bash
   mysqldump -h <Phase2 instance private IP> -u nodeapp -p --databases STUDENTS > data.sql
   # password: student12
   ```
3. Import into the new RDS instance:
   ```bash
   mysql -h <rds_address output> -u nodeapp -p STUDENTS < data.sql
   # password: fetch it from Secrets Manager ->
   #   aws secretsmanager get-secret-value --secret-id Mydbsecret --region us-east-1
   ```
4. Verify: open `terraform output web_url` -> `/students`; you should see the migrated data.

### Phase 4

```bash
cd ../phase4
cp terraform.tfvars.example terraform.tfvars   # fill in allowed_ssh_cidr / key_name again
terraform init
terraform plan -out=phase4.tfplan
terraform apply "phase4.tfplan"
```

Creates 14 resources: `alb-sg`/`asg-web-sg`, ALB, Target Group, Listener, Launch Template,
ASG (min 2 / max 4 / desired 2), Target Tracking policy (CPU 50%).

Verify:
```bash
terraform output alb_url    # open in a browser, test create/read/update/delete
```

Load test to verify scaling (run `loadtest` locally — the ALB is public, no need to run it from Cloud9):
```bash
npm install -g loadtest
loadtest --rps 1000 -c 500 -k -t 120 <alb_url>/students
```
Once CPU crosses 50%, the ASG's Desired Capacity automatically climbs from 2 to 4 within a few
minutes, then scales back down once the load subsides.

## 5. Issues Encountered During Deployment and Their Fixes

| Issue | Root Cause | Fix |
|---|---|---|
| `for_each` error in the `security` module | Filtered rules by "is this field null," and Terraform can't evaluate that at plan time when the field's value is a resource ID that doesn't exist yet (e.g. a reference to another security group not yet created) | Split into two separate variables, `cidr_ingress_rules` / `sg_ingress_rules`, so the for_each keys only depend on statically-known list indices |
| Security group `description` with an apostrophe fails to apply | AWS security group rule descriptions only allow the character set `a-zA-Z0-9.\_\-:/()#,@[]+=&;{}!$*` | Reworded the description to avoid apostrophes |
| Changing `description` forces security group replacement | AWS security group `description` is immutable — changing it forces the resource to be replaced | Avoided touching `description` when only adding a rule, to keep the change minimal |
| Cloud9 couldn't reach MySQL on the Phase 2 instance | Phase 2's `web-sg` only opened 80/22, not 3306 | Added a rule to Phase 2's `web-sg` allowing 3306 only from the VPC's internal CIDR |
| Cloud9 couldn't reach the new RDS instance | `db-sg` only allowed the web tier's security group, not Cloud9's own security group | Used `data "aws_security_group"` to look up Cloud9's auto-generated security group by its environment tag, then added a rule allowing it |
| Phase 3's website showed "failed to retrieve student list" | **Not a permissions issue** (verified by replaying the exact API call directly on the instance via SSM — the secret was readable). The real cause was a race condition: the EC2 user-data only reads Secrets Manager once at boot, but RDS took ~6 minutes to provision, so the secret was created after the app had already started and permanently failed over to a nonexistent `localhost` | Rebooted the instance (`aws ec2 reboot-instances`), which re-triggers `/etc/rc.local` and re-runs `npm start` — by then the secret existed and was read successfully |
| Would the same race condition recur when deploying Phase 4? | No — by the time Phase 4 is created, RDS and the secret already exist (Phase 3 already ran), so the ASG instances read the secret correctly on their first boot | No action needed |

## 6. Key Design Decisions

- **Terraform chains the three environments via local state + `terraform_remote_state`**, rather than
  three fully independent VPCs — this stays closer to the assignment's intent of "extending what you
  already built." The tradeoff is that Phase 2 can't be freely `destroy`ed, since Phase 3/4 both depend
  on its VPC/IGW.
- **The database migration is intentionally not encoded in Terraform**: it's a one-time operation
  requiring an interactive password prompt; wrapping it in `null_resource`/`local-exec` would be less
  safe and harder to maintain, so it's kept as a manual runbook step.
- **No NAT Gateway**: the private subnets only host RDS, which doesn't need outbound internet access,
  saving the NAT Gateway's fixed hourly cost.
- **The Secrets Manager secret name is fixed as `Mydbsecret`**: the official Node.js app code we
  downloaded (`app/config/config.js`) hardcodes this name, so the Terraform `secret_name` variable's
  default is aligned with it.

## 7. Teardown

Destroy in reverse dependency order:

```bash
cd terraform/envs/phase4 && terraform destroy
cd ../phase3 && terraform destroy
cd ../phase2 && terraform destroy
```

Or, without destroying anything, click **End Lab** on the Vocareum page (resources are retained and
still count against your overall lab budget, but stop actively running until you Start Lab again).
