---
title: "Worklog Tuần 3"
date: 2026-06-29
weight: 3
chapter: false
pre: " <b> 1.3. </b> "
reportType: worklog
reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---

### Mục tiêu tuần 3:

* Đưa phần đăng nhập Discord lên Lambda nằm sau API Gateway, để mỗi lần đặt pixel quy được về một user id thật thay vì tin vào những gì trình duyệt khai báo.
* Phát hành một session mà API tự xác thực được, không phải tra cứu store trên đường đi của mỗi request.
* Làm cho các endpoint admin không thể bị gọi từ site khác, và phủ kiểm thử cả module xác thực lẫn phần proxy bằng các test không cần tài khoản AWS.

### Các công việc cần triển khai trong tuần này:

| Thứ | Công việc | Ngày bắt đầu | Ngày hoàn thành | Nguồn tài liệu |
| --- | --------- | ------------ | --------------- | -------------- |
| 2   | - Khai báo function API trong cdk/lib/lambda.ts: một lambda.Function thuần trên NODEJS_24_X, handler index.handler, code lấy từ thư mục ../lambda dưới dạng asset <br> - Đặt memorySize 512 và timeout 30 giây <br> - Đặt trước nó một HTTP API v2 trong cdk/lib/apigw.ts, đăng ký làm defaultIntegration để một route bắt-tất-cả chuyển mọi path và mọi method cho Express 5 <br> - Gắn custom domain api.place.namanhishere.com vào stage mặc định và trỏ alias từ Route 53 | 29/06/2026 | 29/06/2026 | <https://docs.aws.amazon.com/lambda/latest/dg/lambda-nodejs.html> <br> <https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html> <br> <https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_lambda-readme.html> |
| 3   | - Dựng URL authorize của Discord với response_type=code và scope=identify, không xin thêm gì <br> - **Đổi code lấy token ở phía server:** <br>&emsp; + POST dạng form-urlencoded tới endpoint oauth2/token với grant_type=authorization_code <br>&emsp; + gửi client_id, client_secret và đúng redirect_uri đã đăng ký trong Developer Portal <br>&emsp; + báo lỗi ngay khi token response không phải 2xx, thay vì đi tiếp với một profile rỗng <br> - Đọc danh tính từ users/@me bằng bearer token rồi rút gọn còn id, username và avatar | 30/06/2026 | 30/06/2026 | <https://discord.com/developers/docs/topics/oauth2#authorization-code-grant> |
| 4   | - Ký session thành một JWT HS256 với các claim discordId, username, avatar và isAdmin, expiresIn 7d <br> - Ghim algorithms về HS256 ở phía verify để token gửi kèm alg header khác bị từ chối <br> - **Đóng gói vào cookie rplace_session:** <br>&emsp; + httpOnly, để không script nào đọc được <br>&emsp; + sameSite lax, vì lượt quay về từ Discord là một điều hướng GET ở cấp cao nhất <br>&emsp; + secure chỉ khi NODE_ENV là production, để môi trường cục bộ chạy HTTP vẫn dùng được <br> - Tính lại isAdmin từ ADMIN_DISCORD_IDS ở mỗi request thay vì tin vào claim nằm trong token | 01/07/2026 | 01/07/2026 | <https://github.com/auth0/node-jsonwebtoken> <br> <https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie> |
| 5   | - **Xử lý session xuyên subdomain, đây là vấn đề thật của tuần:** <br>&emsp; + đặt Domain của cookie là hostname cha place.namanhishere.com, không có dấu chấm ở đầu <br>&emsp; + đặt allowCredentials true cho CORS preflight của API Gateway và nêu tên origin của frontend một cách tường minh, vì origin dạng ký tự đại diện không hợp lệ khi có credentials <br>&emsp; + phản chiếu lại Origin của request từ middleware Express khi nó khớp ALLOWED_ORIGINS và luôn gửi Access-Control-Allow-Credentials <br> - Thêm GET /api/me, trả về loggedIn false cho người gọi chưa đăng nhập thay vì 401, để frontend vẽ được canvas ở trạng thái chưa đăng nhập mà không coi đó là lỗi | 02/07/2026 | 02/07/2026 | <https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS> <br> <https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-cors.html> |
| 6   | - Chuyển tiếp /api/admin tới ALB nằm sau ECS_ALB_URL, chỉ viết lại header Host và giữ nguyên Origin có chủ ý để server Go tự chạy kiểm tra same-origin của nó <br> - Xếp thứ tự middleware sao cho requireSameOrigin chạy trước requireAdmin với POST, PUT và DELETE <br> - Trả 502 khi ECS_ALB_URL thiếu hoặc không phân tích được, không bao giờ trả về stack trace <br> - Phủ kiểm thử auth.js và admin-proxy.js bằng Vitest cùng supertest, gồm các trường hợp Set-Cookie Domain và một test proxy dựng server echo cục bộ trên port 0 | 03/07/2026 | 03/07/2026 | <https://expressjs.com/en/guide/using-middleware.html> <br> <https://vitest.dev/guide/> <br> <https://github.com/ladjs/supertest> |

Session chỉ gồm một token đã ký và một cookie, và mọi thuộc tính trên cookie đó đều có lý do:

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

Đường admin là chỗ duy nhất mà thứ tự middleware là một thuộc tính an toàn chứ không phải chuyện thẩm mỹ. Bước kiểm tra CSRF phải từ chối request trước khi có bất cứ gì đọc tới session:

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

### Kết quả đạt được tuần 3:

