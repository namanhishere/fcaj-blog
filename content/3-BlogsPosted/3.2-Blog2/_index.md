---
title: "Keyless AWS deployments from GitLab CI with OIDC"
date: 2026-07-24
weight: 2
chapter: false
pre: " <b> 3.2. </b> "
includeInReport: false
---

# The problem

My internship project, **awsplace**, lives on my own GitLab instance at `git.namanhishere.com`. That is the only git remote the repository has. Everything the pipeline does to AWS happens from there: it pushes container images to Amazon ECR, runs `npx cdk deploy` against `AwsplaceStack`, uploads a frontend bundle to Amplify Hosting, and forces a new ECS deployment.

The obvious way to make that work is to create an IAM user, generate an access key pair, and paste `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` into the project's CI/CD variables. It takes two minutes and it works on the first try. I did not want it, for reasons that are specific rather than theoretical.

A stored access key never expires on its own. Mine would have sat in the variable store of a GitLab instance I administer alone, on hardware in my apartment, with no key rotation process behind it. Every job in the pipeline would have inherited it, including the jobs that build a C++ datastore image and run four container contract tests against it, none of which has any business talking to AWS. And if the key ever leaked, through a `set -x` in the wrong place, a third-party CI plugin, or a compromised runner, the blast radius would be permanent until I noticed and revoked it manually.

So the pipeline holds no AWS key at all. The only AWS-related value stored in GitLab is `${AWS_ROLE_ARN}`, which is a role reference, not a credential. Knowing it grants nothing.

# How the trust is established

GitLab can act as an OpenID Connect identity provider. For any job that declares the `id_tokens` keyword, GitLab mints a short-lived JWT, signs it with its own key, and injects it into that job's environment. The token is never written into the repository and never persisted as an artifact.

On the AWS side there are two objects. The first is an IAM OIDC identity provider registered for the issuer URL `https://git.namanhishere.com`, which is what lets IAM fetch the JWKS document and verify the signature on a token my GitLab produced. The second is an IAM role whose trust policy names that provider as its principal and constrains which tokens may assume it.

The audience matters more than it looks. In `.gitlab-ci.yml` I set it explicitly:

```yaml
id_tokens:
  AWS_JWT_TOKEN:
    aud: https://git.namanhishere.com
```

All three credentialed jobs declare exactly that value, so `aud` and `iss` are the same string here. That is a deliberate choice and it has a cost worth naming: an audience equal to the issuer is a weaker binding than a per-consumer audience such as `sts.amazonaws.com`, because it does not distinguish "a token meant for AWS" from "a token meant for anything else that trusts my GitLab". Today AWS is the only OIDC relying party in the project, so the distinction is theoretical. If I add a second one, the audience has to be split first.

<figure>
  <img src="/images/3-BlogsPosted/3.2-Blog2/iam-oidc.png" alt="AWS IAM console showing the OpenID Connect identity provider git.namanhishere.com with a single registered audience" loading="lazy">
  <figcaption>The IAM identity provider for my GitLab instance, with exactly one audience registered. That single entry is the <code>aud</code> value all three credentialed jobs ask for; splitting it is the prerequisite for a second relying party.</figcaption>
</figure>

The trust policy is where the actual authorisation lives. It checks the audience for equality and the subject for a pattern, so a token minted for a different project or a different branch of the same project cannot assume the role even though it carries a valid signature:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/git.namanhishere.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "git.namanhishere.com:aud": "https://git.namanhishere.com"
        },
        "StringLike": {
          "git.namanhishere.com:sub": "project_path:namanhishere/awsplace:ref_type:branch:ref:main"
        }
      }
    }
  ]
}
```

The account ID is redacted throughout this post. The `sub` claim is the part that does real work: GitLab builds it from the project path, the ref type, and the ref name, and pinning it to `ref:main` is what stops a branch or a fork from minting itself a deployment credential. Signature validity alone is not authorisation.

<figure>
  <img src="/images/diagrams/gitlab-oidc-trust.svg" alt="Sequence diagram of a GitLab CI job exchanging a signed OIDC token for temporary AWS credentials through IAM and STS" loading="lazy">
  <figcaption>The full handshake, from the <code>id_tokens</code> declaration to a 3600 second STS session. Every step is annotated with its line in <code>.gitlab-ci.yml</code>.</figcaption>
</figure>

# The job configuration

The exchange itself is one `aws-cli` call. This is the `before_script` of the `push-ecr` job, which builds the Go application image and pushes it to ECR:

```yaml
before_script:
  - >
    ASSUME_ROLE_OUTPUT=$(aws sts assume-role-with-web-identity
    --role-arn ${AWS_ROLE_ARN}
    --role-session-name "GitLabCI-${CI_PIPELINE_ID}"
    --web-identity-token ${AWS_JWT_TOKEN}
    --duration-seconds 3600
    --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]"
    --output text)
  - export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $1}')
  - export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $2}')
  - export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $3}')
