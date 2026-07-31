---
title: "Monitoring"
date: 2024-01-01
weight: 7
chapter: false
pre: " <b> 5.8. </b> "
---

For awsplace, we built a multi-layered monitoring setup so we always know exactly what's going on. We use CloudWatch dashboards to see things in real-time, alarms to alert us when things go wrong, health checks to keep our containers running smoothly, and centralized logging to help us figure out why something broke. We define all of this right in our CDK code, so there's no need to click around the AWS console—and it's all tested automatically before deployment.

Here's a look at our monitoring setup:

| Sub-section | Description |
|---|---|
| [5.8.1 CloudWatch Dashboards](5.8.1-cloudwatch-dashboards/) | Visual panels for our Raft metrics, EFS storage, container CPU/RAM usage, and load balancer health |
| [5.8.2 CloudWatch Alarms](5.8.2-cloudwatch-alarms/) | Alerts for high CPU/memory, data snapshot issues, deployment rollbacks, and failed health checks |
| [5.8.3 Container & Application Health Checks](5.8.3-health-checks/) | Keeping containers healthy with ECS and ALB health probes, plus rules for how containers should start up |
| [5.8.4 Centralized Logging](5.8.4-centralized-logging/) | Storing and organizing all our logs in CloudWatch so we can easily search them when debugging |

#### Monitoring Philosophy

Our approach to monitoring is simple: **we only monitor things that actually break our application**. Instead of cluttering our dashboards with every metric AWS offers, we focus on what matters:

1. **Track the important stuff**: We track custom Raft metrics from our database nodes (using specific **Cluster** and **NodeId** tags) so we can see exactly who is doing what.
2. **Alarm on data loss risks**: We trigger alarms for durability issues—like outdated snapshots or write errors—because losing data is the biggest risk.
3. **Catch broken deployments**: If a container's CPU usage stays suspiciously low after a deploy, we trigger an alarm because it usually means the app failed to start.
4. **Ignore missing data safely**: We treat missing data as "normal" for most alarms. This way, when we start a fresh stack, we don't get spammed with false alerts just because the data hasn't arrived yet.

This keeps our dashboards clean and our alerts useful. When an alarm goes off, we know exactly what to fix.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion: A diagram showing the monitoring layers of the awsplace project:
- Top: CloudWatch Dashboards (real-time visualization)
- Middle: CloudWatch Alarms (automated alerting)
- Bottom: Health Checks + Centralized Logging (service-level diagnostics)
Save as: static/images/5.7/monitoring-layers.png
-->
