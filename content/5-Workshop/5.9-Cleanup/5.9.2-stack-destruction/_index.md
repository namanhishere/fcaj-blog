---
title: "Stack Destruction Procedures"
date: 2024-01-01
weight: 2
chapter: false
pre: " <b> 5.9.2. </b> "
---

Stack destruction in awsplace follows documented, tested procedures. The project distinguishes between three destruction contexts: staging stack teardown (safe, routine), application stack teardown (handles retained resources), and pre-deployment stuck-stack cleanup (automated by CI/CD scripts). Each is covered below.

---

#### 1. Staging Stack Destruction

Source: **docs/raftdb/staging-runbook.md** — §Destroy staging

The RaftDB staging stack is designed to be created and destroyed repeatedly for qualification drills. The runbook provides an exact procedure:

```bash
export ENABLE_RAFTDB=true
export RAFTDB_RESTORE_FROM_S3=false
npx cdk destroy RaftDbStagingStack --force
```

Critical points from the procedure:

- **ENABLE_RAFTDB** must remain **true** and **RAFTDB_RESTORE_FROM_S3** must be **false** — otherwise the conditional stack will not exist in the CDK application and the destroy command will fail.
- The **--force** flag skips the interactive confirmation prompt, making the command suitable for scripting but dangerous for production — it is only used for the staging stack.
- After destruction, verify that **AwsplaceStack** and its ECR repository remain untouched. The staging stack imports only the shared repository name from the application stack; destroying it must not cascade.

The runbook explicitly warns that the encrypted EFS filesystem and versioned S3 bucket are retained after cdk destroy due to their **RETAIN** policy. These retained resources require the separate cleanup procedure detailed in section 5.9.3.

---

#### 2. Application Stack Destruction

The application stack (**AwsplaceStack**) destruction requires more care because it contains the ECR repository, Secrets Manager secret, and imported S3 buckets. The CDK code in infrastructure code documents the workflow:

```typescript
// CI publishes before the application stack is recreated, so the registry
// must survive `cdk destroy` and be auto-imported on the next deployment.
repository.applyRemovalPolicy(RemovalPolicy.RETAIN);
```

The deployment uses **--import-existing-resources** to handle retained resources on recreation:

```yaml
- name: CDK deploy
  run: |
    cd cdk
    npm ci && npm run build
    npx cdk deploy --require-approval never --no-strict --all --import-existing-resources
```

The **--import-existing-resources** flag tells CDK to search for existing resources with matching physical names (like the ECR repository **awsplace-ecs**) and adopt them into the new stack rather than attempting to create duplicates. This is validated by the test **GitLab and GitHub publish and deploy through the shared ECR contract** in **deployment-contract.test.cjs**.

For a full application stack teardown:

1. Destroy the stack normally: **npx cdk destroy AwsplaceStack**
2. Verify retained resources: the ECR repository, Secrets Manager secret, and imported S3 buckets survive.
3. If re-creating, re-deploy with **--import-existing-resources** to re-adopt retained resources.

---

#### 3. Pre-Deployment Stuck-Stack Cleanup

File: **scripts/prepare-cloudformation-deploy.sh**

Before every deployment, the CI/CD pipeline runs this script to handle CloudFormation stacks that are stuck in a failed state. The script is tested by **deploy-config.test.cjs** with 7 distinct test scenarios.

The script's decision matrix:

| Stack State | Action | Rationale |
|---|---|---|
| **CREATE_COMPLETE**, **UPDATE_COMPLETE** | Proceed normally | Stack is healthy; CDK can update in place |
| **CREATE_FAILED**, **ROLLBACK_COMPLETE**, **ROLLBACK_FAILED**, **DELETE_FAILED** | Delete the stack automatically | No successful deployment to preserve; deleting lets CDK recreate from scratch |
| **DELETE_IN_PROGRESS** | Wait for deletion to finish | Another process is already cleaning up; wait rather than conflict |
| **UPDATE_ROLLBACK_FAILED** | **Refuse to delete** | A prior stable deployment exists; automatic deletion would destroy production infrastructure |
| ***_IN_PROGRESS** | Refuse and exit | A CloudFormation operation is already running; concurrent operations cause conflicts |

The **UPDATE_ROLLBACK_FAILED** state is the safety-critical case. The script refuses to auto-delete because this state means a stable deployment exists but a subsequent update failed. Automatic deletion in this state would destroy production infrastructure. Manual intervention is required.

The deletion logic includes a retry mechanism for **DELETE_FAILED** states:

```bash
delete_incomplete_stack() {
  for attempt in 1 2; do
    echo "Deleting incomplete CloudFormation stack $stack_name (attempt $attempt/2)"
    aws cloudformation delete-stack --stack-name "$stack_name" "${region_args[@]}"

    if aws cloudformation wait stack-delete-complete \
      --stack-name "$stack_name" "${region_args[@]}"; then
      echo "Incomplete CloudFormation stack $stack_name was deleted"
      return 0
    fi

    current_status="$(describe_stack_status 2>/dev/null || true)"
    if [[ "$current_status" != "DELETE_FAILED" ]]; then
      echo "ERROR: deletion of $stack_name stopped in unexpected state: ${current_status:-unknown}" >&2
      return 1
    fi
  done

  echo "ERROR: $stack_name is still DELETE_FAILED after two attempts" >&2
  return 1
}
```

The Jest tests for this script cover every code path:

| Test Case | Stack State | Expected Behavior |
|---|---|---|
| Healthy stack | CREATE_COMPLETE | Leaves stack unchanged |
| Failed initial creation | ROLLBACK_FAILED | Deletes stack and waits for cleanup |
| New stack | Does not exist | Allows creation |
| Failed update with prior stable state | UPDATE_ROLLBACK_FAILED | Refuses to delete automatically |

---

#### 4. CI/CD Artifact Lifecycle

CI/CD artifacts (test logs, scan reports, publication evidence) are managed separately from CloudFormation resources:

| Artifact | Retention Period | Cleanup Mechanism |
|---|---|---|
| GitHub Actions run logs | 90 days (default) | Automatic GitHub expiration |
| RaftDB image publication evidence | 90 days (explicit) | Workflow artifact with retention-days: 90 |
| Trivy vulnerability scan reports | 90 days (explicit) | Workflow artifact with retention-days: 90 |
| ECR images beyond count 10 | Automatic | Lifecycle rule |
| S3 non-current snapshot versions | 35 days | Lifecycle rule |

The 90-day artifact retention aligns with the RaftDB chain-of-custody requirement: publication evidence must be available for audit during the full rollback window (7 days after read cutover) plus a generous margin.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion 1: Run cdk destroy RaftDbStagingStack --force in a terminal.
Capture the output showing CloudFormation resources being deleted and the final confirmation.
Save as: static/images/5.8/cdk-destroy-staging.png

Screenshot suggestion 2: Open the CloudFormation console during a stuck-stack scenario (ROLLBACK_FAILED).
Capture the stack events showing the failure and then the successful deletion triggered by prepare-cloudformation-deploy.sh.
Save as: static/images/5.8/stuck-stack-cleanup.png
-->
