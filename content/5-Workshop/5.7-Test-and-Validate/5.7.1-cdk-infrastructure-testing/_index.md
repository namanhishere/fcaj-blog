---
title: "CDK Infrastructure Testing"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 5.7.1. </b> "
---

The awsplace CDK codebase contains **7 test files** inside the **cdk/** directory, all using Jest as the test runner. These tests do not mock CDK constructs. Instead, they invoke **cdk synth** to produce real CloudFormation templates and then parse the JSON output to validate infrastructure correctness.

#### Test files overview

| Test File | Purpose | Key Assertions |
|---|---|---|
| deployment-contract.test.cjs | Validates the deployment contract between CDK and CI/CD pipelines | ECR repository name, ECS image tag, circuit breaker config, CloudFormation exports |
| deploy-config.test.cjs | Tests the validate-deploy-env.sh and prepare-cloudformation-deploy.sh helper scripts | Environment variable validation, stack state handling |
| raftdb.test.cjs | Comprehensive RaftDB staging stack validation  | VPC isolation, ECS task definitions, security groups, EFS encryption, S3 snapshot config |
| raftdb-workflow.test.cjs | Tests CI/CD workflow files against RaftDB requirements | Docker build steps, image scanning, qualification tests |
| raftdb-runbook.test.cjs | Validates operational runbook documentation against code | Runbook commands match actual infrastructure |
| raftdb-application-modes.test.cjs | Tests application mode state machine documentation | DATA_MODE transitions, retry contracts, protocol documentation |
| amplify.test.cjs | Validates frontend hosting uses Amplify (not CloudFront) | Amplify App/Branch/Domain resources exist, no CloudFront resources |

---

#### 1. Deployment Contract Testing

File: **deployment-contract.test.cjs** 

This is the most critical test file. It validates a shared contract between the CDK infrastructure code and the CI/CD pipelines. Both GitHub Actions and GitLab CI depend on specific CloudFormation outputs and resource properties. If the CDK code changes these, the deployment will break. This test catches such breaking changes.

Key test cases:

#### a) ECR Repository Stability

```javascript
test('application ECR repository has a stable retained physical name', () => {
  const repositories = resourcesByType(defaultTemplate, 'AWS::ECR::Repository');
  expect(repositories).toHaveLength(1);
  expect(repository.Properties).toEqual(expect.objectContaining({
    RepositoryName: 'awsplace-ecs',
    ImageScanningConfiguration: { ScanOnPush: true },
    ImageTagMutability: 'MUTABLE_WITH_EXCLUSION',
  }));
  expect(repository.DeletionPolicy).toBe('Retain');
});
```

This test ensures:
- There is exactly **one** ECR repository named **awsplace-ecs**.
- The repository has **ScanOnPush** enabled for security compliance.
- The DeletionPolicy is **Retain** — preventing accidental deletion of production images.
- Image tags prefixed with **raftdb-*** are immutable and cannot be overwritten.

#### b) ECS Deployment Configuration

```javascript
test('ECS uses the requested image tag and exports exact deployment targets', () => {
  // ... synthesize with ECS_IMAGE_TAG=0123456789abcdef...
  expect(services[0][1].Properties.DeploymentConfiguration).toEqual(
    expect.objectContaining({
      DeploymentCircuitBreaker: { Enable: true, Rollback: true },
      MinimumHealthyPercent: 0,
      MaximumPercent: 100,
    })
  );
  expect(template.Outputs.EcsClusterName).toBeDefined();
  expect(template.Outputs.EcsServiceName).toBeDefined();
});
```

This validates:
- The ECS service uses a **deployment circuit breaker** with automatic rollback.
- CloudFormation exports the cluster and service name (CI/CD scripts depend on these for **aws ecs wait services-stable**).

#### c) Invalid Input Rejection

```javascript
test('invalid ECS image tags fail synthesis before deployment', () => {
  const { result } = synthWithImageTag('invalid/tag');
  expect(result.status).not.toBe(0);
  expect(`${result.stdout}\n${result.stderr}`).toContain(
    'ECS_IMAGE_TAG must be a valid Docker image tag'
  );
});
```

This "negative test" ensures the CDK code fails fast with a clear error if the image tag format is incorrect, preventing invalid deployments.

#### d) Frontend-Backend CORS Contract

```javascript
test('ECS allows the browser origin derived from the deployed frontend domain', () => {
  // Synth with DOMAIN_NAME=canvas.example.com
  expect(environment.ALLOWED_ORIGINS).toBe('https://canvas.example.com');
});
```

This ensures the backend's **ALLOWED_ORIGINS** environment variable automatically matches the frontend domain, so CORS does not break in production.

#### e) CI/CD Script Contract

```javascript
test('GitLab and GitHub publish and deploy through the shared ECR contract', () => {
  for (const workflow of [gitlab, github]) {
    expect(workflow).toContain('scripts/push-ecs-image.sh');
    expect(workflow).toContain('ECS_IMAGE_TAG');
    expect(workflow).toContain('aws ecs wait services-stable');
    expect(workflow).toContain('--import-existing-resources');
  }
});
```

This reads the actual **.gitlab-ci.yml** and **deploy.yml** files and asserts they use the same deployment scripts and patterns. This prevents one CI system from drifting out of sync.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion: Run npm test inside the awsplace/cdk folder.
Capture the Jest output showing all 7 test files passing with green checkmarks.
Save as: static/images/5.6/cdk-test-results.png
-->

---

#### 2. Deploy Configuration Testing

File: **deploy-config.test.cjs** 

This file tests the deployment helper scripts in the **scripts/** directory — specifically **validate-deploy-env.sh** and **prepare-cloudformation-deploy.sh**.

Key scenarios tested:

| Test Case | What It Validates |
|---|---|
| Accepts resolved configuration | All required env vars (HOSTED_ZONE_ID, DOMAIN_NAME, SESSION_SECRET, etc.) are present |
| Rejects unresolved GitLab variables | Catches literal values that GitLab failed to interpolate |
| Rejects missing secrets | Fails if DISCORD_CLIENT_SECRET is empty |
| Stack preparer: healthy stack | Leaves a CREATE_COMPLETE stack unchanged |
| Stack preparer: rollback failed | Deletes a ROLLBACK_FAILED stack and waits for cleanup |
| Stack preparer: new stack | Allows creation when stack does not exist |
| Stack preparer: update failed | Refuses to auto-delete UPDATE_ROLLBACK_FAILED (requires manual intervention) |

The deploy-config tests use mock AWS CLI scripts to simulate CloudFormation stack states without requiring real AWS credentials.

---

#### 3. RaftDB Infrastructure Validation

File: **raftdb.test.cjs** 

This is the largest test file. It validates the entire **RaftDbStagingStack** — a separate CDK stack used exclusively for rehearsing Raft consensus operations on throwaway infrastructure.

The test synthesizes templates with multiple configurations:
- Default (RaftDB disabled)
- Enabled (ENABLE_RAFTDB=true, RAFTDB_NODE_COUNT=3)
- Restore mode (RAFTDB_RESTORE_FROM_S3=true)
- Post-restore mode (RAFTDB_RESTORE_FROM_S3=false, with a data generation label)

Key areas validated include VPC isolation (separate VPC from production), 3-member ECS task definitions, security group rules, EFS encrypted volumes, and S3 snapshot configuration.

---

#### 4. Amplify Frontend Hosting

File: **amplify.test.cjs** 

A concise but important test that validates the architectural decision to host the frontend on AWS Amplify instead of CloudFront:

```javascript
test('the application stack hosts the frontend on Amplify, not CloudFront', () => {
  expect(resourcesByType(defaultTemplate, 'AWS::CloudFront::Distribution')).toHaveLength(0);
  expect(resourcesByType(defaultTemplate, 'AWS::Amplify::App').length).toBeGreaterThanOrEqual(1);
  expect(resourcesByType(defaultTemplate, 'AWS::Amplify::Branch').length).toBeGreaterThanOrEqual(1);
});
```

---

#### Running CDK tests locally

```bash
cd awsplace/cdk
npm install
npm test
```

The **npm test** script performs three steps sequentially:
1. **npm run build** — Compiles TypeScript to JavaScript via tsc
2. **npm run synth** — Runs cdk synth to generate CloudFormation templates
3. **jest --runInBand** — Executes all 7 test files serially

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion: Run npm test inside awsplace/cdk and capture the terminal output showing:
1. The TypeScript compilation
2. The CDK synth output
3. The Jest test results (all passing)
Save as: static/images/5.6/npm-test-output.png
-->
