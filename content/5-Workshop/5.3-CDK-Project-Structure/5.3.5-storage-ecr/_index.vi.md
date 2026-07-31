---
title : "Lưu trữ: ECR & S3"
date : 2024-01-01
weight : 5
chapter : false
pre : " <b> 5.3.5 </b> "
---

#### ECR Repository

Module ECR (**createEcr**) tạo một **Elastic Container Registry** repository duy nhất tên là **awsplace-ecs**. Repository này lưu trữ cả image ứng dụng Go và image RaftDB.

```typescript
export function createEcr(scope: Construct): EcrOutput {
  const repository = new ecr.Repository(scope, 'ApplicationRepository', {
    repositoryName: 'awsplace-ecs',
    imageScanOnPush: true,
    imageTagMutability: ecr.TagMutability.MUTABLE_WITH_EXCLUSION,
    imageTagMutabilityExclusionFilters: [
      ecr.ImageTagMutabilityExclusionFilter.wildcard('raftdb-*'),
    ],
  });

  repository.applyRemovalPolicy(RemovalPolicy.RETAIN);

  repository.addLifecycleRule({
    maxImageCount: 10,
    rulePriority: 1,
    tagStatus: ecr.TagStatus.ANY,
  });

  return { repository };
}
```

**Đặc điểm chính:**

| Tính năng | Giá trị | Lý do |
|-----------|--------|-------|
| Tên repository | awsplace-ecs | Repository chung cho cả image App và RaftDB |
| Quét image | imageScanOnPush: true | Quét bảo mật trên mỗi lần push |
| Khả năng thay đổi tag | MUTABLE_WITH_EXCLUSION | Tag ứng dụng có thể bị ghi đè (ví dụ: tag dựa trên commit), nhưng tag raftdb-* là **bất biến** |
| Loại trừ tag RaftDB | Wildcard raftdb-* | Image RaftDB phải sử dụng tag bất biến để đảm bảo image đã kiểm thử là image được triển khai |
| Chính sách vòng đời | Giữ 10 image gần nhất | Ngăn tăng trưởng lưu trữ không giới hạn |
| Chính sách xóa | RETAIN | Tồn tại qua cdk destroy — CI xuất bản trước khi stack được tạo lại |

**Tại sao RemovalPolicy.RETAIN?** ECR repository phải tồn tại qua các chu kỳ cdk destroy. CI đẩy image trước khi stack ứng dụng được triển khai. Nếu repository bị xóa và tạo lại, tất cả các tham chiếu image hiện có sẽ bị hỏng. Với RETAIN, cdk destroy để repository (và image của nó) nguyên vẹn.

**Chuỗi lưu trữ image cho RaftDB:** Xây dựng không cần thông tin xác thực AWS → xuất artifact → xác minh danh tính → OIDC → push. Image RaftDB luôn được tham chiếu bằng SHA256 digest bất biến (không phải tag) trong định nghĩa task ECS.

#### Lưu trữ S3

Module lưu trữ (**createStorage**) **nhập** (không tạo) hai bucket S3 theo tên:

```typescript
export function createStorage(scope: Construct, props?: StorageProps): StorageOutput {
  const account = props?.account ?? '';

  const canvasBucket = s3.Bucket.fromBucketName(
    scope, 'ImportedCanvasBucket',
    `awsplace-canvas-${account}`
  );

  const exportsBucket = s3.Bucket.fromBucketName(
    scope, 'ImportedExportsBucket',
    `awsplace-exports-${account}`
  );

  return { canvasBucket, exportsBucket };
}
```

**Chi tiết chính — Mẫu Bucket.fromBucketName():** Các bucket không được tạo bởi CDK. Chúng được nhập theo tên. Điều này có nghĩa:
1. Bucket phải tồn tại **trước khi** triển khai.
2. Bucket tồn tại qua cdk destroy (chúng không được quản lý bởi stack).
3. Hậu tố ID tài khoản tạo tên duy nhất cho mỗi tài khoản AWS.

**Mục đích bucket:**

| Bucket | Mẫu đặt tên | Có phiên bản | Mục đích |
|--------|-------------|-------------|----------|
| Canvas | awsplace-canvas-{account} | Có | Canvas binary (canvas/canvas.bin), đóng gói nibble 4-bit, lên đến 32 MiB |
| Exports | awsplace-exports-{account} | Không | Xuất PNG từ export.py, phục vụ cho admin dashboard |

**Tại sao S3 cho canvas thay vì DynamoDB?** DynamoDB có giới hạn kích thước mục 400 KB. Canvas ở 4 bit mỗi pixel phát triển đến **32 MiB** ở kích thước tối đa (8000×8000). S3 không có giới hạn kích thước thực tế cho trường hợp sử dụng này và rẻ hơn cho lưu trữ nhị phân.

![Sơ đồ Kiến trúc Lưu trữ ECR & S3](/images/5-Workshop/5.3-CDK-Project-Structure/storage-architecture.png)

#### Lưu trữ Ứng dụng RaftDB

Module này tạo lớp lưu trữ bền vững cho RaftDB sidecar:

```typescript
export function createRaftDbApplicationStorage(
  scope: Construct,
  props: { vpc: ec2.Vpc; taskRole: iam.Role },
): RaftDbApplicationStorage {
  const snapshotBucket = new s3.Bucket(scope, 'RaftDbApplicationSnapshots', {
    versioned: true,
    encryption: s3.BucketEncryption.S3_MANAGED,
    blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
    enforceSSL: true,
    minimumTLSVersion: 1.2,
    removalPolicy: RemovalPolicy.DESTROY,
    autoDeleteObjects: true,
    lifecycleRules: [{
      noncurrentVersionExpiration: Duration.days(35),
      abortIncompleteMultipartUploadAfter: Duration.days(1),
    }],
  });

  const fileSystem = new efs.FileSystem(scope, 'RaftDbApplicationFileSystem', { ... });
  const accessPoint = fileSystem.addAccessPoint('ApplicationAccessPoint', { ... });
  ...
}
```

**Ba tài nguyên được tạo:**

| Tài nguyên | Mục đích | Cài đặt chính |
|------------|----------|---------------|
| **EFS FileSystem** | Lưu trữ WAL bền vững cho RaftDB | Mã hóa, điểm gắn kết public subnet |
| **EFS AccessPoint** | Thực thi người dùng/nhóm POSIX | UID/GID 10001:10001 (người dùng non-root RaftDB), quyền 0750 |
| **S3 Snapshot Bucket** | Snapshot RaftDB định kỳ | Có phiên bản, hết hạn phiên bản cũ 35 ngày, TLS 1.2 |

EFS access point rất quan trọng: nó thực thi rằng chỉ người dùng 10001:10001 (danh tính tiến trình RaftDB) mới có thể đọc/ghi dữ liệu WAL. Task role được cấp elasticfilesystem:ClientMount và elasticfilesystem:ClientWrite giới hạn trong ARN access point cụ thể này.
