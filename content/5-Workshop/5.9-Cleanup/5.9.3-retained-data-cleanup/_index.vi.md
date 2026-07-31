---
title: "Dọn dẹp Dữ liệu Được Giữ lại"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 5.9.3. </b> "
---

Khi một stack bị huỷ với chính sách **RETAIN**, các tài nguyên CloudFormation bị loại bỏ khỏi stack nhưng các tài nguyên AWS bên dưới — S3 bucket, EFS filesystem, Secrets Manager secret, ECR repository — vẫn tồn tại. Dự án awsplace coi việc dọn dẹp những tài nguyên được giữ lại này là một thao tác thủ công, riêng biệt, được kiểm soát bởi phê duyệt. Staging runbook (**docs/raftdb/staging-runbook.md**) định nghĩa quy trình có thẩm quyền.

---

#### 1. Tại sao Dọn dẹp Dữ liệu Được Giữ lại Lại Tách biệt

Sự tách biệt giữa huỷ stack và huỷ dữ liệu tồn tại vì ba lý do:

1. **An toàn**: Một lệnh **cdk destroy** định kỳ trong quá trình diễn tập qualification hoặc phát triển không bao giờ được lan truyền thành mất dữ liệu vĩnh viễn. Các tài nguyên được giữ lại hoạt động như một lưới an toàn.
2. **Khả năng kiểm toán**: Dọn dẹp dữ liệu được giữ lại yêu cầu phê duyệt huỷ dữ liệu bằng văn bản và đánh giá lưu giữ. Điều này tạo ra một dấu vết giấy tờ rõ ràng cho mục đích tuân thủ.
3. **Tính chủ đích**: Việc biến dọn dẹp thành thủ công và được kiểm soát bởi phê duyệt ngăn chặn tai nạn "mũm mĩm ngón tay" (fat-finger). Không script nào có thể vô tình chạy dọn dẹp — con người phải xác minh định danh, nhận phê duyệt, và thực thi từng bước.

Staging runbook tóm tắt ngắn gọn:

> Cleanup is a separate destructive operation requiring written data-destruction approval and a retention review. Match the recorded filesystem and bucket IDs; never use account-wide name matching. This runbook deliberately provides no blanket cleanup command.

---

#### 2. Dọn dẹp Tài nguyên Được Giữ lại của Staging

Nguồn: **docs/raftdb/staging-runbook.md** — §Retained data cleanup

Sau khi huỷ **RaftDbStagingStack**, các tài nguyên sau vẫn tồn tại và phải được dọn dẹp thủ công:

| Tài nguyên | Hành vi giữ lại | Độ phức tạp dọn dẹp |
|---|---|---|
| RaftDB snapshot bucket (S3, versioned, mã hoá KMS-managed) | Tất cả object version và delete marker tồn tại | Cao — phải làm rỗng mọi version và delete marker trước khi xoá bucket |
| RaftDB EFS filesystem (đã mã hoá) | Filesystem tồn tại; mount target có thể còn sót lại | Trung bình — phải xoá access point và mount target trước khi xoá filesystem |

#### Quy trình dọn dẹp từng bước:

#### a) Dọn dẹp S3 Snapshot Bucket

Staging snapshot bucket có **versioning** với mã hoá **KMS_MANAGED**. CloudFormation từ chối xoá bucket không rỗng, và với versioning được bật, "làm rỗng" yêu cầu xoá từng object version và từng delete marker.

```bash
# 1. Ghi lại tên bucket trước khi huỷ stack
BUCKET=$(jq -r '.RaftDbStagingStack.RaftDbSnapshotBucketName' \
  cdk.out/raftdb-staging-outputs.json)

# 2. Xác minh định danh bucket — không bao giờ khớp theo mẫu tên
aws s3api list-object-versions --bucket "$BUCKET" --max-items 1

# 3. Làm rỗng tất cả object version (đây là bước huỷ)
aws s3api delete-objects --bucket "$BUCKET" \
  --delete "$(aws s3api list-object-versions \
    --bucket "$BUCKET" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json)"

# 4. Làm rỗng tất cả delete marker
aws s3api delete-objects --bucket "$BUCKET" \
  --delete "$(aws s3api list-object-versions \
    --bucket "$BUCKET" \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json)"

# 5. Xoá bucket khi đã rỗng
aws s3api delete-bucket --bucket "$BUCKET"
```

Lifecycle rule được cấu hình trong mã hạ tầng (35 ngày hết hạn noncurrent version) cung cấp dọn dẹp tự động cuối cùng cho các version cũ, nhưng việc dọn dẹp hoàn chỉnh ngay lập tức như trên là cách duy nhất để loại bỏ hoàn toàn bucket theo yêu cầu.

#### b) Dọn dẹp EFS Filesystem

Dọn dẹp EFS yêu cầu thứ tự cụ thể: access point và mount target phải được xoá trước khi bản thân filesystem có thể bị xoá.

