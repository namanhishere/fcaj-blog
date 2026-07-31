---
title: "Thiết kế Chính sách Xoá Tài nguyên"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 5.9.1. </b> "
---

Mỗi tài nguyên có trạng thái trong mã nguồn CDK của awsplace đều mang một **RemovalPolicy** rõ ràng — hoặc **RETAIN** (tồn tại sau khi xoá stack) hoặc **DESTROY** (bị xoá cùng stack). Không có tài nguyên nào bị bỏ mặc cho giá trị mặc định của CloudFormation. Những lựa chọn này được thực thi bởi các Jest contract test trong **raftdb.test.cjs** và **deployment-contract.test.cjs**, với assertion rằng các tài nguyên production quan trọng — đặc biệt là ECR repository — mang chính sách chính xác.

#### Danh sách chính sách xoá

| Tài nguyên | Stack | Chính sách | File nguồn | Lý do |
|---|---|---|---|---|
| ECR Repository (awsplace-ecs) | AwsplaceStack | **RETAIN** | Infrastructure | CI publish image trước khi tạo lại stack; registry phải tồn tại sau cdk destroy |
| RaftDB staging snapshot bucket | RaftDbStagingStack | **RETAIN** | Infrastructure | Dữ liệu staging snapshot và qualification evidence phải được duy trì qua các lần dỡ bỏ staging |
| RaftDB staging EFS | RaftDbStagingStack | **RETAIN** | Infrastructure | Dữ liệu WAL bền vững được cố ý giữ lại; dọn dẹp là quy trình huỷ riêng biệt |
| RaftDB application snapshot bucket | AwsplaceStack | **DESTROY** | Infrastructure | Production sidecar snapshot là cục bộ; bucket được dùng riêng cho sidecar và bị xoá với autoDeleteObjects |
| RaftDB application EFS | AwsplaceStack | **DESTROY** | Infrastructure | EFS volume của production sidecar là tạm thời — dữ liệu nằm trong DynamoDB; không cần giữ lại |
| Secrets Manager secret | AwsplaceStack | **RETAIN** | Infrastructure | Application secret phải tồn tại sau khi tạo lại stack để tránh phải nhập lại thủ công |

---

#### 1. ECR Repository: RETAIN với Lifecycle

Hàm: **createEcr**

ECR repository là tài nguyên được giữ lại quan trọng nhất. Lý do được ghi lại trong mã nguồn:

```typescript
// CI publishes before the application stack is recreated, so the registry
// must survive `cdk destroy` and be auto-imported on the next deployment.
repository.applyRemovalPolicy(RemovalPolicy.RETAIN);
```

Quy trình triển khai phụ thuộc vào hành vi này:

1. CI build và push Docker image lên repository **awsplace-ecs** với tag bất biến.
2. Đợt triển khai CDK tham chiếu đến cùng repository đó theo tên thông qua **Fn.importValue**.
3. Nếu stack bị huỷ và tạo lại, stack mới sẽ tái nhập (re-import) repository hiện có theo tên vật lý của nó.

Repository cũng có lifecycle rule giới hạn số lượng image được giữ:

```typescript
repository.addLifecycleRule({
  maxImageCount: 10,
  rulePriority: 1,
  tagStatus: ecr.TagStatus.ANY,
});
```

Quy tắc này giữ lại 10 image gần nhất (cả tagged và untagged) và tự động hết hạn các image cũ hơn, ngăn chặn tăng trưởng lưu trữ không giới hạn. Các RaftDB image có tiền tố **raftdb-*** còn được bảo vệ thêm bởi image-tag immutability exclusion filter, nghĩa là chúng không thể bị ghi đè nhưng vẫn chịu sự kiểm soát của lifecycle count.

Jest test **application ECR repository has a stable retained physical name** trong **deployment-contract.test.cjs** xác thực:

```javascript
test('application ECR repository has a stable retained physical name', () => {
  const repositories = resourcesByType(defaultTemplate, 'AWS::ECR::Repository');
  expect(repositories).toHaveLength(1);
  expect(repository.Properties).toEqual(expect.objectContaining({
    RepositoryName: 'awsplace-ecs',
    ImageScanningConfiguration: { ScanOnPush: true },
    ImageTagMutability: 'MUTABLE_WITH_EXCLUSION',
  }));
  expect(repository.DeletionPolicy).toBe('Retain');
});
```

---

#### 2. Tài nguyên RaftDB Staging: RETAIN

Hàm: **createRaftDbCluster**

Snapshot bucket và EFS filesystem của staging đều được đặt là **RETAIN**:

