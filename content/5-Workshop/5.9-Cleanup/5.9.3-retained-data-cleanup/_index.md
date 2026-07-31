---
title: "Retained Data Cleanup"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 5.9.3. </b> "
---

When a stack is destroyed with **RETAIN** policies, the CloudFormation resources are removed from the stack but the underlying AWS resources — S3 buckets, EFS filesystems, Secrets Manager secrets, ECR repositories — persist. The awsplace project treats cleanup of these retained resources as a separate, manual, approval-gated operation. The staging runbook (**docs/raftdb/staging-runbook.md**) defines the authoritative procedure.

---

#### 1. Why Retained Cleanup Is Separate

The separation between stack destruction and data destruction exists for three reasons:

1. **Safety**: A routine **cdk destroy** during qualification drills or development should never cascade into permanent data loss. The retained resources act as a safety net.
2. **Auditability**: Retained data cleanup requires written data-destruction approval and a retention review. This creates an explicit paper trail for compliance.
3. **Deliberateness**: Making cleanup manual and approval-gated prevents "fat-finger" accidents. No script can accidentally run the cleanup — a human must verify identifiers, obtain approval, and execute each step.

The staging runbook summarizes this concisely:

> Cleanup is a separate destructive operation requiring written data-destruction approval and a retention review. Match the recorded filesystem and bucket IDs; never use account-wide name matching. This runbook deliberately provides no blanket cleanup command.

---

#### 2. Staging Retained Resources Cleanup

Source: **docs/raftdb/staging-runbook.md** — §Retained data cleanup

After destroying **RaftDbStagingStack**, the following resources survive and must be cleaned up manually:

| Resource | Retention Behavior | Cleanup Complexity |
|---|---|---|
| RaftDB snapshot bucket (S3, versioned, KMS-managed encryption) | All object versions and delete markers persist | High — must empty every version and delete marker before bucket deletion |
| RaftDB EFS filesystem (encrypted) | Filesystem survives; mount targets may linger | Medium — must remove access points and mount targets before filesystem deletion |

#### Step-by-step cleanup procedure:

#### a) S3 Snapshot Bucket Cleanup

The staging snapshot bucket is **versioned** with **KMS_MANAGED** encryption. CloudFormation refuses to delete a non-empty bucket, and with versioning enabled, "emptying" requires deleting every object version and every delete marker.

```bash
# 1. Record the bucket name before destroying the stack
BUCKET=$(jq -r '.RaftDbStagingStack.RaftDbSnapshotBucketName' \
  cdk.out/raftdb-staging-outputs.json)

# 2. Verify the bucket identity — never match by name pattern
aws s3api list-object-versions --bucket "$BUCKET" --max-items 1

# 3. Empty all object versions (this is the destructive step)
aws s3api delete-objects --bucket "$BUCKET" \
  --delete "$(aws s3api list-object-versions \
    --bucket "$BUCKET" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json)"

# 4. Empty all delete markers
aws s3api delete-objects --bucket "$BUCKET" \
  --delete "$(aws s3api list-object-versions \
    --bucket "$BUCKET" \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json)"

# 5. Delete the bucket once empty
aws s3api delete-bucket --bucket "$BUCKET"
```

The lifecycle rule configured in infrastructure code (35-day noncurrent version expiration) provides automatic eventual cleanup for old versions, but the complete immediate cleanup above is the only way to fully remove the bucket on demand.

#### b) EFS Filesystem Cleanup

EFS cleanup requires a specific ordering: access points and mount targets must be removed before the filesystem itself can be deleted.

```bash
# 1. Record the filesystem ID before destroying the stack
FILESYSTEM=$(jq -r '.RaftDbStagingStack.RaftDbFileSystemId' \
  cdk.out/raftdb-staging-outputs.json)

# 2. List and delete all access points
aws efs describe-access-points --file-system-id "$FILESYSTEM" \
  --query 'AccessPoints[].AccessPointId' --output text | while read ap_id; do
  if [ -n "$ap_id" ]; then
    aws efs delete-access-point --access-point-id "$ap_id"
  fi
done

# 3. List and delete all mount targets
aws efs describe-mount-targets --file-system-id "$FILESYSTEM" \
  --query 'MountTargets[].MountTargetId' --output text | while read mt_id; do
  if [ -n "$mt_id" ]; then
    aws efs delete-mount-target --mount-target-id "$mt_id"
  fi
done

# 4. Wait for mount targets to finish deleting
aws efs describe-mount-targets --file-system-id "$FILESYSTEM" \
  --query 'length(MountTargets)' | while read count; do
  if [ "$count" -eq 0 ]; then break; fi
  sleep 10
done

# 5. Delete the filesystem
aws efs delete-file-system --file-system-id "$FILESYSTEM"
```

Mount targets exist in each Availability Zone where the filesystem was mounted. They must all be in the **deleted** state before the filesystem can be removed.

---

#### 3. Production Retained Resources

Production retained resources (ECR repository, Secrets Manager secret, imported S3 buckets) are typically **not** cleaned up. They are designed to persist indefinitely:

| Resource | Cleanup Requirement | Typical Action |
|---|---|---|
| ECR Repository (awsplace-ecs) | Only if the project is fully decommissioned | Delete after confirming no active deployments depend on its images |
| Secrets Manager secret | Only if the application is fully decommissioned | Schedule deletion with a recovery window (default 30 days) |
| Imported S3 buckets (canvas, exports) | Never via CDK | These are imported (not created) by the stack; they must be managed independently |

Because imported S3 buckets are created outside CDK (via **s3.Bucket.fromBucketName** in infrastructure code), CDK has no authority to delete them — they survive stack destruction automatically.

---

#### 4. ECR Repository Cleanup (Decommissioning)

If the entire project is decommissioned, the ECR repository requires manual deletion:

```bash
# 1. Verify no active ECS tasks reference images in this repository
aws ecs list-tasks --cluster <cluster-name> --desired-status RUNNING

# 2. Delete all images (required before repository deletion)
aws ecr batch-delete-image \
  --repository-name awsplace-ecs \
  --image-ids "$(aws ecr list-images \
    --repository-name awsplace-ecs \
    --query 'imageIds[*]' --output json)"

# 3. Delete the repository
aws ecr delete-repository --repository-name awsplace-ecs --force
```

The **--force** flag on delete-repository is required because the repository may still contain images even after batch-delete-image. The lifecycle rule (max 10 images) keeps the image count manageable for this operation.

---

#### 5. Cleanup Approval and Record-Keeping

The staging runbook mandates documentation of every cleanup operation:

- **Written data-destruction approval** before any cleanup command is executed.
- **Record every deleted identifier**: bucket name, filesystem ID, access point IDs, mount target IDs.
- **Retention review**: confirm that no qualification evidence or audit trail is still needed before proceeding.
- **Never use account-wide name matching**: always match resources by their exact recorded IDs to avoid accidentally deleting similarly-named resources in other stacks.

This approach aligns with the capacity runbook's requirement that the service owner must explicitly approve resource retirement in writing.

<!-- 📸 IMAGE GUIDELINE:
Screenshot suggestion 1: In the S3 console, open the RaftDB snapshot bucket after stack destruction.
Capture the bucket showing object versions still present despite the stack being destroyed.
Save as: static/images/5.8/retained-s3-bucket.png

Screenshot suggestion 2: In the EFS console, show the filesystem still existing after stack destruction.
Capture the filesystem detail showing the "Orphaned" or "Not managed by CloudFormation" indicator.
Save as: static/images/5.8/retained-efs-filesystem.png
-->
