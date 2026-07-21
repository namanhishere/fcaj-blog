---
title: "Blogs Posted"
linkPreviewLabel: "Blog Post"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 3. </b> "
includeInReport: false
---

This is where I write up the technical problems I run into while building and testing systems—including what I tried, why I chose it, and what I would still improve.

### [Scaling GitLab Runner to zero with EC2 Auto Scaling](3.1-Blog1/)

This article explains how I combined GitLab Runner's Docker Autoscaler, the Fleeting AWS plugin, Terraform, Packer, and an EC2 Auto Scaling Group to create one temporary worker per job and scale the worker fleet back to zero when the queue is empty.

<figure>
  <a href="/3-blogsposted/3.1-blog1/" aria-label="Read Scaling GitLab Runner to zero with EC2 Auto Scaling">
    <img src="/images/diagrams/gitlab-runner-ec2-autoscale.svg" alt="GitLab Runner architecture using an EC2 Auto Scaling Group and ephemeral workers" loading="lazy">
  </a>
  <figcaption>Build the worker image once, launch isolated EC2 workers on demand, and return capacity to zero after the jobs finish.</figcaption>
</figure>