* Đăng nhập Discord đã chạy trọn vẹn trên AWS. `cdk/lib/apigw.ts` tạo một HTTP API v2 với `defaultIntegration` là Lambda, nên chỉ có đúng một route bắt-tất-cả và Express 5 nắm toàn bộ việc định tuyến bên trong function. Bản thân function là một `lambda.Function` thuần trên `NODEJS_24_X` với 512 MB và timeout 30 giây, code được đóng gói thành asset thư mục từ `../lambda`. Không có bundler nào trong đường đi, và điều đó giữ cho việc triển khai trung thực: những gì nằm trong thư mục chính là những gì chạy.

* Session được thiết kế không lưu trạng thái, đó là chủ ý. `/auth/callback` đổi code tại endpoint `oauth2/token` của Discord, đọc `users/@me`, rồi ký một JWT HS256 với `expiresIn: '7d'` mang theo `discordId`, `username`, `avatar` và `isAdmin`. Phía verify ghim `algorithms: ['HS256']`, nên token gửi kèm một `alg` header khác sẽ bị từ chối chứ không bị diễn giải lại, còn `getJwtSecret()` ném lỗi khi `SESSION_SECRET` chưa được đặt thay vì ký bằng khoá rỗng. `isAdmin` được tính lại từ `ADMIN_DISCORD_IDS` ở mỗi request, nên claim nằm trong token chỉ là tiện lợi cho frontend và không bao giờ là thẩm quyền.

* Phần khó của tuần không phải OAuth mà là cookie. Frontend được phục vụ từ `place.namanhishere.com` còn API trả lời trên `api.place.namanhishere.com`, nên cookie do API đặt ra đơn giản là không được gửi kèm các request sau đó. `awsplace/learnings.md` ghi lại cách giải quyết tôi đã chốt: dùng `Domain` cha chung là `place.namanhishere.com`, **không có dấu chấm ở đầu**, đặt `allowCredentials: true` cho preflight của API Gateway kèm một origin frontend được nêu tên tường minh, một middleware Express phản chiếu `Origin` của request khi nó khớp `ALLOWED_ORIGINS` và luôn đặt `Access-Control-Allow-Credentials`, cùng `credentials: "include"` trên mọi lệnh fetch của frontend tới một URL API tuyệt đối. Ba trong bốn điều đó là cần thiết và không điều nào tự nó là đủ, đó là lý do việc này tốn một ngày. `sameSite: 'lax'` chỉ trụ được trong luồng này vì lượt quay về từ Discord là một điều hướng GET ở cấp cao nhất chứ không phải một request nền.

* Hostname thứ ba là `ws.place.namanhishere.com`, và đó là nơi admin proxy trỏ tới. `cdk/lib/stack.ts` truyền `ecsAlbUrl: https://ws.${domainName}` vào Lambda dưới tên `ECS_ALB_URL`, còn bản ghi A cho tên đó được tạo ngay cạnh load balancer trong `cdk/lib/ecs.ts`, không phải trong `route53.ts`. Vậy nên các endpoint admin đi tới server Go qua đúng hostname ALB công khai mà trình duyệt dùng cho WebSocket, và proxy chuyển tiếp mọi header trừ `host`, giữ nguyên `Origin` để chính sách origin của server Go vẫn được chạy.

* Thứ tự middleware trên `/api/admin` được một test khẳng định chứ không phải để người đọc tự suy ra. `requireSameOriginOnMutation` bọc `requireSameOrigin` và chạy trước `requireAdmin` với `POST`, `PUT` và `DELETE`, nên một lệnh thay đổi dữ liệu có cookie admin hợp lệ nhưng thiếu header `Origin` sẽ bị từ chối 403 trước khi session được xem tới. `GET` bỏ qua bước kiểm tra origin một cách có chủ ý, vì một lượt đọc không có gì để giả mạo. `ECS_ALB_URL` thiếu hoặc không phân tích được sẽ cho ra 502 kèm một dòng log ở phía server, thay vì để một exception lộ ra cho người gọi.

* Cả hai module đều được phủ bởi Vitest cùng supertest, chạy bằng `npm test` trong package `lambda`. Các test xác thực thử một token bị sửa và ký bằng khoá sai, một token đã hết hạn, một `Origin` giả mạo với scheme khác, và thuộc tính `Domain` của `Set-Cookie` ở cả hai dạng có và không có. Các test proxy dựng một server echo Express thật trên port 0 rồi trỏ `ECS_ALB_URL` vào đó, sau đó khẳng định path được giữ nguyên, header được chuyển tiếp, `host` của client không được chuyển tiếp, và `Set-Cookie` từ backend được trả về nguyên vẹn. Không phần nào cần tài khoản AWS, và đó là lý do duy nhất khiến tôi chạy chúng nhiều lần như đã chạy.

* Hai lỗi đã biết và được ghi lại chứ không im lặng bỏ qua. Cookie đặt `maxAge: SESSION_TTL_MS`, nhưng package `cookie` tính theo giây còn `SESSION_TTL_MS` là mili giây, nên `Max-Age` phát ra dài hơn rất nhiều so với bảy ngày dự định; `expiresIn` của chính JWT vẫn chặn thời hạn session thật, nên hậu quả là một cookie cũ chứ không phải một session cũ. Và giá trị `state` của OAuth được sinh ra lúc đăng nhập nhưng không hề được kiểm tra ở bước callback, nên hiện tại nó ghi lại một ý định chứ không thực thi ý định đó. Cả hai đều rẻ để sửa và tuần này chưa sửa cái nào.