```

The `- >` folded scalar is why the command reads as one line to the shell despite spanning seven lines of YAML.

Three details in that call are load-bearing. `--web-identity-token` receives the injected `${AWS_JWT_TOKEN}` and nothing else, so no secret is interpolated from the variable store. `--role-session-name` embeds `${CI_PIPELINE_ID}`, which means every session that appears in CloudTrail traces back to one pipeline; `publish-raftdb-image` uses `"GitLabCI-${CI_PIPELINE_ID}-RaftDB"` so its actions are separable from the application image push. And `--query` with `--output text` returns the three credential fields as tab-separated text, which the three `export` lines then split with `awk`. No credential is echoed to the log.

Once those variables are exported, the rest of the job is ordinary AWS tooling. Registry authentication uses a token derived from the same session:

```bash
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"
```

`get-login-password` prints a password on stdout and the pipe into `--password-stdin` keeps it off the process table and out of the job log. It expires with the session, like everything else here.



# What the credentials can and cannot do

The session is issued for 3600 seconds. When the pipeline ends, the credentials are already useless, and there is nothing left to rotate or revoke. That number is not tuned; it is the same `--duration-seconds 3600` in all three jobs, and it is longer than a typical run needs. Tightening it per job would reduce the window further, at the price of a failed deploy if a CDK deployment ever ran long enough to outlive its own credential.

What the session may do is whatever the role's permission policy allows, and that is the honest weak point of my setup. One role serves all three jobs, so `push-ecr` runs with the same permissions as `deploy-to-aws`, which needs CloudFormation, ECS, Amplify, Secrets Manager, EFS, S3 and Route 53 access to bring up `AwsplaceStack`. The identity is short-lived; the authority granted to it is not narrow. Federation removed the stored-secret problem, not the over-permissioning problem, and I should not pretend otherwise.

Three jobs declare `id_tokens`: `push-ecr`, `publish-raftdb-image` and `deploy-to-aws`. Everything else in the pipeline runs with no AWS identity whatsoever, which is the interesting half of the design.

<figure>
  <img src="/images/3-BlogsPosted/3.2-Blog2/gitlab-ci.png" alt="GitLab pipeline #73 in job-dependency view, showing fourteen jobs across the build-ci-image, test, build and deploy stages" loading="lazy">
  <figcaption>Pipeline #73 on <code>main</code>: 14 jobs, 35 minutes. Three of them hold an AWS identity. The other eleven, <code>raftdb-image</code> included, run with none.</figcaption>
</figure>

# The chain of custody

This is the part I would actually defend in a review.

The RaftDB container image is the production datastore for awsplace. `raftdb-image` is the job that builds it, and that job has no `id_tokens` block, no role ARN, and no way to reach AWS. It runs in stage `test` on `docker:27-cli`, builds `raftdb:${CI_COMMIT_SHA}`, and then runs four contract tests against the built image: `container_contract_test.sh`, `qualification_runtime_contract_test.sh`, `migration_runtime_contract_test.sh` and `s3_runtime_contract_test.sh`. It installs Trivy 0.72.0 by downloading the release archive and the release checksums file, verifying the checksums file against a hard-coded sha256, then verifying the archive against the checksums file. It records the Docker image ID before and after the scan and fails if the two differ, because a scanner has no business mutating the artefact it is inspecting. Any CRITICAL finding fails the job outright. A HIGH finding fails it too, unless `RAFTDB_ACCEPT_HIGH_CVES` is set to the exact `$CI_COMMIT_SHA` being built, which makes an acceptance a decision about one commit rather than a switch someone leaves on.

The point of giving that job no credential is that a compromised build step has nothing to push with. Whatever a malicious dependency in the RaftDB Dockerfile might attempt, it cannot reach ECR, because no ECR-capable identity exists in that job's environment.

So the tested image has to travel. The job saves it and hands it over as an artifact, together with a small evidence document:

```bash
docker save --output raftdb-image.tar "$LOCAL_IMAGE"
gzip -9 raftdb-image.tar
jq -n \
  --arg commit "$CI_COMMIT_SHA" \
  --arg imageId "$IMAGE_ID_AFTER_SCAN" \
  --arg tag "$LOCAL_IMAGE" \
  --argjson criticalCount "$CRITICAL_COUNT" \
  --argjson highCount "$HIGH_COUNT" \
  --argjson highAccepted "$HIGH_ACCEPTED" \
  '{commit: $commit, imageId: $imageId, localTag: $tag, scan: {criticalCount: $criticalCount, highCount: $highCount, highAccepted: $highAccepted}}' \
  > raftdb-image-evidence.json
