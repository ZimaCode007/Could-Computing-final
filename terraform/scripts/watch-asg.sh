#!/bin/bash
# Live monitor for the Phase 4 demo: shows ASG capacity + latest CPU while a load test runs.
# Usage: ./watch-asg.sh

ASG_NAME="capstone-phase4-asg"
REGION="us-east-1"

while true; do
  clear
  echo "=== $(date -u +%H:%M:%S) UTC ==="
  echo
  echo "--- ASG capacity ---"
  aws autoscaling describe-auto-scaling-groups --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Running:length(Instances)}' \
    --output table

  echo
  echo "--- Latest CPUUtilization ---"
  END=$(date -u +%Y-%m-%dT%H:%M:%S)
  START=$(date -u -v-10M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '-10 minutes' +%Y-%m-%dT%H:%M:%S)
  aws cloudwatch get-metric-statistics --region "$REGION" \
    --namespace AWS/EC2 --metric-name CPUUtilization \
    --dimensions Name=AutoScalingGroupName,Value="$ASG_NAME" \
    --start-time "$START" --end-time "$END" --period 60 --statistics Average \
    --query 'Datapoints | sort_by(@, &Timestamp)[-3:].{Time:Timestamp,Avg:Average}' \
    --output table

  echo
  echo "--- Recent scaling activity ---"
  aws autoscaling describe-scaling-activities --region "$REGION" \
    --auto-scaling-group-name "$ASG_NAME" --max-items 3 \
    --query 'Activities[].{Time:StartTime,Desc:Description,Status:StatusCode}' \
    --output table

  sleep 10
done
