---
title: "Environment Variables — Setup with GitLab"
date: 2026-07-27
weight: 8
chapter: false
pre: " <b> 5.2.8 </b> "
---

The deployment pipeline validates required variables with `awsplace/scripts/validate-deploy-env.sh`. The script refuses to start if any variable is missing, empty, or contains an unresolved `${...}` reference.

## Where to set the variables

1. Open the GitLab project at `https://git.namanhishere.com/namanhishere/awsplace`.
2. Go to **Settings** → **CI/CD** → **Variables**.
3. Click **Add variable**.
4. Enter the key, value, and type.
5. Mark sensitive values as **Masked** and **Protected**.

## Required variables

| Variable | Value | Masked | Protected | Purpose |
|---|---|---|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/GitLabCDKDeployRole` | Yes | Yes | IAM role assumed by the deploy job through OIDC |
| `HOSTED_ZONE_ID` | `Z0456501936MVLQCQV3O6Y` | No | Yes | Route 53 hosted zone ID for `place.namanhishere.com` |
| `DOMAIN_NAME` | `place.namanhishere.com` | No | Yes | Base domain used for ALB, API Gateway, and Amplify |
| `SESSION_SECRET` | 96-character random hex string | Yes | Yes | Key used to sign JWT session cookies |
| `DISCORD_CLIENT_ID` | `1510122461088448633` | Yes | Yes | Discord OAuth2 Client ID |
| `DISCORD_CLIENT_SECRET` | From Discord OAuth2 page | Yes | Yes | Discord OAuth2 Client Secret |
| `DISCORD_REDIRECT_URI` | `https://api.place.namanhishere.com/auth/callback` | No | Yes | OAuth2 callback URL; must match Discord app settings |
| `ADMIN_DISCORD_IDS` | Comma-separated Discord user IDs | Yes | Yes | Users allowed into the admin dashboard |
| `FRONTEND_URL` | `https://place.namanhishere.com` | No | Yes | Public URL of the frontend |
| `RAFTDB_IMAGE_DIGEST` | Provided by the `publish-raftdb-image` job | No | Yes | Immutable digest of the tested RaftDB image |

## Generating the session secret

Generate a 96-character random hex string:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

Copy the output into the `SESSION_SECRET` variable. Do not save it to a file.

## The RaftDB image digest

`RAFTDB_IMAGE_DIGEST` is the only value you cannot prepare in advance. The validator enforces the exact shape `sha256:[0-9a-f]{64}` so that RaftDB is never deployed by a mutable tag. The `publish-raftdb-image` job in `.gitlab-ci.yml` produces this digest and passes it to the deploy job as a dotenv artifact.

## Optional variables

| Variable | Value | Purpose |
|---|---|---|
| `RAFTDB_ACCEPT_HIGH_CVES` | Current commit SHA | If the Trivy scan finds HIGH vulnerabilities in the RaftDB image, setting this variable to the commit SHA allows the pipeline to proceed after explicit owner acknowledgment |

## Built-in variables not to redefine

GitLab provides these automatically. Do not define them yourself:

- `CI_REGISTRY_USER`
- `CI_REGISTRY_PASSWORD`
- `CI_REGISTRY`
- `CI_REGISTRY_IMAGE`
- `CI_COMMIT_SHA`
- `CI_COMMIT_REF_SLUG`
- `CI_PIPELINE_ID`
- `CI_PROJECT_DIR`

## Protected variables

Mark deployment-related variables as **Protected**. This ensures they are only injected into pipelines running on protected branches (typically `main`). A merge request pipeline will not receive these values, which prevents accidental deployments from feature branches.

## Validation

The `validate-deploy-env.sh` script checks each required variable. A typical failure looks like this:

```
ERROR: required deployment variable HOSTED_ZONE_ID is not set
ERROR: required deployment variable RAFTDB_IMAGE_DIGEST contains an unresolved variable reference
```

Fix the variable and re-run the pipeline.
