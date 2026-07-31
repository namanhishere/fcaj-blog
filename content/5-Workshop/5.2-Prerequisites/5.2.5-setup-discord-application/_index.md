---
title: "Setup Discord Application"
date: 2026-07-27
weight: 5
chapter: false
pre: " <b> 5.2.5 </b> "
---

Anyone can view the canvas, but placing a pixel requires a Discord login. The OAuth application is therefore a hard prerequisite, not a nice-to-have.

## Step 1: Create the application

1. Open the [Discord Developer Portal](https://discord.com/developers/applications).
2. Click **New Application**.
3. Name it `place` or any name you prefer. The screenshots in this workshop use `place`.

## Step 2: Copy the Client ID and Client Secret

1. In the application, go to **OAuth2** → **General**.
2. Copy the **Client ID**. For this workshop it is `1510122461088448633`.
3. Click **Reset Secret** to reveal the **Client Secret** if you have not already generated one.
4. Copy the secret and store it immediately. It is only shown once.


## Step 3: Configure redirect URIs

Discord requires redirect URIs to match exactly, character for character, including scheme and trailing slashes. Add these three URIs:

| URI | Purpose |
|---|---|
| `https://place.namanhishere.com/auth/callback` | OAuth callback for the Amplify-hosted frontend |
| `https://api.place.namanhishere.com/auth/callback` | OAuth callback for the Lambda-backed API |
| `http://localhost:8980/auth/callback` | Local development with the Go server |

The screenshot below shows the Discord OAuth2 page with the two production redirect URIs filled in.

![Discord OAuth2 configuration](/images/5-Workshop/5.2-Prerequisite/discord_oauth.png)

## Step 4: Select the `identify` scope

The application only needs to know the Discord user ID. Request only the `identify` scope. Do not request `email`, `guilds`, `connections`, or any other scope. The screenshot above shows only `identify` selected.

## Step 5: Find your Discord user ID

1. In Discord, enable Developer Mode in **Settings** → **Advanced** → **Developer Mode**.
2. Right-click your own username and choose **Copy User ID**.
3. Paste this value into the `ADMIN_DISCORD_IDS` variable. Separate multiple admins with commas.

## Step 6: Store the values

By the end of this section you should have:

| Value | Where to store |
|---|---|
| Client ID | GitLab CI/CD variable `DISCORD_CLIENT_ID` |
| Client Secret | GitLab CI/CD variable `DISCORD_CLIENT_SECRET` |
| Redirect URI | GitLab CI/CD variable `DISCORD_REDIRECT_URI` and Discord app settings |
| Your Discord user ID | GitLab CI/CD variable `ADMIN_DISCORD_IDS` |
