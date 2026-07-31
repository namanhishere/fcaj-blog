---
title: "Quy trình Huỷ Stack"
date: 2024-01-01
weight: 2
chapter: false
pre: " <b> 5.9.2. </b> "
---

Việc huỷ stack trong awsplace tuân theo các quy trình được ghi chép và kiểm thử. Dự án phân biệt ba ngữ cảnh huỷ: dỡ bỏ staging stack (an toàn, định kỳ), dỡ bỏ application stack (xử lý tài nguyên được giữ lại), và dọn dẹp stack bị kẹt trước khi triển khai (được tự động hoá bởi script CI/CD). Mỗi ngữ cảnh được trình bày dưới đây.

---

#### 1. Huỷ Staging Stack

Nguồn: **docs/raftdb/staging-runbook.md** — §Destroy staging

RaftDB staging stack được thiết kế để tạo và huỷ lặp lại phục vụ các đợt diễn tập qualification. Runbook cung cấp quy trình chính xác:

```bash
export ENABLE_RAFTDB=true
export RAFTDB_RESTORE_FROM_S3=false
npx cdk destroy RaftDbStagingStack --force
```

Các điểm quan trọng từ quy trình:

- **ENABLE_RAFTDB** phải giữ là **true** và **RAFTDB_RESTORE_FROM_S3** phải là **false** — nếu không conditional stack sẽ không tồn tại trong CDK application và lệnh destroy sẽ thất bại.
- Cờ **--force** bỏ qua lời nhắc xác nhận tương tác, làm cho lệnh phù hợp để viết script nhưng nguy hiểm cho production — nó chỉ được dùng cho staging stack.
- Sau khi huỷ, xác minh rằng **AwsplaceStack** và ECR repository của nó vẫn nguyên vẹn. Staging stack chỉ import tên repository dùng chung từ application stack; việc huỷ nó không được lan truyền.

Runbook cảnh báo rõ ràng rằng EFS filesystem đã mã hoá và S3 bucket có versioning được giữ lại sau cdk destroy do chính sách **RETAIN** của chúng. Những tài nguyên được giữ lại này yêu cầu quy trình dọn dẹp riêng biệt được trình bày chi tiết trong phần 5.8.3.

---

#### 2. Huỷ Application Stack

Việc huỷ application stack (**AwsplaceStack**) yêu cầu cẩn trọng hơn vì nó chứa ECR repository, Secrets Manager secret, và các S3 bucket được import. Mã CDK trong mã hạ tầng ghi lại quy trình:

```typescript
// CI publishes before the application stack is recreated, so the registry
// must survive `cdk destroy` and be auto-imported on the next deployment.
repository.applyRemovalPolicy(RemovalPolicy.RETAIN);
```

Quá trình triển khai sử dụng **--import-existing-resources** để xử lý các tài nguyên được giữ lại khi tạo lại:

```yaml
- name: CDK deploy
  run: |
    cd cdk
    npm ci && npm run build
    npx cdk deploy --require-approval never --no-strict --all --import-existing-resources
```

Cờ **--import-existing-resources** yêu cầu CDK tìm kiếm các tài nguyên hiện có với physical name khớp (như ECR repository **awsplace-ecs**) và nhận chúng vào stack mới thay vì cố gắng tạo bản sao. Điều này được xác thực bởi test **GitLab and GitHub publish and deploy through the shared ECR contract** trong **deployment-contract.test.cjs**.

Đối với việc dỡ bỏ toàn bộ application stack:

1. Huỷ stack bình thường: **npx cdk destroy AwsplaceStack**
2. Xác minh tài nguyên được giữ lại: ECR repository, Secrets Manager secret, và S3 bucket được import vẫn tồn tại.
3. Nếu tạo lại, triển khai lại với **--import-existing-resources** để tái nhận tài nguyên được giữ lại.

---

#### 3. Dọn dẹp Stack Bị Kẹt Trước Triển khai

File: **scripts/prepare-cloudformation-deploy.sh**

Trước mỗi lần triển khai, CI/CD pipeline chạy script này để xử lý các CloudFormation stack bị kẹt trong trạng thái lỗi. Script được kiểm thử bởi **deploy-config.test.cjs** với 7 kịch bản test riêng biệt.

Ma trận quyết định của script:

