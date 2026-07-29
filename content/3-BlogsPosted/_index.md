---
title: "Blogs Posted"
linkPreviewLabel: "Blog Post"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 3. </b> "
includeInReport: false
---

This is where I write up the technical problems I run into while building and testing systems: what I tried, why I chose it, and what I would still improve. All three posts below were published in the AWS Study Group Facebook group.

### Scaling GitLab Runner to zero with EC2 Auto Scaling

[Read the post](3.1-Blog1/)

This article explains how I combined GitLab Runner's Docker Autoscaler, the Fleeting AWS plugin, Terraform, Packer, and an EC2 Auto Scaling Group to create one temporary worker per job and scale the worker fleet back to zero when the queue is empty.

<figure>
  <a href="/3-blogsposted/3.1-blog1/" aria-label="Read Scaling GitLab Runner to zero with EC2 Auto Scaling">
    <img src="/images/diagrams/gitlab-runner-ec2-autoscale.svg" alt="GitLab Runner architecture using an EC2 Auto Scaling Group and ephemeral workers" loading="lazy">
  </a>
  <figcaption>Build the worker image once, launch isolated EC2 workers on demand, and return capacity to zero after the jobs finish.</figcaption>
</figure>

<div hidden aria-hidden="true">

![GitLab Runner architecture using an EC2 Auto Scaling Group and ephemeral workers](/images/diagrams/gitlab-runner-ec2-autoscale.png)

</div>

### Keyless AWS deployments from self-hosted GitLab CI with OIDC

[Read the post](3.2-Blog2/)

This article covers how the awsplace pipeline deploys to AWS with no stored access key: GitLab mints a signed OIDC token per job, IAM verifies the issuer, `aud` and `sub` claims, and `sts assume-role-with-web-identity` returns a 3600-second session. It then follows the RaftDB image chain of custody, where the job that builds and scans the image holds no AWS credential at all.

<figure>
  <a href="/3-blogsposted/3.2-blog2/" aria-label="Read Keyless AWS deployments from self-hosted GitLab CI with OIDC">
    <img src="/images/diagrams/gitlab-oidc-trust.svg" alt="A GitLab CI job exchanging a signed OIDC token for a temporary IAM role session" loading="lazy">
  </a>
  <figcaption>The pipeline stores a role ARN, not a credential. GitLab signs a token per job and IAM decides whether to trust it.</figcaption>
</figure>

<div hidden aria-hidden="true">

![A GitLab CI job exchanging a signed OIDC token for a temporary IAM role session](/images/diagrams/gitlab-oidc-trust.png)

</div>

### How Amazon EFS shortened my development loop while building a Raft datastore

[Read the post](3.3-Blog3/)

This article explains why the RaftDB sidecar keeps its write-ahead log and snapshots on an Amazon EFS access point rather than on storage that belongs to the task, and what that changed day to day: a Fargate deployment stopped wiping the canvas and became a recovery exercise instead. It records why EBS, Amazon S3 and task-scoped ephemeral volumes were each rejected, and how the access point does the identity work so uid/gid `10001` lands in a directory it already owns. It also states the cost of the design plainly: because one writer owns the write-ahead log, the service deploys with `minHealthyPercent: 0`, so every deploy takes the canvas offline for the whole window.

<figure>
  <a href="/3-blogsposted/3.3-blog3/" aria-label="Read How Amazon EFS shortened my development loop while building a Raft datastore">
    <img src="/images/diagrams/raftdb-efs-devloop.svg" alt="RaftDB write-ahead log and snapshots on an Amazon EFS access point shared across Fargate task replacements" loading="lazy">
  </a>
  <figcaption>Fargate replaces the task on every deploy. The write-ahead log outlives it.</figcaption>
</figure>

<div hidden aria-hidden="true">

![RaftDB write-ahead log and snapshots on an Amazon EFS access point shared across Fargate task replacements](/images/diagrams/raftdb-efs-devloop.png)

</div>
