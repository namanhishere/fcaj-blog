---
title: "Test & Validate"
date: 2024-01-01
weight: 6
chapter: false
pre: " <b> 5.7. </b> "
---

We believe testing is the backbone of the awsplace project. Instead of just hoping things work, we check our code at multiple levels—starting from small unit tests, up to testing our CDK infrastructure, and finally running everything through our CI/CD pipelines.

Here's a look at how we organized our tests:

| Sub-section | Description |
|---|---|
| [5.7.1 CDK Infrastructure Testing](5.7.1-cdk-infrastructure-testing/) | We use Jest to generate real CloudFormation templates and make sure our infrastructure matches what we expect |
| [5.7.2 Application Testing](5.7.2-application-testing/) | Unit tests for our Go code, plus integration tests for PostgreSQL and our DynamoDB/S3 setup |
| [5.7.3 CI/CD Pipeline Validation](5.7.3-ci-cd-pipeline-validation/) | Our GitHub Actions and GitLab CI workflows that automatically check every deployment |

#### Testing Philosophy

When it comes to testing, our core rule is to **test the contract, not the implementation**. Instead of writing mock tests for every little CDK resource, we take a more practical approach:

1. **Synthesize real templates**: First, we run **cdk synth** to generate the actual CloudFormation templates, just like they would appear in a real environment.
2. **Check the final output**: Then, we scan the generated JSON to make sure all our important resources, exports, and configurations are exactly where they should be.
3. **Verify our deployment scripts**: Finally, we validate our deployment scripts by checking them against the real shell scripts used in our CI/CD pipelines.

By testing the real output, we catch actual deployment bugs that simple mocking would completely miss.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion: A diagram showing the testing pyramid of the awsplace project:
- Top: CI/CD Pipeline (GitHub Actions / GitLab CI)
- Middle: CDK Contract Tests (Jest)
- Bottom: Application Tests (Go unit + integration)
Save as: static/images/5.6/testing-pyramid.png
-->
