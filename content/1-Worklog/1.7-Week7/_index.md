---
title: "Week 7 Worklog"
date: 2026-07-27
weight: 7
chapter: false
pre: " <b> 1.7. </b> "
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
---

### Week 7 Objectives:

* Move the whole build, test and deploy sequence into the self-hosted GitLab instance as one pipeline instead of a set of commands I run by hand.
* Remove the long-lived AWS access key from CI entirely and replace it with a short-lived session obtained from an OIDC token GitLab mints per job.
* Make the RaftDB image the thing that gets promoted, not a tag that points at whatever was pushed last: build it and scan it in a job with no AWS credentials, then let a second job publish it only after proving it is the same image.

### Tasks to be carried out this week:

| Day | Task | Start Date | Completion Date | Reference Material |
| --- | ---- | ---------- | --------------- | ------------------ |
| 2   | - Lay out the pipeline as four stages: build-ci-image, test, build, deploy <br> - Build the shared runner image in the first stage so every later job starts from one toolchain instead of installing tools per job <br> - **Write Dockerfile.ci-utils on node:24-bookworm with the tools the pipeline actually calls:** <br>&emsp; + Go, pinned to go1.25.0 <br>&emsp; + AWS CLI v2, aws-cdk, docker, git, jq, zip, unzip, curl <br> - Tag the result ci-utils with the commit SHA and with main, and have later jobs pull the main tag | 27/07/2026 | 27/07/2026 | <https://docs.gitlab.com/ee/ci/yaml/> <br> <https://docs.gitlab.com/ee/ci/docker/using_docker_build.html> |
| 3   | - Register the GitLab instance as an IAM OIDC identity provider and write the trust policy conditions on issuer and subject <br> - Declare id_tokens in each job that needs AWS, one variable AWS_JWT_TOKEN with aud set to https://git.namanhishere.com <br> - Exchange the token with aws sts assume-role-with-web-identity and split the result into the three standard credential variables <br> - Keep the session at 3600 seconds and confirm no AWS access key or secret exists as a CI variable anywhere | 28/07/2026 | 28/07/2026 | <https://docs.gitlab.com/ee/ci/cloud_services/aws/> <br> <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html> <br> <https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html> |
| 4   | - Write the raftdb-image job in the test stage and give it no AWS credentials at all, only DOCKER_HOST and DOCKER_TLS_CERTDIR <br> - Build the image and run the four contract tests against it: <br>&emsp; + raftdb/test/container_contract_test.sh <br>&emsp; + raftdb/test/qualification_runtime_contract_test.sh <br>&emsp; + raftdb/test/migration_runtime_contract_test.sh <br>&emsp; + raftdb/test/s3_runtime_contract_test.sh <br> - Install Trivy 0.72.0 by verifying its checksums file against a hardcoded sha256, then verifying the archive against that file | 29/07/2026 | 29/07/2026 | <https://github.com/aquasecurity/trivy> <br> <https://docs.gitlab.com/ee/ci/docker/using_docker_build.html> |
| 5   | - Scan for HIGH and CRITICAL with trivy image and let Trivy exit 0, so the pass or fail decision is mine and is made in jq <br> - **Set the two gates apart deliberately:** <br>&emsp; + any CRITICAL fails the job, with no override <br>&emsp; + any HIGH fails the job unless RAFTDB_ACCEPT_HIGH_CVES equals the exact commit SHA <br> - Record the docker image ID before and after the scan and fail if it changed <br> - Hand the image forward as a gzipped tar plus raftdb-image-evidence.json carrying the commit, the image ID and the scan counts | 30/07/2026 | 30/07/2026 | <https://github.com/aquasecurity/trivy> <br> <https://jqlang.github.io/jq/manual/> |
| 6   | - Write publish-raftdb-image so every check happens before the first credential is requested: evidence commit must equal the pipeline commit, and the loaded image ID must equal the recorded one <br> - Push the immutable tag raftdb- plus the commit SHA, then read the digest back and require it to match sha256 followed by 64 lowercase hex characters <br> - Delete every local copy, pull the image back by digest, and re-run the container and migration contract tests on the pulled bytes <br> - Publish the digest to the deploy job with reports dotenv, and have deploy-to-aws cross-check it against the evidence file before assuming its role | 31/07/2026 | 31/07/2026 | <https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html> <br> <https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-pull-ecr-image.html> <br> <https://docs.gitlab.com/ee/ci/yaml/artifacts_reports.html> |