```typescript
// Snapshot bucket
const snapshotBucket = new s3.Bucket(scope, 'RaftDbSnapshotBucket', {
  versioned: true,
  encryption: s3.BucketEncryption.KMS_MANAGED,
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
  enforceSSL: true,
  removalPolicy: RemovalPolicy.RETAIN,
  lifecycleRules: [{
    id: 'RetainCurrentSnapshotsAndPreviousPointerVersions',
    enabled: true,
    noncurrentVersionExpiration: Duration.days(35),
    abortIncompleteMultipartUploadAfter: Duration.days(1),
  }],
});

// EFS filesystem
const fileSystem = new efs.FileSystem(scope, 'RaftDbFileSystem', {
  vpc,
  vpcSubnets: isolatedSubnets,
  encrypted: true,
  removalPolicy: RemovalPolicy.RETAIN,
});
```

Staging runbook (**docs/raftdb/staging-runbook.md**) tuyên bố rõ ràng rằng việc tạo lại stack sẽ tạo ra tài nguyên mới — nó không tự động gắn lại các tài nguyên được giữ lại. Điều này có nghĩa là:

- Huỷ và tạo lại **RaftDbStagingStack** sẽ để lại snapshot bucket và EFS filesystem cũ ở trạng thái mồ côi.
- Stack mới tạo ra tài nguyên mới với physical ID mới.
- Các tài nguyên mồ côi yêu cầu một quy trình dọn dẹp riêng biệt, được ghi chép lại (được đề cập trong 5.8.3).

Jest test **raftdb snapshots use a retained private versioned bucket with lifecycle** trong **raftdb.test.cjs** xác thực cấu hình này.

---

#### 3. Tài nguyên RaftDB Phía Ứng dụng: DESTROY

Hàm: **createRaftDbApplicationStorage**

Trái ngược với staging stack, các tài nguyên RaftDB sidecar của production application sử dụng **DESTROY**:

```typescript
// Application snapshot bucket
const snapshotBucket = new s3.Bucket(scope, 'RaftDbApplicationSnapshots', {
  versioned: true,
  encryption: s3.BucketEncryption.S3_MANAGED,
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
  enforceSSL: true,
  removalPolicy: RemovalPolicy.DESTROY,
  autoDeleteObjects: true,
  lifecycleRules: [{
    noncurrentVersionExpiration: Duration.days(35),
    abortIncompleteMultipartUploadAfter: Duration.days(1),
  }],
});

// Application EFS
const fileSystem = new efs.FileSystem(scope, 'RaftDbApplicationFileSystem', {
  vpc: props.vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
  encrypted: true,
  removalPolicy: RemovalPolicy.DESTROY,
});
```

Điểm khác biệt chính là **autoDeleteObjects: true** trên application snapshot bucket. Thiết lập này triển khai một custom resource (Lambda function) để làm rỗng bucket trước khi CloudFormation xoá nó — cần thiết vì CloudFormation từ chối xoá S3 bucket không rỗng. Staging bucket cố ý bỏ qua thiết lập này vì dữ liệu staging snapshot được coi là qualification evidence phải tồn tại sau khi dỡ bỏ stack.

---

#### 4. Secrets Manager: RETAIN

Hàm: **createLambda**

Application secret (Discord OAuth credentials, session secret) được giữ lại:

```typescript
appSecret.applyRemovalPolicy(RemovalPolicy.RETAIN);
```

Điều này ngăn việc tạo lại stack làm mất secret và yêu cầu nhập lại thủ công. Khi tạo lại stack, mã CDK sử dụng **--import-existing-resources** để nhận lại secret đã được giữ lại vào stack mới.

---

#### Tóm tắt quyết định chính sách

| Câu hỏi | Trả lời | Áp dụng cho |
|---|---|---|
| Tài nguyên có chứa dữ liệu phải tồn tại sau khi tạo lại stack không? | **RETAIN** | ECR, staging snapshot, staging EFS, Secrets Manager |
| Dữ liệu của tài nguyên có thể tái tạo từ nguồn khác không? | **DESTROY** | Application EFS, application snapshot bucket |
| Việc vô tình xoá có thể gây mất dữ liệu không có đường khôi phục không? | **RETAIN** + không autoDeleteObjects | Staging snapshot bucket |
| Tài nguyên an toàn để xoá nhưng sẽ chặn xoá stack nếu không rỗng? | **DESTROY** + autoDeleteObjects | Application snapshot bucket |

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh: Trong CloudFormation console, chọn một tài nguyên từ AwsplaceStack (ví dụ: ECR repository).
Chụp chi tiết tài nguyên hiển thị trường DeletionPolicy: Retain.
Lưu tại: static/images/5.8/retain-policy-ecr.png
-->