```bash
# 1. Ghi lại filesystem ID trước khi huỷ stack
FILESYSTEM=$(jq -r '.RaftDbStagingStack.RaftDbFileSystemId' \
  cdk.out/raftdb-staging-outputs.json)

# 2. Liệt kê và xoá tất cả access point
aws efs describe-access-points --file-system-id "$FILESYSTEM" \
  --query 'AccessPoints[].AccessPointId' --output text | while read ap_id; do
  if [ -n "$ap_id" ]; then
    aws efs delete-access-point --access-point-id "$ap_id"
  fi
done

# 3. Liệt kê và xoá tất cả mount target
aws efs describe-mount-targets --file-system-id "$FILESYSTEM" \
  --query 'MountTargets[].MountTargetId' --output text | while read mt_id; do
  if [ -n "$mt_id" ]; then
    aws efs delete-mount-target --mount-target-id "$mt_id"
  fi
done

# 4. Chờ mount target hoàn tất xoá
aws efs describe-mount-targets --file-system-id "$FILESYSTEM" \
  --query 'length(MountTargets)' | while read count; do
  if [ "$count" -eq 0 ]; then break; fi
  sleep 10
done

# 5. Xoá filesystem
aws efs delete-file-system --file-system-id "$FILESYSTEM"
```

Mount target tồn tại trong mỗi Availability Zone nơi filesystem được mount. Tất cả chúng phải ở trạng thái **deleted** trước khi filesystem có thể bị xoá.

---

#### 3. Tài nguyên Production Được Giữ lại

Tài nguyên production được giữ lại (ECR repository, Secrets Manager secret, S3 bucket được import) thường **không** được dọn dẹp. Chúng được thiết kế để tồn tại vô thời hạn:

| Tài nguyên | Yêu cầu dọn dẹp | Hành động điển hình |
|---|---|---|
| ECR Repository (awsplace-ecs) | Chỉ khi dự án bị ngừng hoàn toàn | Xoá sau khi xác nhận không có deployment đang hoạt động nào phụ thuộc vào image của nó |
| Secrets Manager secret | Chỉ khi ứng dụng bị ngừng hoàn toàn | Lên lịch xoá với recovery window (mặc định 30 ngày) |
| S3 bucket được import (canvas, exports) | Không bao giờ qua CDK | Chúng được import (không được tạo) bởi stack; phải được quản lý độc lập |

Vì các S3 bucket được import được tạo bên ngoài CDK (qua **s3.Bucket.fromBucketName** trong mã hạ tầng), CDK không có thẩm quyền xoá chúng — chúng tự động tồn tại sau khi huỷ stack.

---

#### 4. Dọn dẹp ECR Repository (Ngừng hoạt động)

Nếu toàn bộ dự án bị ngừng hoạt động, ECR repository yêu cầu xoá thủ công:

```bash
# 1. Xác minh không có ECS task đang hoạt động tham chiếu image trong repository này
aws ecs list-tasks --cluster <cluster-name> --desired-status RUNNING

# 2. Xoá tất cả image (bắt buộc trước khi xoá repository)
aws ecr batch-delete-image \
  --repository-name awsplace-ecs \
  --image-ids "$(aws ecr list-images \
    --repository-name awsplace-ecs \
    --query 'imageIds[*]' --output json)"

# 3. Xoá repository
aws ecr delete-repository --repository-name awsplace-ecs --force
```

Cờ **--force** trên delete-repository là bắt buộc vì repository có thể vẫn chứa image ngay cả sau batch-delete-image. Lifecycle rule (tối đa 10 image) giữ cho số lượng image có thể quản lý được cho thao tác này.

---

#### 5. Phê duyệt Dọn dẹp và Lưu trữ Hồ sơ

Staging runbook yêu cầu ghi chép lại mọi thao tác dọn dẹp:

- **Phê duyệt huỷ dữ liệu bằng văn bản** trước khi bất kỳ lệnh dọn dẹp nào được thực thi.
- **Ghi lại mọi định danh đã xoá**: tên bucket, filesystem ID, access point ID, mount target ID.
- **Đánh giá lưu giữ**: xác nhận rằng không còn cần qualification evidence hoặc audit trail nào trước khi tiến hành.
- **Không bao giờ sử dụng khớp tên toàn tài khoản**: luôn khớp tài nguyên theo ID chính xác đã ghi lại để tránh vô tình xoá tài nguyên có tên tương tự trong stack khác.

Cách tiếp cận này phù hợp với yêu cầu của capacity runbook rằng service owner phải phê duyệt rõ ràng việc ngừng hoạt động tài nguyên bằng văn bản.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh 1: Trong S3 console, mở RaftDB snapshot bucket sau khi huỷ stack.
Chụp bucket hiển thị object version vẫn còn mặc dù stack đã bị huỷ.
Lưu tại: static/images/5.8/retained-s3-bucket.png

Gợi ý chụp ảnh 2: Trong EFS console, hiển thị filesystem vẫn tồn tại sau khi huỷ stack.
Chụp chi tiết filesystem hiển thị chỉ báo "Orphaned" hoặc "Not managed by CloudFormation".
Lưu tại: static/images/5.8/retained-efs-filesystem.png
-->