The part that removes the static key is short. Each credentialed job asks GitLab for a signed token, and the audience is the GitLab instance itself:

```yaml
# awsplace/.gitlab-ci.yml
id_tokens:
  AWS_JWT_TOKEN:
    aud: https://git.namanhishere.com
```

The token is then exchanged for a session that expires within the hour:

```bash
CREDS=$(aws sts assume-role-with-web-identity \
  --role-arn "$AWS_ROLE_ARN" \
  --role-session-name "GitLabCI-${CI_PIPELINE_ID}" \
  --web-identity-token "$AWS_JWT_TOKEN" \
  --duration-seconds 3600 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
```

### Week 7 Achievements:

* The pipeline is four stages and thirteen jobs, and the stage order is the argument: `build-ci-image` produces one runner image, `test` runs the Lambda, Go, CDK and RaftDB image checks, `build` pushes artifacts to ECR, and `deploy` is the only stage that touches the account. Nothing in `test` can reach AWS, which is what makes the next point possible.

* No AWS access key exists in the CI configuration. Three jobs need credentials, `push-ecr`, `publish-raftdb-image` and `deploy-to-aws`, and all three declare the same `id_tokens` block with `aud: https://git.namanhishere.com`, so the audience and the issuer are the same self-hosted GitLab. Each job exchanges that token through `sts assume-role-with-web-identity` for a session capped at 3600 seconds. A leaked job log costs an hour, not a rotation.

* The chain of custody is the week's real result. `raftdb-image` builds the image, runs the four contract tests, scans it, and holds no AWS credential, so it cannot publish anything even if it wanted to. It hands the image over as a gzipped tar with `raftdb-image-evidence.json` recording the commit, the docker image ID and the scan counts. `publish-raftdb-image` then re-checks the commit, loads the tar, re-checks the image ID against the evidence, and only then asks for credentials. The tag it pushes is `raftdb-<commit sha>`, and `scripts/ensure-ecr-repository.sh` sets `MUTABLE_WITH_EXCLUSION` with the wildcard filter `raftdb-*`, so exactly those tags cannot be overwritten while the ordinary application tags stay mutable.

* Two details of the scan gate were worth arguing over with myself. `trivy image` runs with `--exit-code 0`, which looks wrong until you see that the decision is then made in `jq`: a CRITICAL finding always fails the job, and a HIGH finding fails it unless `RAFTDB_ACCEPT_HIGH_CVES` equals the exact commit SHA. Pinning the override to a SHA rather than accepting `true` means an acceptance cannot silently carry forward to the next commit. The other detail is the pinned checksum: the hardcoded `sha256` covers the Trivy **checksums file**, and the archive is then verified against that file, so the trust anchor is one hash rather than one per artifact.

* The digest, not the tag, is what reaches the deploy. After pushing, the job reads the digest back, requires it to match `^sha256:[0-9a-f]{64}$`, removes every local copy of the image, pulls it again **by digest**, and re-runs the container and migration contract tests against the bytes that came out of ECR. It then publishes the digest through `reports: dotenv`, and `deploy-to-aws` cross-checks that value against `raftdb-publish-evidence.json` and runs `scripts/validate-deploy-env.sh` over its nine required variables before it authenticates. Verification first, credentials second, in both jobs.

* Three things are honestly weaker than the rest, and I would fix them before calling this finished. `Dockerfile.ci-utils` pins Go exactly to `go1.25.0` but installs the AWS CLI from a moving download URL and `aws-cdk` through an unpinned global `npm install`, so the runner image is not reproducible. The pipeline declares no GitLab `environment:` blocks at all, which means the role ARN comes from unscoped project variables and there is no environment-level protection on the deploy. And `test-raftdb-sanitizers` is commented out while still being listed as an `optional: true` dependency of the deploy job, so it is valid configuration that quietly contributes nothing; the sanitizer coverage it names lives in a separate workflow file rather than here.
