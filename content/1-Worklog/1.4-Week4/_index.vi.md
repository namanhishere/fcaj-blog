---
title: "Worklog Tuần 4"
date: 2026-07-06
weight: 4
chapter: false
pre: " <b> 1.4. </b> "
reportType: worklog
reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---

### Mục tiêu tuần 4:

* Mô tả toàn bộ phần triển khai bằng một stack CDK duy nhất, để không chi tiết nào của nó phụ thuộc vào một cú click trên console mà về sau tôi sẽ quên.
* Chọn một hình dạng mạng và một hình dạng IAM mà tôi bảo vệ được: không có subnet riêng nào tôi không cần, không có action nào trong policy mà tôi không gọi được tên.
* Đưa ba hostname công khai lên TLS, với load balancer được cấu hình cho những kết nối mở liên tục hàng giờ.

### Các công việc cần triển khai trong tuần này:

| Thứ | Công việc | Ngày bắt đầu | Ngày hoàn thành | Nguồn tài liệu |
| --- | --------- | ------------ | --------------- | -------------- |
| 2   | - Viết cdk/lib/vpc.ts: maxAzs 2, một nhóm public subnet ở cidrMask 24, và natGateways 0 <br> - **Chấp nhận hệ quả của việc bỏ NAT thay vì che nó đi:** <br>&emsp; + các task Fargate nằm trong public subnet và cần assignPublicIp true để tải được image <br>&emsp; + do đó sự cô lập đến từ security group, không đến từ một ranh giới định tuyến <br>&emsp; + hai NAT gateway, tức mức mặc định của CDK ở maxAzs 2, sẽ là dòng chi phí định kỳ lớn nhất trong hoá đơn của một service chỉ có một task <br> - Kiểm tra đầu vào của stack trong cdk/bin/app.ts để một giá trị sai bị chặn ngay lúc synth chứ không phải giữa lúc triển khai | 06/07/2026 | 06/07/2026 | <https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html> <br> <https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_ec2-readme.html> |
| 3   | - Khai báo ba role trong cdk/lib/iam.ts: ECS task execution, ECS task, và Lambda execution <br> - Liệt kê tường minh từng action thay vì viết một ký tự đại diện cho cả service <br> - Thu hẹp resource về đúng ARN của bucket và của object, không phải về cả tài khoản <br> - Chỉ để resource dạng sao ở nơi API không có resource nào để nêu tên, tức lệnh lấy authorization token của ECR và hai lệnh ghi CloudWatch Logs, và ghi lại rằng đó là có chủ ý | 07/07/2026 | 07/07/2026 | <https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html> <br> <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html> |
| 4   | - Dựng ALB trong cdk/lib/ecs.ts: internet-facing, nằm trong public subnet, HTTPS trên 443 với chứng chỉ ký tự đại diện <br> - Thêm một listener HTTP trên 80 chỉ làm duy nhất một việc là chuyển hướng vĩnh viễn sang 443 <br> - Trỏ target group vào cổng container 8980 với health check /health, chu kỳ 30 giây, timeout 5 giây, ngưỡng khoẻ 2 <br> - **Điều chỉnh cho các kết nối WebSocket dài:** <br>&emsp; + đặt idle_timeout.timeout_seconds là 3600 trên load balancer, không phải trên target group <br>&emsp; + đặt deregistration_delay.timeout_seconds là 30 trên target group | 08/07/2026 | 08/07/2026 | <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html> <br> <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html> |
| 5   | - Nhập hosted zone theo id trong cdk/lib/route53.ts bằng fromHostedZoneAttributes, để synth không cần credential AWS <br> - Yêu cầu một chứng chỉ ACM ký tự đại diện cho domain và xác thực nó bằng DNS trên đúng zone đó <br> - Giữ route53.ts không chứa bản ghi nào: tên api được tạo cạnh custom domain của API Gateway, tên ws được tạo cạnh load balancer, còn tên gốc để Amplify lo <br> - Xác nhận chứng chỉ ký tự đại diện được cả API Gateway và ALB sử dụng | 09/07/2026 | 09/07/2026 | <https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html> <br> <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html> |
| 6   | - Tạo app Amplify trong cdk/lib/amplify.ts với branch production và không khai báo source code provider, vì CI tải lên một asset zip chứ không để Amplify kéo repository <br> - Thêm các rule rewrite cho SPA và gắn domain gốc bằng mapRoot, để enableAutoSubdomain là false <br> - Để Amplify tự quản chứng chỉ và tự quản bản ghi DNS của nó, và ghi lại lý do việc khai báo trùng trong CDK làm hỏng lượt triển khai <br> - Nối npm test trong cdk/package.json để chạy tsc, rồi cdk synth, rồi bảy tệp test Jest kiểm tra hợp đồng trên template đã synth | 10/07/2026 | 10/07/2026 | <https://docs.aws.amazon.com/amplify/latest/userguide/redirects.html> <br> <https://docs.aws.amazon.com/amplify/latest/userguide/custom-domains.html> |