| Trạng thái Stack | Hành động | Lý do |
|---|---|---|
| **CREATE_COMPLETE**, **UPDATE_COMPLETE** | Tiến hành bình thường | Stack khoẻ mạnh; CDK có thể cập nhật tại chỗ |
| **CREATE_FAILED**, **ROLLBACK_COMPLETE**, **ROLLBACK_FAILED**, **DELETE_FAILED** | Tự động xoá stack | Không có đợt triển khai thành công nào để bảo tồn; xoá để CDK tạo lại từ đầu |
| **DELETE_IN_PROGRESS** | Chờ xoá hoàn tất | Một tiến trình khác đang dọn dẹp; chờ thay vì xung đột |
| **UPDATE_ROLLBACK_FAILED** | **Từ chối xoá** | Đã tồn tại một đợt triển khai ổn định trước đó; xoá tự động sẽ phá huỷ hạ tầng production |
| ***_IN_PROGRESS** | Từ chối và thoát | Một thao tác CloudFormation đang chạy; thao tác đồng thời gây xung đột |

Trạng thái **UPDATE_ROLLBACK_FAILED** là trường hợp an toàn quan trọng. Script từ chối tự động xoá vì trạng thái này có nghĩa là một đợt triển khai ổn định đang tồn tại nhưng một lần cập nhật sau đó đã thất bại. Xoá tự động trong trạng thái này sẽ phá huỷ hạ tầng production. Cần can thiệp thủ công.

Logic xoá bao gồm cơ chế thử lại cho trạng thái **DELETE_FAILED**:

```bash
delete_incomplete_stack() {
  for attempt in 1 2; do
    echo "Deleting incomplete CloudFormation stack $stack_name (attempt $attempt/2)"
    aws cloudformation delete-stack --stack-name "$stack_name" "${region_args[@]}"

    if aws cloudformation wait stack-delete-complete \
      --stack-name "$stack_name" "${region_args[@]}"; then
      echo "Incomplete CloudFormation stack $stack_name was deleted"
      return 0
    fi

    current_status="$(describe_stack_status 2>/dev/null || true)"
    if [[ "$current_status" != "DELETE_FAILED" ]]; then
      echo "ERROR: deletion of $stack_name stopped in unexpected state: ${current_status:-unknown}" >&2
      return 1
    fi
  done

  echo "ERROR: $stack_name is still DELETE_FAILED after two attempts" >&2
  return 1
}
```

Các Jest test cho script này bao phủ mọi nhánh mã:

| Test Case | Trạng thái Stack | Hành vi mong đợi |
|---|---|---|
| Stack khoẻ mạnh | CREATE_COMPLETE | Giữ nguyên stack |
| Tạo ban đầu thất bại | ROLLBACK_FAILED | Xoá stack và chờ dọn dẹp |
| Stack mới | Không tồn tại | Cho phép tạo mới |
| Cập nhật thất bại với trạng thái ổn định trước đó | UPDATE_ROLLBACK_FAILED | Từ chối tự động xoá |

---

#### 4. Vòng đời Artifact CI/CD

CI/CD artifact (test log, báo cáo scan, publication evidence) được quản lý riêng biệt với tài nguyên CloudFormation:

| Artifact | Thời gian lưu | Cơ chế dọn dẹp |
|---|---|---|
| GitHub Actions run log | 90 ngày (mặc định) | Tự động hết hạn bởi GitHub |
| RaftDB image publication evidence | 90 ngày (rõ ràng) | Workflow artifact với retention-days: 90 |
| Trivy vulnerability scan report | 90 ngày (rõ ràng) | Workflow artifact với retention-days: 90 |
| ECR image vượt quá 10 image | Tự động | Lifecycle rule |
| S3 non-current snapshot version | 35 ngày | Lifecycle rule |

Thời gian lưu artifact 90 ngày phù hợp với yêu cầu chain-of-custody của RaftDB: publication evidence phải có sẵn để kiểm toán trong toàn bộ rollback window (7 ngày sau read cutover) cộng với biên độ hào phóng.

<!-- 📸 HƯỚNG DẪN HÌNH ẢNH:
Gợi ý chụp ảnh 1: Chạy cdk destroy RaftDbStagingStack --force trong terminal.
Chụp đầu ra hiển thị tài nguyên CloudFormation đang bị xoá và xác nhận cuối cùng.
Lưu tại: static/images/5.8/cdk-destroy-staging.png

Gợi ý chụp ảnh 2: Mở CloudFormation console trong kịch bản stack bị kẹt (ROLLBACK_FAILED).
Chụp stack events hiển thị lỗi và sau đó là xoá thành công được kích hoạt bởi prepare-cloudformation-deploy.sh.
Lưu tại: static/images/5.8/stuck-stack-cleanup.png
-->
