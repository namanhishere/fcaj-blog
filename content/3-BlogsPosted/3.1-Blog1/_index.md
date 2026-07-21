---
title: "Scaling GitLab Runner to zero with EC2 Auto Scaling"
date: 2026-07-21
weight: 1
chapter: false
pre: " <b> 3.1. </b> "
includeInReport: false
---

# Introduction

During my internship project at FCAJ, I hosted all of the source code on my personal GitLab instance and ran a self-managed GitLab Runner on my home computer for CI/CD.

The machine was not powerful enough to run many pipelines at the same time, so I configured it to handle only one concurrent job. Whenever several pipelines were triggered, their jobs had to sit in the queue for a long time. Sometimes an entire pipeline took more than an hour to finish, while AddressSanitizer (ASan) and ThreadSanitizer (TSan) jobs waited more than 30 minutes just to acquire a worker.

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/longqueue.png" alt="GitLab job list showing queue times between 11 and 33 minutes" loading="lazy">
  <figcaption>The jobs were not slow. They simply spent too long waiting for a worker.</figcaption>
</figure>

That made me wonder: instead of upgrading the hardware, why not use an **AWS EC2 Auto Scaling Group**? AWS still offered a USD 200 student credit, so this was also a good opportunity to build a GitLab Runner that could scale with the number of waiting jobs. It solved a real problem I was facing while giving me hands-on experience with AWS infrastructure.

# Design goals

I was not trying to build a complete CI/CD platform or replace GitLab SaaS. My goals were much simpler:

- Do not pay for workers when no pipeline is running (scale to zero).
- Accept a cold start of a few dozen seconds in exchange for a near-zero idle cost.
- Create workers automatically when pipelines arrive, without manual intervention.
- Run every job in a completely fresh environment to prevent cross-job contamination.
- Terminate each worker after its job finishes so that resources are not wasted.

In short, I wanted GitLab Runner to become a service that “exists only when needed.”

# Architecture

The system is divided into two parts.

The first part is the **Runner Manager**, which runs continuously on a small machine. Its only responsibilities are communicating with GitLab, monitoring pipeline demand, and deciding when more workers are required.

The second part consists of **EC2 workers** in an **Auto Scaling Group** with `desired capacity = 0`. Normally, no worker instances exist. When GitLab has a new job, the Runner Manager asks the Auto Scaling Group to launch an instance. After booting, the worker receives exactly one job, runs it inside a Docker container, and then terminates itself.

What I like about this model is that the Runner Manager stays lightweight, while the expensive build capacity exists only when it is actually needed.

<figure>
  <img src="/images/diagrams/gitlab-runner-ec2-autoscale.svg" alt="Architecture diagram of a GitLab Runner Manager controlling an EC2 Auto Scaling Group and ephemeral workers" loading="lazy">
  <figcaption>The system has two main flows: preparing the worker image and executing a CI job on an ephemeral EC2 instance.</figcaption>
</figure>

The lifecycle of a job can be summarized as follows:

1. The Runner Manager receives a job from GitLab over HTTPS.
2. The Fleeting AWS plugin asks the Auto Scaling Group to increase capacity from `0` to `1`.
3. EC2 boots from the custom AMI, then the Runner Manager connects over SSH and starts a Docker container.
4. Logs and results are returned to GitLab.
5. The worker is discarded after the job and capacity returns to `0`.

## One job per machine

The most important part of the Runner configuration is quite short:

```toml
[[runners]]
  executor = "docker-autoscaler"

  [runners.autoscaler]
    plugin                = "aws:latest"
    capacity_per_instance = 1
    max_use_count         = 1
    max_instances         = 10

    [[runners.autoscaler.policy]]
      idle_count = 0
      idle_time  = "5m"
```

`capacity_per_instance = 1` limits each EC2 instance to one job at a time, while `max_use_count = 1` schedules the instance for removal after its first use. I give up local caches and worker reuse in exchange for a cleaner, more predictable environment for every pipeline. In production, `aws:latest` should also be pinned to a specific plugin version.



## Capacity should have only one controller

Terraform creates the Auto Scaling Group, but GitLab Runner is responsible for increasing or decreasing `desired_capacity` during operation. If Terraform also tries to manage this value on every `apply`, the two controllers can pull capacity in different directions.

```hcl
resource "aws_autoscaling_group" "runner" {
  name                = "${var.name_prefix}-asg"
  min_size            = 0
  max_size            = var.max_instances
  desired_capacity    = 0
  vpc_zone_identifier = local.subnet_ids

  launch_template {
    id      = aws_launch_template.runner.id
    version = "$Latest"
  }

  lifecycle {
    # The Fleeting plugin controls capacity after the ASG is created.
    ignore_changes = [desired_capacity]
  }
}
```

`ignore_changes` does not mean that Terraform stops managing the Auto Scaling Group. Terraform still manages the Launch Template, subnets, tags, and other infrastructure properties; it simply does not overwrite the instance count requested by Runner.

# Prebuilding the Docker image with GitHub Actions

One of the first issues I encountered was preparing the build environment.

