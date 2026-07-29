---
title: "Week 3 Worklog"
date: 2026-06-29
weight: 3
chapter: false
pre: " <b> 1.3. </b> "
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
---

### Week 3 Objectives:

* Put Discord login behind API Gateway on Lambda, so a placement can be attributed to a real user id instead of to whatever the browser claims.
* Issue a session the API can verify on its own, with no store lookup on the request path.
* Make the admin endpoints unreachable cross-site, and cover both the auth module and the proxy with tests that need no AWS account.

### Tasks to be carried out this week:

| Day | Task | Start Date | Completion Date | Reference Material |
| --- | ---- | ---------- | --------------- | ------------------ |
| 2   | - Define the API function in cdk/lib/lambda.ts: a plain lambda.Function on NODEJS_24_X, handler index.handler, code taken from the ../lambda directory as an asset <br> - Size it at memorySize 512 and timeout 30 seconds <br> - Front it with an HTTP API v2 in cdk/lib/apigw.ts, registered as defaultIntegration so one catch-all route hands every path and method to Express 5 <br> - Map the custom domain api.place.namanhishere.com onto the default stage and alias it from Route 53 | 29/06/2026 | 29/06/2026 | <https://docs.aws.amazon.com/lambda/latest/dg/lambda-nodejs.html> <br> <https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html> <br> <https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_lambda-readme.html> |
| 3   | - Build the Discord authorize URL with response_type=code and scope=identify, nothing wider <br> - **Exchange the code server side:** <br>&emsp; + POST form-urlencoded to the oauth2/token endpoint with grant_type=authorization_code <br>&emsp; + send client_id, client_secret and the same redirect_uri that is registered in the Developer Portal <br>&emsp; + fail loudly on a non-2xx token response instead of continuing with an empty profile <br> - Read the identity from users/@me with the bearer token and reduce it to id, username and avatar | 30/06/2026 | 30/06/2026 | <https://discord.com/developers/docs/topics/oauth2#authorization-code-grant> |
| 4   | - Sign the session as a HS256 JWT with claims discordId, username, avatar and isAdmin, expiresIn 7d <br> - Pin algorithms to HS256 on the verify side so a token that arrives with a different alg header is refused <br> - **Serialise it into the cookie rplace_session:** <br>&emsp; + httpOnly, so no script can read it <br>&emsp; + sameSite lax, because the Discord return trip is a top-level GET navigation <br>&emsp; + secure only when NODE_ENV is production, so local HTTP still works <br> - Recompute isAdmin from ADMIN_DISCORD_IDS on every request rather than trusting the claim in the token | 01/07/2026 | 01/07/2026 | <https://github.com/auth0/node-jsonwebtoken> <br> <https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie> |
| 5   | - **Fix the cross-subdomain session, the real problem of the week:** <br>&emsp; + set the cookie Domain to the parent hostname place.namanhishere.com, with no leading dot <br>&emsp; + set allowCredentials true on the API Gateway CORS preflight and name the frontend origin explicitly, because a wildcard origin is illegal with credentials <br>&emsp; + echo the request Origin from the Express middleware when it matches ALLOWED_ORIGINS and always send Access-Control-Allow-Credentials <br> - Add GET /api/me, returning loggedIn false for an anonymous caller rather than a 401, so the frontend can render a logged-out canvas without treating it as an error | 02/07/2026 | 02/07/2026 | <https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS> <br> <https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-cors.html> |
| 6   | - Forward /api/admin to the ALB behind ECS_ALB_URL, rewriting only the Host header and deliberately preserving Origin so the Go server can run its own same-origin check <br> - Order the middleware so requireSameOrigin runs before requireAdmin on POST, PUT and DELETE <br> - Answer 502 when ECS_ALB_URL is absent or unparseable, never a stack trace <br> - Cover auth.js and admin-proxy.js with Vitest and supertest, including the Set-Cookie Domain cases and a proxy test that boots a local echo server on port 0 | 03/07/2026 | 03/07/2026 | <https://expressjs.com/en/guide/using-middleware.html> <br> <https://vitest.dev/guide/> <br> <https://github.com/ladjs/supertest> |

The session is one signed token and one cookie, and every attribute on that cookie is there for a reason:

```javascript
// awsplace/lambda/auth.js
export function createSessionToken(user) {
    return jwt.sign(
        {
            discordId: user.id,
            username: user.username,
            avatar: user.avatar,
            isAdmin: isAdmin(user.id),
        },
        getJwtSecret(),
        { algorithm: 'HS256', expiresIn: '7d' }
    );
}

export function buildSessionCookie(token) {
    return cookie.serialize(COOKIE_NAME, token, {
        httpOnly: true,
        sameSite: 'lax',
        secure: process.env.NODE_ENV === 'production',
        domain: process.env.COOKIE_DOMAIN || undefined,
        maxAge: SESSION_TTL_MS,
        path: '/',
    });
}
```

