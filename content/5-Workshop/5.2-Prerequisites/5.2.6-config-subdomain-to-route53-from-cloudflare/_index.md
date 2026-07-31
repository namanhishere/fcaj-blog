---
title: "Config subdomain to Route53 from Cloudflare"
date: 2026-07-27
weight: 6
chapter: false
pre: " <b> 5.2.6 </b> "
---

The workshop domain is `place.namanhishere.com`. The DNS is delegated from Cloudflare to an AWS Route 53 public hosted zone. This lets Route 53 manage the records for the ALB, API Gateway, and Amplify without moving the entire root domain to AWS.

## Step 1: Create the Route 53 hosted zone

1. Open the Route 53 console in the `ap-southeast-1` region.
2. Click **Hosted zones** → **Create hosted zone**.
3. Enter the domain name `place.namanhishere.com`.
4. Choose **Public hosted zone**.
5. Click **Create hosted zone**.

Route 53 assigns four nameservers. For this workshop they are:

- `ns-204.awsdns-25.com`
- `ns-1073.awsdns-06.org`
- `ns-595.awsdns-10.net`
- `ns-1827.awsdns-36.co.uk`

The hosted zone ID for this workshop is `Z0456501936MVLQCQV3O6Y`. You will store this in the `HOSTED_ZONE_ID` GitLab CI/CD variable.

## Step 2: Copy the nameservers

After the zone is created, the Route 53 detail page shows the nameservers and the hosted zone ID.

![Route 53 hosted zone for place.namanhishere.com](/images/5-Workshop/5.2-Prerequisite/route53.png)

## Step 3: Add NS records in Cloudflare

1. Open the Cloudflare dashboard for the parent domain `namanhishere.com`.
2. Go to **DNS** → **Records**.
3. Add four `NS` records for the subdomain `place`.
4. Each `NS` record points to one of the Route 53 nameservers.
5. Leave the TTL on **Auto**.

The screenshot below shows the Cloudflare DNS records for the delegation.

![Cloudflare NS records pointing to Route 53](/images/5-Workshop/5.2-Prerequisite/cloudflare.png)

## Step 4: Wait for propagation

NS record changes can take anywhere from a few minutes to several hours to propagate, depending on the TTL of the parent zone. Cloudflare `NS` records with **Auto** TTL typically propagate quickly.

## Step 5: Verify with `dig`

Run this command from your local machine:

```bash
dig place.namanhishere.com NS
```

The output should list the four Route 53 nameservers.

![dig output for place.namanhishere.com NS records](/images/5-Workshop/5.2-Prerequisite/digcheck.png)

You can also use `+short` for a compact view:

```bash
dig place.namanhishere.com NS +short
```

Expected output:

```
ns-204.awsdns-25.com.
ns-1073.awsdns-06.org.
ns-595.awsdns-10.net.
ns-1827.awsdns-36.co.uk.
```

## Why NS records and not a CNAME?

A `CNAME` at the apex of a subdomain can conflict with other record types such as `SOA` and `NS`. Delegating the entire `place.namanhishere.com` subdomain to Route 53 with `NS` records gives AWS full control over all records under that subdomain, including the apex `A` record for Amplify, the `api` alias for API Gateway, and the `ws` alias for the ALB.