Phần mạng dài 22 dòng và mỗi dòng trong đó đều là một quyết định:

```typescript
// awsplace/cdk/lib/vpc.ts
export function createVpc(scope: Construct): VpcOutput {
  const vpc = new ec2.Vpc(scope, 'AwsplaceVpc', {
    maxAzs: 2,
    natGateways: 0,
    subnetConfiguration: [
      {
        name: 'Public',
        subnetType: ec2.SubnetType.PUBLIC,
        cidrMask: 24,
      },
    ],
  });

  return { vpc };
}
```

IAM thì ngược lại, không ngắn gọn chút nào. Nêu tên bốn action S3 và bốn ARN thì dài hơn một ký tự đại diện, nhưng đó là bản duy nhất tôi soát lại được:

```typescript
// awsplace/cdk/lib/iam.ts
ecsTaskRole.addToPolicy(
  new iam.PolicyStatement({
    actions: [
      's3:GetObject',
      's3:PutObject',
      's3:DeleteObject',
      's3:ListBucket',
    ],
    resources: [
      storage.canvasBucket.bucketArn,
      `${storage.canvasBucket.bucketArn}/*`,
      storage.exportsBucket.bucketArn,
      `${storage.exportsBucket.bucketArn}/*`,
    ],
  })
);
```

Idle timeout là thiết lập duy nhất tôi đặt sai chỗ ngay lần đầu, và cách sửa được ghi lại ngay trong code:

```typescript
// awsplace/cdk/lib/ecs.ts
targetGroup.setAttribute('deregistration_delay.timeout_seconds', '30');
// chage from the target group to the load balancer to set the idle timeout
alb.setAttribute('idle_timeout.timeout_seconds', '3600');
```

### Kết quả đạt được tuần 4:

* Toàn bộ phần triển khai là một stack CloudFormation duy nhất được synth từ TypeScript, chia thành các module theo từng mối quan tâm và được `cdk/lib/stack.ts` ghép lại. Không có gì trong hệ thống đang chạy được tạo bằng tay, nghĩa là câu trả lời cho "vì sao chỗ này được cấu hình như vậy" luôn là một tệp chứ không phải một ký ức.

* VPC được giữ tối giản một cách có chủ ý: `maxAzs: 2`, một nhóm public subnet duy nhất, và `natGateways: 0`. Dòng cuối cùng đó là quyết định chi phí lớn nhất trong stack, vì ở `maxAzs: 2` mức mặc định của CDK là một NAT gateway cho mỗi availability zone, tính tiền theo giờ bất kể có lưu lượng đi ra hay không. Bỏ chúng đi không phải là không có hệ quả và tôi ghi lại hệ quả đó chứ không nói cho qua: task Fargate chạy trong public subnet với `assignPublicIp: true` để tải được image, nên sự cô lập mà một private subnet đáng lẽ mang lại giờ hoàn toàn đến từ security group. Security group của ALB nhận 80 và 443 từ mọi nơi; security group của task chỉ nhận 8980 từ security group của ALB, và không nhận gì khác. Với một service chỉ có một task, đó là một ranh giới tôi soát được ở một chỗ duy nhất.

* Mọi policy trong `cdk/lib/iam.ts` liệt kê action của nó mỗi dòng một action, và ba role được tách theo đúng việc chúng làm: role task execution tải image và ghi log, role task chạm vào phần lưu trữ của chính ứng dụng, còn role Lambda execution nhận managed policy thi hành cơ bản cộng thêm một `s3:PutObject` duy nhất trên tiền tố exports. ARN của resource được nêu tên, không thừa hưởng từ cả tài khoản. `resources: ['*']` chỉ còn sống trong đúng hai statement, cả hai đều thuộc role execution, và cả hai đều vì API tương ứng không có resource nào để thu hẹp: `ecr:GetAuthorizationToken` và cặp lệnh ghi CloudWatch Logs. Việc nêu được điều đó trong một câu chính là mục đích của cách viết dài dòng này.

* Có một điểm cần chỉnh lại: `cdk/README.md` xếp `secretsmanager:GetSecretValue` vào role ECS execution, nhưng trong `iam.ts` không có statement nào như vậy. Quyền đó được cấp ở chỗ khác, dưới dạng `lambda.appSecret.grantRead(ecsTaskExecutionRole)` trong `cdk/lib/stack.ts`. Bản thân secret được tạo trong `cdk/lib/lambda.ts`, và bên duy nhất đọc nó lúc chạy là container `App` trên ECS; Lambda nhân đôi cùng những giá trị đó thành biến môi trường dạng văn bản thuần và không hề gọi Secrets Manager. Vậy tài liệu đúng về hiệu lực nhưng sai về vị trí, và code là thứ tôi tin.

* TLS và DNS được chia qua ba tệp một cách có chủ ý, và `route53.ts` là tệp nhỏ nhất trong số đó: nó nhập hosted zone bằng `fromHostedZoneAttributes` và yêu cầu một `acm.Certificate` ký tự đại diện được xác thực bằng DNS. Nó không tạo bản ghi nào cả. Tên `api` là một alias được tạo cạnh custom domain của API Gateway trong `apigw.ts`, tên `ws` là một alias trỏ tới load balancer được tạo trong `ecs.ts`, còn tên gốc thuộc hoàn toàn về Amplify. Việc nhập zone thay vì tra cứu nó quan trọng hơn vẻ ngoài của nó: `fromHostedZoneAttributes` được giải quyết ngay lúc synth, nên `cdk synth` chạy được mà không cần credential AWS, và đó chính là điều cho phép các test hợp đồng chạy trong CI trên một job không giữ role nào.

* Load balancer được cấu hình cho những kết nối vốn phải sống lâu. `idle_timeout.timeout_seconds` là 3600 và đặt trên chính load balancer, vì một WebSocket đang tải các cập nhật canvas hoàn toàn có thể im lặng lâu hơn mức mặc định 60 giây, và khi đó ALB sẽ đóng nó ngay dưới chân client. Ban đầu tôi đặt thuộc tính ấy trên target group, nơi nó không có tác dụng gì, và dòng chú thích ghi lại lần chuyển vẫn còn trong `ecs.ts` như một lời nhắc rằng một thuộc tính được nhận mà không báo lỗi chưa phải là một thuộc tính đã có hiệu lực. `deregistration_delay.timeout_seconds` là 30 trên target group, nên một task bị thay thế sẽ rút kết nối dần chứ không cắt đứt các socket đang mở. HTTP trên cổng 80 tồn tại chỉ để phát ra một lệnh chuyển hướng vĩnh viễn sang 443.

* Amplify phục vụ frontend mà không kết nối với repository nào. App không có `sourceCodeProvider` và cả app lẫn branch đều không có `environmentVariables`: CI build frontend, nén `dist/` lại, rồi tải lên như một asset, còn các endpoint API và WebSocket được nướng sẵn vào lúc build chứ không tiêm vào lúc chạy. Domain gốc được gắn bằng `addDomain` cùng `mapRoot`, `enableAutoSubdomain` giữ nguyên false, và Amplify giữ chứng chỉ riêng của nó. Chú thích trong `amplify.ts` giải thích vì sao tôi không khai báo thêm các bản ghi DNS đó trong CDK: Amplify có thể tạo chúng trước, và stack sau đó sẽ thất bại với lỗi bản ghi đã tồn tại.

* `npm test` trong package `cdk` là một dây ba chặng: `tsc`, rồi `cdk synth --no-strict`, rồi Jest trên bảy tệp test được nêu tên tường minh bằng `--runTestsByPath`. Chúng kiểm tra trực tiếp template `AwsplaceStack` đã synth trên đĩa chứ không giả lập AWS, nên chúng bắt được độ lệch giữa ý định và template. Có hai điều về chúng đáng nói cho chính xác. Cái mà mọi người gọi là "bảy test hợp đồng" là bảy *tệp*, không phải bảy trường hợp; các tệp đó cộng lại chứa nhiều trường hợp hơn thế đáng kể. Và độ phủ của chúng không đều: các test Amplify có khẳng định stack không phát ra CloudFront distribution nào và không phát ra bản ghi DNS Amplify nào, các test hợp đồng triển khai chạy lại synth với biến môi trường bị sửa để chứng minh một image tag sai bị chặn trước khi triển khai, nhưng không có test nào trong bộ này khẳng định `natGateways: 0`, mức idle timeout 3600 giây, các statement IAM, hay chứng chỉ ký tự đại diện. Bốn điều đó dựa trên việc soát code chứ không dựa trên test, và khoảng trống ấy là trạng thái trung thực của bộ test ở cuối tuần này.