The admin path is the one place where middleware order is a security property rather than a style choice. The CSRF check has to reject the request before anything reads the session:

```javascript
// awsplace/lambda/admin-proxy.js
function requireSameOriginOnMutation(req, res, next) {
    if (['POST', 'PUT', 'DELETE'].includes(req.method)) {
        return requireSameOrigin(req, res, next);
    }
    next();
}

export function registerAdminProxyRoutes(app) {
    app.all('/api/admin/*_', requireSameOriginOnMutation, requireAdmin, async (req, res) => {
```

### Week 3 Achievements:

* Discord login works end to end through AWS. `cdk/lib/apigw.ts` creates an HTTP API v2 whose `defaultIntegration` is the Lambda, so there is exactly one catch-all route and Express 5 owns all routing inside the function. The function itself is a plain `lambda.Function` on `NODEJS_24_X` at 512 MB and a 30 second timeout, with its code shipped as a directory asset from `../lambda`. There is no bundler in the path, which keeps the deploy honest: what is in the folder is what runs.

* The session is stateless on purpose. `/auth/callback` exchanges the code at Discord's `oauth2/token` endpoint, reads `users/@me`, and signs a HS256 JWT with `expiresIn: '7d'` carrying `discordId`, `username`, `avatar` and `isAdmin`. Verification pins `algorithms: ['HS256']`, so a token presented with a different `alg` header is rejected rather than reinterpreted, and `getJwtSecret()` throws when `SESSION_SECRET` is unset instead of signing with an empty key. `isAdmin` is recomputed from `ADMIN_DISCORD_IDS` on every request, so the claim inside the token is a convenience for the frontend and never the authority.

* The hard part of the week was not OAuth, it was the cookie. The frontend is served from `place.namanhishere.com` and the API answers on `api.place.namanhishere.com`, so a cookie set by the API was simply not being sent back with subsequent requests. `awsplace/learnings.md` records the resolution I settled on: a shared parent `Domain` of `place.namanhishere.com` with **no leading dot**, `allowCredentials: true` on the API Gateway preflight together with an explicitly named frontend origin, an Express middleware that echoes the request `Origin` when it matches `ALLOWED_ORIGINS` and always sets `Access-Control-Allow-Credentials`, and `credentials: "include"` on every frontend fetch against an absolute API URL. Three of those four are necessary and none of them is sufficient alone, which is why this cost a day. `sameSite: 'lax'` survives the flow only because the Discord return trip is a top-level GET navigation rather than a background request.

* The third hostname is `ws.place.namanhishere.com`, and it is where the admin proxy points. `cdk/lib/stack.ts` passes `ecsAlbUrl: https://ws.${domainName}` into the Lambda as `ECS_ALB_URL`, and the A record for that name is created next to the load balancer in `cdk/lib/ecs.ts`, not in `route53.ts`. So the admin endpoints reach the Go server through the same public ALB hostname the browser uses for WebSockets, and the proxy forwards every header except `host`, keeping `Origin` intact so the Go server's own origin policy still gets to run.

* Middleware order on `/api/admin` is asserted by a test, not left to reading. `requireSameOriginOnMutation` wraps `requireSameOrigin` and runs before `requireAdmin` for `POST`, `PUT` and `DELETE`, so a mutation with a valid admin cookie but no `Origin` header is refused with 403 before the session is even consulted. `GET` skips the origin check deliberately, because a read has nothing to forge. A missing or unparseable `ECS_ALB_URL` produces 502 and a server-side log line rather than an exception surfacing to the caller.

* Both modules are covered by Vitest with supertest, run by `npm test` in the `lambda` package. The auth tests exercise a tampered token signed with the wrong secret, an expired token, a spoofed `Origin` with a different scheme, and the `Set-Cookie` `Domain` attribute in both its present and absent forms. The proxy tests boot a real Express echo server on port 0 and point `ECS_ALB_URL` at it, then assert path preservation, header forwarding, that the client `host` is not forwarded, and that a `Set-Cookie` from the backend is relayed. None of it needs an AWS account, which is the only reason I ran it as often as I did.

* Two defects are known and written down rather than quietly left. The cookie sets `maxAge: SESSION_TTL_MS`, but the `cookie` package expects seconds and `SESSION_TTL_MS` is milliseconds, so the emitted `Max-Age` is far longer than the seven days intended; the JWT's own `expiresIn` still bounds the real session, so the effect is a stale cookie rather than a stale session. And the OAuth `state` value is generated on login but never checked on callback, so it currently documents an intent instead of enforcing one. Both are cheap to fix and neither was fixed this week.
