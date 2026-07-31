---
title: "Cleanup"
date: 2024-01-01
weight: 8
chapter: false
pre: " <b> 5.9. </b> "
---

In the awsplace project, we treat cleanup as a priority, not an afterthought. We've assigned a strict **RemovalPolicy** to every CDK resource, documented our stack deletion process, and made sure that cleaning up retained data requires explicit manual approval. This section covers how we manage our resources from the moment they are created until they are safely destroyed.

Here's how we organize our cleanup process:

| Sub-section | Description |
|---|---|
| [5.9.1 Resource Removal Policy Design](5.9.1-removal-policy-design/) | How we decide whether to RETAIN or DESTROY resources like ECR, EFS, S3, and Secrets Manager |
| [5.9.2 Stack Destruction Procedures](5.9.2-stack-destruction/) | Step-by-step guides for tearing down staging and production stacks, plus tips for CI/CD cleanup |
| [5.9.3 Retained Data Cleanup](5.9.3-retained-data-cleanup/) | The manual steps we use to safely delete retained data, old S3 versions, and leftover EFS files |

#### Cleanup Philosophy

When it comes to cleaning up, our main rule is to **separate destroying the stack from deleting the data**:

1. **Stack deletion removes the running app**: Running **cdk destroy** takes down the compute resources—like our ECS services, load balancers, and security groups.
2. **Data destruction is manual**: Actually deleting the data is a separate, manual process that requires written approval and specific commands. It will never happen automatically just because you deleted a stack.
3. **Keep the important stuff**: We tell CDK to retain our critical resources (like our ECR repo, RaftDB snapshots, EFS files, and secrets). They stick around even if the stack is deleted, because we need them to persist across deployments.

This separation gives us peace of mind. If we ever need to tear down and recreate our stack, we know we won't accidentally wipe out our production images, database snapshots, or app secrets.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion: A diagram showing the cleanup decision flow of the awsplace project:
- Stack Deletion (cdk destroy) → removes compute, network, and security resources
- Retained Resources (RETAIN policy) → survive stack deletion
- Manual Data Destruction (runbook procedure) → requires written approval
Save as: static/images/5.8/cleanup-decision-flow.png
-->