```

`publish-raftdb-image` picks that up with `needs: [{job: raftdb-image, artifacts: true}]`. Before it asks for a token, it re-establishes identity twice. It reads `.commit` from `raftdb-image-evidence.json` and fails if it is not `$CI_COMMIT_SHA`, which rejects a stale artifact from an earlier pipeline. Then it runs `gzip -dc raftdb-image.tar.gz | docker load` and compares the loaded image's `{{.Id}}` against `.imageId` from the evidence file, failing on any mismatch. Only after both checks pass does `aws sts assume-role-with-web-identity` appear, with the `-RaftDB` session name. The credential arrives at step four, not step one.

What it does with that credential is deliberately constrained. `scripts/ensure-ecr-repository.sh` resolves the repository URI, and the job then asserts that the repository component is the literal string `awsplace-ecs`, refusing to continue against anything else. It pushes the tag `raftdb-${CI_COMMIT_SHA}`. That tag is immutable in ECR by configuration: the repository runs with `--image-tag-mutability MUTABLE_WITH_EXCLUSION` and an exclusion filter of `filterType=WILDCARD,filter=raftdb-*`, so ordinary tags can move and `raftdb-*` tags cannot. If the tag already exists, the job pulls it and compares its image ID to the one it just verified, failing if the tag points at different bytes rather than overwriting anything.

Then it does the thing I like most in the whole pipeline. It reads back the digest, checks it against `^sha256:[0-9a-f]{64}$`, deletes every local copy of the image with `docker image rm --force`, pulls the image again *by digest*, and re-runs the container and migration contract tests on the bytes ECR served back:

```bash
docker image rm --force \
  "$LOCAL_IMAGE" \
  "${ECR_URI}:${IMAGE_TAG}" \
  "${ECR_URI}@${IMAGE_DIGEST}" 2>/dev/null || true
docker pull "${ECR_URI}@${IMAGE_DIGEST}"
bash raftdb/test/container_contract_test.sh "${ECR_URI}@${IMAGE_DIGEST}"
bash raftdb/test/migration_runtime_contract_test.sh "${ECR_URI}@${IMAGE_DIGEST}"
```

Deleting the local images first is what makes the re-pull meaningful. Without it, Docker would serve the layers it already has and the test would prove nothing about what is actually stored in the registry.

The digest is then handed forward as a dotenv report:

```yaml
artifacts:
  expire_in: 90 days
  paths:
    - raftdb-publish-evidence.json
    - raftdb-publish.env
  reports:
    dotenv: raftdb-publish.env
```

`deploy-to-aws` receives `PUBLISHED_RAFTDB_IMAGE_DIGEST` from that dotenv report, and it does not trust it. Its `before_script` reads `.digest` out of `raftdb-publish-evidence.json` and fails if the dotenv value and the evidence file disagree, then exports the agreed value as `RAFTDB_IMAGE_DIGEST` and runs `scripts/validate-deploy-env.sh`. That script requires nine variables to be present, rejects any value still holding an unresolved `${VAR}` reference, checks `RAFTDB_IMAGE_DIGEST` against the same sha256 pattern, and checks `HOSTED_ZONE_ID` against `^Z[A-Z0-9]+$`. All of it runs *before* the STS call. A missing secret or a malformed digest fails the job while it still has no AWS credential and has created no AWS resources.

The result is that the digest CDK pins into the ECS task definition is provably the digest of an image that was built without AWS access, scanned, tested four ways, verified byte for byte on handover, and tested again after a round trip through the registry.

<figure>
  <img src="/images/diagrams/cicd-pipeline.svg" alt="The four stages of the awsplace GitLab pipeline with the RaftDB image custody chain highlighted" loading="lazy">
  <figcaption>Four stages: <code>build-ci-image</code>, <code>test</code>, <code>build</code>, <code>deploy</code>. The custody lane runs from the credential-free <code>raftdb-image</code> job to the digest cross-check in <code>deploy-to-aws</code>.</figcaption>
</figure>

## References

- [GitLab: ID token authentication](https://docs.gitlab.com/ci/secrets/id_token_authentication/)
- [GitLab: `id_tokens` keyword reference](https://docs.gitlab.com/ci/yaml/#id_tokens)
- [GitLab: Configure OpenID Connect with AWS to retrieve temporary credentials](https://docs.gitlab.com/ci/cloud_services/aws/)
- [AWS STS API: `AssumeRoleWithWebIdentity`](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [AWS IAM: Create OpenID Connect identity providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Amazon ECR: Private registry authentication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html)
- [Amazon ECR: Image tag mutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html)
