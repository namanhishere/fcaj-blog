---
title: "CI/CD Pipeline Validation"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 5.7.3. </b> "
---

The awsplace project operates dual CI/CD pipelines: **GitHub Actions** (.github/workflows/deploy.yml) and **GitLab CI** (.gitlab-ci.yml). Both pipelines serve as automated gatekeepers — no code reaches production without passing every validation stage.

#### Pipeline overview

The GitHub Actions workflow is named **"Test & Deploy"** and is triggered on:
- Push to **main** — runs all tests AND deploys
- Pull requests to **main** — runs all tests only (no deployment)
- Tag pushes — runs all tests AND deploys

```yaml
on:
  push:
    branches: [main]
    tags: ['*']
  pull_request:
    branches: [main]
```

---

#### Deployment Gate Architecture

The deployment job (deploy) has a strict **needs** dependency chain — it only runs after ALL test jobs succeed:

```yaml
deploy:
  needs:
    [test-lambda, test-go-unit, test-go-postgres, test-go-ministack, test-cdk, publish-raftdb-image]
  if: github.ref == 'refs/heads/main'
```

This means a failure in any of the 6 prerequisite jobs will block deployment entirely.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion: Go to the GitHub Actions tab and open a workflow run.
Capture the visual dependency graph showing how the deploy job depends on all test jobs.
Save as: static/images/5.6/deployment-gate.png
-->

---

#### Pre-Deployment Validation Steps

Before running cdk deploy, the pipeline executes critical validation scripts:

#### 1. Environment Variable Validation

```bash
bash scripts/validate-deploy-env.sh
```

This script (tested by deploy-config.test.cjs) ensures:
- All required secrets are present and non-empty
- No unresolved GitLab variable references leaked into the environment
- Secret values are not accidentally printed to logs

#### 2. CloudFormation Stack Preparation

```bash
bash scripts/prepare-cloudformation-deploy.sh AwsplaceStack
```

This script handles stuck CloudFormation stacks:
- **CREATE_COMPLETE** or **UPDATE_COMPLETE** → proceed normally
- **ROLLBACK_FAILED** → auto-delete the failed stack and allow fresh creation
- **UPDATE_ROLLBACK_FAILED** → refuse to auto-delete (manual intervention required)

#### 3. WebSocket Origin Verification

```bash
bash scripts/check-websocket-origin.mjs
```

Both GitHub and GitLab pipelines verify that the WebSocket origin URL matches the deployment domain, preventing CORS/origin mismatch issues.

---

#### CDK Deployment

Once all validations pass, the actual deployment happens:

```yaml
- name: CDK deploy
  env:
    SESSION_SECRET: ${{ secrets.SESSION_SECRET }}
    DISCORD_CLIENT_ID: ${{ secrets.DISCORD_CLIENT_ID }}
    HOSTED_ZONE_ID: ${{ secrets.HOSTED_ZONE_ID }}
    DOMAIN_NAME: ${{ secrets.DOMAIN_NAME }}
    ECS_IMAGE_TAG: ${{ github.sha }}
    RAFTDB_IMAGE_DIGEST: ${{ needs.publish-raftdb-image.outputs.digest }}
  run: |
    bash scripts/validate-deploy-env.sh
    bash scripts/prepare-cloudformation-deploy.sh AwsplaceStack
    cd cdk
    npm ci && npm run build
    npx cdk deploy --require-approval never --no-strict --all --import-existing-resources
```

Key flags:
- **--require-approval never** — skips manual confirmation (CI is automated)
- **--import-existing-resources** — safely handles resources that already exist outside CDK
- **--all** — deploys all stacks (AwsplaceStack + RaftDbStagingStack if enabled)

---

#### Post-Deployment Validation

After CDK deploys the infrastructure, the pipeline:

1. Pushes the Docker image to ECR using **scripts/push-ecs-image.sh**
2. Deploys frontend to Amplify via asset upload
3. Waits for ECS service stability using **aws ecs wait services-stable**
4. Verifies the frontend build derives correct API and WebSocket endpoints from the domain

---

#### RaftDB Image Chain of Custody

The RaftDB image follows a rigorous chain of custody:

1. **Build** — docker build creates the image (no cloud credentials)
2. **Test** — 4 contract tests validate the image behavior
3. **Scan** — Trivy scans for HIGH/CRITICAL vulnerabilities
4. **Export evidence** — Image ID and scan results are saved as artifacts
5. **Publish** — After scan passes, push to ECR with immutable tag
6. **Verify** — After ECR push, pull back the published image and re-run contract tests to confirm integrity
7. **Record** — Publication evidence is uploaded with 90-day retention

```yaml
# Re-verify after ECR publication
- name: Pull digest into a clean local image cache
  run: |
    docker pull "${ECR_URI}@${IMAGE_DIGEST}"
    bash raftdb/test/container_contract_test.sh "${ECR_URI}@${IMAGE_DIGEST}"
    bash raftdb/test/migration_runtime_contract_test.sh "${ECR_URI}@${IMAGE_DIGEST}"
```

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion 1: Open a successful "Test & Deploy" workflow run in GitHub Actions.
Expand the "deploy" job and capture the steps showing validate, prepare, and CDK deploy.
Save as: static/images/5.6/deploy-steps.png

Screenshot suggestion 2: Open the "raftdb-image" job and capture the chain of steps:
Build → Contract tests → Trivy scan → Export evidence
Save as: static/images/5.6/raftdb-image-chain.png
-->

---

#### GitLab CI Integration

The **.gitlab-ci.yml** file (26,685 bytes) mirrors the GitHub Actions workflow with equivalent validation stages. The deployment contract tests (deployment-contract.test.cjs) explicitly verify that both pipelines contain the same critical commands:

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

This "test-the-test" approach ensures the two CI systems never drift apart.