If every new worker has to install compilers, SDKs, and dependencies before it can run a pipeline, most of its time is spent preparing the environment instead of executing the job.

To solve this, I moved the complete build environment into a separate Docker image. GitHub Actions automatically builds the image and publishes it to GitHub Container Registry (GHCR) whenever it changes.

As a result, every worker uses the same build environment. When a new package or tool is required, I only need to update the Dockerfile and let GitHub Actions rebuild the image.

This also makes the CI environment easier to maintain because all dependencies are defined in one place.

The following is a shortened version of the workflow that builds and publishes the image:

```yaml
name: Build CI image

on:
  push:
    paths:
      - "ci-image/**"

permissions:
  contents: read
  packages: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v7
        with:
          context: ./ci-image
          push: true
          tags: |
            ghcr.io/${{ github.repository }}-ci:latest
            ghcr.io/${{ github.repository }}-ci:sha-${{ github.sha }}
```

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/ghcr.png" alt="Docker image for GitLab Runner workers published to GitHub Container Registry" loading="lazy">
  <figcaption>The CI image on GHCR has both a <code>latest</code> tag and commit-based tags for traceability.</figcaption>
</figure>

The demo still uses `latest` for convenient updates. If stronger reproducibility is required, workers should pull the image by digest or an immutable tag instead of using a tag that can point to different content over time.

# Baking the virtual machine image

Having a Docker image was not enough.

If every new EC2 instance had to install Docker and pull the image from GHCR during startup, the cold start would still be relatively long. In a system designed to scale from zero, that delay appears on the first job of every pipeline burst.

I therefore used Packer to create a **custom Amazon Machine Image (AMI)**.

The AMI already contains:

- Docker
- the required tools
- the Docker image used by CI jobs

Packer uses the `amazon-ebs` builder, runs a provisioning script, and packages the final state as an AMI:

```hcl
build {
  name    = "gitlab-runner-worker"
  sources = ["source.amazon-ebs.runner"]

  provisioner "shell" {
    environment_vars = [
      "CI_IMAGE=${var.ci_image}",
      "SSH_USER=${var.ssh_username}",
    ]
    script = "${path.root}/scripts/install.sh"
  }
}
```

The provisioning script installs Docker and runs `docker pull "${CI_IMAGE}"` while building the AMI. Because the image layers are already on disk, a new worker only needs to check for or download layers that have changed during startup.

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/config.png" alt="Packer variable file containing the region, instance type, and GHCR CI image address" loading="lazy">
  <figcaption>The input values used by Packer to build the worker AMI.</figcaption>
</figure>

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/build_image.png" alt="Packer logs showing a Docker image pull and the creation of an Amazon Machine Image" loading="lazy">
  <figcaption>The test build finished in 6 minutes and 44 seconds; that setup cost is paid once instead of on every job.</figcaption>
</figure>

When the Auto Scaling Group creates a worker, the machine can begin running a job almost immediately without reinstalling everything from scratch.

Building the AMI takes a few extra minutes, but this is a one-time cost. In return, every worker created afterward starts much faster.

# Observing the worker lifecycle

To verify autoscaling, I monitored the Runner logs and the Auto Scaling Group state at the same time:

```bash
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names <asg_name> \
  --query "AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances[].LifecycleState}"'
```

When the system works correctly, `desired` follows the sequence `0 → 1 → 0`. During a burst of jobs, EC2 instances in the `Initializing`, `Running`, `Shutting-down`, and `Terminated` states can appear at the same time because each worker has its own lifecycle.

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/ec2.png" alt="Ephemeral EC2 workers in running, shutting-down, and terminated states" loading="lazy">
  <figcaption>New workers and workers being reclaimed can overlap during a pipeline burst.</figcaption>
</figure>

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/runner.png" alt="An online GitLab Runner using the Docker Autoscaler executor and processing jobs" loading="lazy">
  <figcaption>The Runner Manager remains online in GitLab even when the number of EC2 workers is zero.</figcaption>
</figure>

# Conclusion

After completing the setup, my GitLab Runner could scale automatically with the number of waiting pipelines.

When there are no jobs, all EC2 workers are terminated and the idle cost is close to zero. When a new pipeline arrives, the Auto Scaling Group creates a worker, runs exactly one job, and reclaims the instance afterward.

This is not yet a production-ready system. I still want to move it into private subnets, replace access keys with IAM roles, pin images by digest, and add monitoring for the entire worker initialization process.

Even so, the project helped me understand how GitLab Runner Autoscaler works and how Terraform, Packer, and an AWS Auto Scaling Group can be combined to build an elastic CI/CD system without maintaining a continuously running worker fleet.

## References

- [GitLab Docker Autoscaler executor](https://docs.gitlab.com/runner/executors/docker_autoscaler/)
- [GitLab Runner advanced configuration](https://docs.gitlab.com/runner/configuration/advanced-configuration/#the-runnersautoscaler-section)
- [HashiCorp: Manage AWS Auto Scaling Groups with Terraform](https://developer.hashicorp.com/terraform/tutorials/aws/aws-asg)
- [HashiCorp Packer: Amazon EBS builder](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/builder/ebs)
