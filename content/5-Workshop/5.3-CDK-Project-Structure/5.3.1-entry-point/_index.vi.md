---
title : "Điểm vào & Kết hợp Stack"
date : 2024-01-01
weight : 1
chapter : false
pre : " <b> 5.3.1 </b> "
---

#### Điểm vào

Ứng dụng CDK bắt đầu tại một file điểm vào duy nhất tạo CDK **App**, phân tích các biến môi trường cho cấu hình triển khai, khởi tạo **AwsplaceStack** chính và có điều kiện thêm **RaftDbStagingStack**.

```typescript
const app = new App();
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'ap-southeast-1',
};

const mainStack = new AwsplaceStack(app, 'AwsplaceStack', {
  env,
  domainName: process.env.DOMAIN_NAME || 'place.namanhishere.com',
  hostedZoneId: parseHostedZoneId(process.env.HOSTED_ZONE_ID),
  ecsImageTag: parseEcsImageTag(process.env.ECS_IMAGE_TAG),
  raftDbImageDigest: parseRaftDbImageDigest(process.env.RAFTDB_IMAGE_DIGEST),
});

if (process.env.ENABLE_RAFTDB === 'true') {
  const stagingStack = new RaftDbStagingStack(app, 'RaftDbStagingStack', { ... });
  stagingStack.addDependency(mainStack,
    'RaftDB staging nhập ECR repository chung');
}

app.synth();
```

**Trách nhiệm chính của điểm vào:**

1. **Cấu hình môi trường**: Đặt tài khoản AWS và khu vực. Khu vực mặc định là **ap-southeast-1** (Singapore).

2. **Hàm xác thực đầu vào**: Một số hàm phân tích xác thực đầu vào triển khai trước khi chúng đến stack:
   - **parseHostedZoneId()** — xác thực định dạng Route 53 hosted zone ID (**Z[A-Z0-9]+**), cung cấp placeholder xác định cho tổng hợp không cần thông tin xác thực
   - **parseEcsImageTag()** — xác thực định dạng tag Docker image (tối đa 128 ký tự chữ-số, dấu chấm, dấu gạch dưới, dấu gạch ngang)
   - **parseRaftDbImageDigest()** — xác thực định dạng SHA256 digest (**sha256:\<64 ký tự hex\>**), cung cấp placeholder cho tổng hợp
   - **parseNodeCount()** — chỉ cho phép 1 hoặc 3 node RaftDB
   - **parseRestoreFromS3()** — chỉ cho phép **true**/**false**

3. **Stack staging có điều kiện**: **RaftDbStagingStack** chỉ được tạo khi **ENABLE_RAFTDB=true**. Nó phụ thuộc vào stack chính vì chia sẻ ECR repository thông qua **Fn.importValue**.

![CDK Entry Point Flow](/images/5-Workshop/5.3-CDK-Project-Structure/entry-point-flow.png)

#### Stack Chính

Lớp **AwsplaceStack** là bộ điều phối chính. Nó mở rộng lớp CDK **Stack** và kết nối tất cả các module cơ sở hạ tầng theo một thứ tự phụ thuộc cụ thể.

**Thuộc tính khởi tạo (**AwsplaceStackProps**):**

| Thuộc tính | Kiểu | Mô tả |
|------------|------|-------|
| **domainName** | string | Tên miền tùy chỉnh (ví dụ: **place.namanhishere.com**) |
| **hostedZoneId** | string | Route 53 hosted zone ID |
| **ecsImageTag** | string | Tag image ứng dụng có phiên bản được CI xuất bản |
| **raftDbImageDigest** | string | Digest image RaftDB bất biến, đã được kiểm thử (SHA256) |

**Thứ tự tạo tài nguyên trong hàm khởi tạo:**

```
1. createVpc(this)                   → VPC với 2 AZ, public subnets
2. createDatabase(this)              → 4 bảng DynamoDB
3. createEcr(this)                   → ECR repository
4. createStorage(this, ...)          → Nhập S3 bucket (canvas + exports)
5. createIamRoles(this, ...)         → 3 IAM roles
6. createRaftDbApplicationStorage()  → EFS + S3 cho RaftDB
7. createRoute53AndCertificates()    → ACM wildcard cert
8. createLambda(this, ...)           → Lambda function + Secrets Manager
9. createApiGateway(this, ...)       → HTTP API v2
10. createAmplify(this, ...)         → Amplify Hosting
11. createEcs(this, ...)             → ECS Fargate + ALB
```

Thứ tự rất quan trọng: VPC đứng đầu vì mọi tài nguyên khác phụ thuộc vào nó. IAM roles được tạo sau database và storage vì chúng cần ARN bảng/bucket cho chính sách có phạm vi. ECS được tạo cuối cùng vì nó cần tham chiếu đến hầu như mọi tài nguyên khác.

![Stack Wiring Diagram](/images/5-Workshop/5.3-CDK-Project-Structure/stack-wiring.png)

**CloudFormation Outputs (18 tổng cộng):**

Stack xuất đầu ra cho mọi tài nguyên chính để pipeline CI/CD và script vận hành có thể tham chiếu mà không cần mã hóa cứng giá trị:

| Đầu ra | Giá trị |
|--------|--------|
| VpcId | VPC ID |
| EcsRepositoryUri | ECR repository URI |
| EcsRepositoryName | Tên ECR repository (được xuất cho tham chiếu chéo stack) |
| EcsClusterName | Tên ECS cluster |
| EcsServiceName | Tên ECS service |
| EcsTaskExecutionRoleArn | ARN role thực thi ECS |
| EcsTaskRoleArn | ARN role tác vụ ECS |
| LambdaExecutionRoleArn | ARN role thực thi Lambda |
| ApiFunctionArn | ARN hàm Lambda |
| AppSecretArn | ARN Secrets Manager secret |
| ConfigTableName | Tên bảng Config DynamoDB |
| BansTableName | Tên bảng Bans DynamoDB |
| MilestonesTableName | Tên bảng Milestones DynamoDB |
| HistoryTableName | Tên bảng History DynamoDB |
| CanvasBucketName | Tên bucket Canvas S3 |
| ExportsBucketName | Tên bucket Exports S3 |
| RaftDbFileSystemId | ID EFS filesystem RaftDB |
| RaftDbSnapshotBucketName | Tên bucket snapshot RaftDB S3 |
| AmplifyAppId | ID ứng dụng Amplify |
| AmplifyDefaultDomain | Tên miền mặc định Amplify |
| AmplifyBranchName | Tên nhánh production Amplify |

**Tham chiếu chéo stack:** Tên ECR repository được xuất để stack staging có thể nhập nó qua **Fn.importValue()**. Đây là cơ chế cho phép hai stack CloudFormation riêng biệt chia sẻ một ECR repository duy nhất.
