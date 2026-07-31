---
title: "Deploy Frontend"
date: 2024-01-01
weight: 6
chapter: false
pre: " <b> 5.6. </b> "
---

## Deploying the Frontend to AWS Amplify

The **awsplace** frontend is a lightweight, static HTML application — it doesn't use a complex JavaScript framework like React or Vue. Instead, its deployment relies on a shell-based build script that performs token substitution, and a CI/CD workflow that uploads the final assets directly to AWS Amplify. The entire process is fully automated.

### Part 1: The Amplify App Infrastructure (Defined in CDK)

The foundation for the frontend deployment is an **AWS Amplify App** resource, provisioned by the **AwsplaceStack** (as detailed in the previous section). The CDK code in **cdk/lib/amplify.ts** configures this resource with specific, important behaviors:

1. **Manual Deployment Model:** The Amplify app is intentionally configured without a connection to a Git repository. The code comments clarify this: "No source-code provider is attached: the frontend **dist/** is deployed to this app as a **.zip** asset from CI". This decouples frontend hosting from any specific source control provider and gives the CI/CD pipeline full control over what gets deployed and when.

2. **Custom Domain & TLS:** The stack maps the root domain (e.g., **place.namanhishere.com**) to the **production** branch. Amplify handles provisioning and auto-renewing the public TLS certificate for this domain — no ACM certificate is supplied for the root. (The **\*.domain** wildcard cert is used only by ALB and API Gateway.)

3. **SPA Rewrite Rules:** Instead of using a stock SPA redirect, the stack defines two custom rules:
   - The first uses a regex-based source pattern that rewrites extension-less paths to **/index.html** — but critically adds **html** to the extension allowlist. This means requests to **/admin.html** are served as the actual file, not silently rewritten to the main SPA shell. Without this, the admin dashboard would break.
   - The second is a catch-all **404 rewrite** — any path not matched by the first rule or an actual file returns **/index.html** with a 404 status, allowing the client-side router to handle it.

---

### Part 2: The Build Process (scripts/build-frontend.sh)

The frontend build is handled by **scripts/build-frontend.sh** — a templating engine built with standard shell tools.

**How it works:**

- The script defines an **apply_tokens()** function that uses **sed** to find and replace placeholder tokens in the source HTML files (**public/index.html** and **public/admin.html**). Tokens include **{{BRAND_NAME}}**, **{{BRAND_DESCRIPTION}}**, **{{WS_URL}}**, **{{FRONTEND_API_URL}}**, and several other branding variables.

- Brand defaults are hardcoded in the script (e.g., **BRAND_NAME** defaults to "lẩu/Place"), but can be overridden via a **.env** file for local development or via CI/CD environment variables.

- Production endpoints are derived from **DOMAIN_NAME**: the WebSocket URL becomes **wss://ws.{DOMAIN_NAME}/ws** and the API URL becomes **https://api.{DOMAIN_NAME}**.

**Output:** The script processes both HTML files, copies all non-HTML static assets (CSS, images, fonts) from **public/** into **dist/**, and finishes with a verification step — it uses **grep** to check for any remaining **{{** tokens. If unresolved placeholders are found, the build fails immediately.

---

### Part 3: The CI/CD Deployment Workflow

The deployment step in the CI/CD pipeline is a multi-command script that orchestrates the upload. Here is a breakdown:

1. **Get Amplify App Details:** The script queries CloudFormation stack outputs using **aws cloudformation describe-stacks** to retrieve the **AmplifyAppId** and **AmplifyBranchName**. This ensures the pipeline always targets the correct Amplify resource — even if the stack is recreated.

2. **Package Frontend Assets:** The **dist/** directory is compressed into a single zip file (**amplify-dist.zip**). This is the deployment artifact.

3. **Initiate Deployment:** The script calls **aws amplify create-deployment**, which tells Amplify to prepare for a new manual deployment. Amplify responds with two critical pieces of information:
   - A unique **jobId** for tracking this deployment.
   - A **pre-signed S3 URL** — temporary, secure access to upload the zip directly to an S3 bucket managed by the Amplify service.

4. **Upload Assets:** The script uses **curl** to upload **amplify-dist.zip** to the pre-signed URL.

5. **Start Deployment Job:** **aws amplify start-deployment** is called with the **jobId**, signaling Amplify to start processing the uploaded zip and deploying its contents to its global CDN.

6. **Wait for Completion:** The script enters a **while** loop, polling deployment status every 10 seconds with **aws amplify get-job**. It checks for **SUCCEED** or **FAILED** status. A 10-minute timeout prevents the job from running indefinitely if something goes wrong.

> ![Amplify Deployment Jobs](/images/5-Workshop/5.6-Deploy-Frontend/Screenshot%202026-07-27%20200851.png)

Once the deployment succeeds, the frontend is live and globally distributed through Amplify's CDN. The CI/CD pipeline proceeds to the next step — updating the ECS service and running post-deploy verification.