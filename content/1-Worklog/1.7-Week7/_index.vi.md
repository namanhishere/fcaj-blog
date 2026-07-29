---
title: "Worklog Tuần 7"
date: 2026-07-27
weight: 7
chapter: false
pre: " <b> 1.7. </b> "
reportType: worklog
reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---

### Mục tiêu tuần 7:

* Đưa toàn bộ trình tự build, kiểm thử và triển khai vào GitLab tự quản thành một pipeline duy nhất, thay cho một tập câu lệnh tôi chạy tay.
* Loại bỏ hoàn toàn access key AWS dài hạn khỏi CI và thay bằng một session ngắn hạn lấy từ token OIDC mà GitLab sinh cho từng job.
* Biến image RaftDB thành thứ được thăng cấp, không phải một tag trỏ tới bất cứ thứ gì được push sau cùng: build và scan nó trong một job không có credential AWS, rồi để một job thứ hai publish chỉ sau khi đã chứng minh đó vẫn đúng image đó.

### Các công việc cần triển khai trong tuần này:

| Thứ | Công việc | Ngày bắt đầu | Ngày hoàn thành | Nguồn tài liệu |
| --- | --------- | ------------ | --------------- | -------------- |
| 2   | - Bố trí pipeline thành bốn stage: build-ci-image, test, build, deploy <br> - Build image runner dùng chung ở stage đầu để mọi job sau đều khởi đầu từ một toolchain, thay vì cài công cụ trong từng job <br> - **Viết Dockerfile.ci-utils trên node:24-bookworm với đúng những công cụ pipeline thực sự gọi:** <br>&emsp; + Go, ghim ở go1.25.0 <br>&emsp; + AWS CLI v2, aws-cdk, docker, git, jq, zip, unzip, curl <br> - Gắn tag kết quả là ci-utils theo commit SHA và theo main, rồi để các job sau pull tag main | 27/07/2026 | 27/07/2026 | <https://docs.gitlab.com/ee/ci/yaml/> <br> <https://docs.gitlab.com/ee/ci/docker/using_docker_build.html> |
| 3   | - Đăng ký GitLab instance làm IAM OIDC identity provider và viết điều kiện trust policy trên issuer cùng subject <br> - Khai báo id_tokens trong từng job cần AWS, một biến AWS_JWT_TOKEN với aud là https://git.namanhishere.com <br> - Đổi token qua aws sts assume-role-with-web-identity rồi tách kết quả thành ba biến credential chuẩn <br> - Giữ session ở 3600 giây và xác nhận không có access key hay secret AWS nào tồn tại dưới dạng biến CI ở bất cứ đâu | 28/07/2026 | 28/07/2026 | <https://docs.gitlab.com/ee/ci/cloud_services/aws/> <br> <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html> <br> <https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html> |
| 4   | - Viết job raftdb-image trong stage test và không cấp cho nó bất kỳ credential AWS nào, chỉ có DOCKER_HOST và DOCKER_TLS_CERTDIR <br> - Build image rồi chạy bốn bài kiểm thử hợp đồng trên nó: <br>&emsp; + raftdb/test/container_contract_test.sh <br>&emsp; + raftdb/test/qualification_runtime_contract_test.sh <br>&emsp; + raftdb/test/migration_runtime_contract_test.sh <br>&emsp; + raftdb/test/s3_runtime_contract_test.sh <br> - Cài Trivy 0.72.0 bằng cách xác thực tệp checksums của nó với một sha256 hardcode, rồi xác thực archive dựa trên tệp đó | 29/07/2026 | 29/07/2026 | <https://github.com/aquasecurity/trivy> <br> <https://docs.gitlab.com/ee/ci/docker/using_docker_build.html> |
| 5   | - Scan HIGH và CRITICAL bằng trivy image và để Trivy exit 0, nên quyết định đạt hay không là của tôi và được đưa ra trong jq <br> - **Tách hai cửa gác một cách có chủ ý:** <br>&emsp; + bất kỳ CRITICAL nào cũng làm job thất bại, không có ngoại lệ <br>&emsp; + bất kỳ HIGH nào cũng làm job thất bại, trừ khi RAFTDB_ACCEPT_HIGH_CVES đúng bằng commit SHA hiện tại <br> - Ghi lại docker image ID trước và sau khi scan, và cho thất bại nếu nó thay đổi <br> - Chuyển image sang bước sau dưới dạng tar đã gzip kèm raftdb-image-evidence.json mang theo commit, image ID và số lượng lỗ hổng đã scan | 30/07/2026 | 30/07/2026 | <https://github.com/aquasecurity/trivy> <br> <https://jqlang.github.io/jq/manual/> |
| 6   | - Viết publish-raftdb-image sao cho mọi phép kiểm tra diễn ra trước khi xin credential đầu tiên: commit trong evidence phải bằng commit của pipeline, và image ID nạp lên phải bằng image ID đã ghi <br> - Push tag bất biến raftdb- cộng commit SHA, rồi đọc digest về và yêu cầu nó khớp sha256 theo sau là 64 ký tự hex thường <br> - Xoá mọi bản sao cục bộ, pull image về theo digest, và chạy lại kiểm thử hợp đồng container cùng migration trên đúng phần dữ liệu đã pull <br> - Công bố digest cho job deploy bằng reports dotenv, và để deploy-to-aws đối chiếu giá trị đó với tệp evidence trước khi nhận role | 31/07/2026 | 31/07/2026 | <https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html> <br> <https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-pull-ecr-image.html> <br> <https://docs.gitlab.com/ee/ci/yaml/artifacts_reports.html> |

Phần loại bỏ khoá tĩnh rất ngắn. Mỗi job có credential đều xin GitLab một token đã ký, và audience chính là bản thân GitLab instance:

```yaml
# awsplace/.gitlab-ci.yml
id_tokens:
  AWS_JWT_TOKEN:
    aud: https://git.namanhishere.com
```

Token sau đó được đổi lấy một session hết hạn trong vòng một giờ:

```bash
CREDS=$(aws sts assume-role-with-web-identity \
  --role-arn "$AWS_ROLE_ARN" \
  --role-session-name "GitLabCI-${CI_PIPELINE_ID}" \
  --web-identity-token "$AWS_JWT_TOKEN" \
  --duration-seconds 3600 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
```

### Kết quả đạt được tuần 7:

* Pipeline gồm bốn stage và mười ba job, và thứ tự stage chính là lập luận: `build-ci-image` tạo ra một image runner, `test` chạy các phép kiểm tra Lambda, Go, CDK và image RaftDB, `build` đẩy artifact lên ECR, còn `deploy` là stage duy nhất chạm vào tài khoản AWS. Không thứ gì trong `test` chạm được tới AWS, và chính điều đó làm cho điểm tiếp theo khả thi.

* Không có access key AWS nào tồn tại trong cấu hình CI. Ba job cần credential là `push-ecr`, `publish-raftdb-image` và `deploy-to-aws`, cả ba đều khai báo cùng một khối `id_tokens` với `aud: https://git.namanhishere.com`, nên audience và issuer đều là cùng một GitLab tự quản. Mỗi job đổi token đó qua `sts assume-role-with-web-identity` lấy một session giới hạn 3600 giây. Một job log bị lộ chỉ tốn một giờ, không phải một lần thay khoá.

* Chuỗi giám hộ là kết quả thực sự của tuần này. `raftdb-image` build image, chạy bốn bài kiểm thử hợp đồng, scan nó, và không giữ credential AWS nào, nên nó không thể publish bất cứ thứ gì dù có muốn. Nó chuyển image sang bước sau dưới dạng tar đã gzip kèm `raftdb-image-evidence.json` ghi lại commit, docker image ID và số lượng lỗ hổng đã scan. `publish-raftdb-image` sau đó kiểm tra lại commit, nạp tar, kiểm tra lại image ID với evidence, và chỉ khi đó mới xin credential. Tag nó push là `raftdb-<commit sha>`, và `scripts/ensure-ecr-repository.sh` đặt `MUTABLE_WITH_EXCLUSION` với bộ lọc wildcard `raftdb-*`, nên đúng những tag đó không thể bị ghi đè trong khi các tag ứng dụng thông thường vẫn có thể thay đổi.

* Có hai chi tiết trong cửa gác scan mà tôi đã phải tự tranh luận với chính mình. `trivy image` chạy với `--exit-code 0`, nghe có vẻ sai cho đến khi thấy rằng quyết định được đưa ra sau đó trong `jq`: một phát hiện CRITICAL luôn làm job thất bại, còn một phát hiện HIGH làm job thất bại trừ khi `RAFTDB_ACCEPT_HIGH_CVES` đúng bằng commit SHA hiện tại. Ghim ngoại lệ vào một SHA thay vì nhận giá trị `true` nghĩa là một lần chấp nhận không thể âm thầm kéo sang commit kế tiếp. Chi tiết còn lại là checksum được ghim: giá trị `sha256` hardcode bao phủ **tệp checksums** của Trivy, và archive sau đó được xác thực dựa trên tệp đó, nên gốc tin cậy là một hash chứ không phải một hash cho mỗi artifact.

* Thứ đi tới bản triển khai là digest, không phải tag. Sau khi push, job đọc digest về, yêu cầu nó khớp `^sha256:[0-9a-f]{64}$`, xoá mọi bản sao cục bộ của image, pull lại **theo digest**, rồi chạy lại kiểm thử hợp đồng container và migration trên đúng phần dữ liệu lấy ra từ ECR. Sau đó nó công bố digest qua `reports: dotenv`, và `deploy-to-aws` đối chiếu giá trị đó với `raftdb-publish-evidence.json` rồi chạy `scripts/validate-deploy-env.sh` trên chín biến bắt buộc trước khi xác thực. Kiểm tra trước, credential sau, ở cả hai job.

* Có ba điểm yếu hơn phần còn lại một cách thẳng thắn, và tôi sẽ sửa chúng trước khi coi việc này là xong. `Dockerfile.ci-utils` ghim Go chính xác ở `go1.25.0` nhưng cài AWS CLI từ một URL tải luôn trỏ bản mới nhất và cài `aws-cdk` qua `npm install -g` không ghim phiên bản, nên image runner không tái lập được. Pipeline không khai báo khối `environment:` nào của GitLab, nghĩa là role ARN đến từ biến project không giới hạn phạm vi và bản triển khai không có lớp bảo vệ ở mức environment. Và `test-raftdb-sanitizers` đang bị comment lại trong khi vẫn được liệt kê là phụ thuộc `optional: true` của job deploy, nên đó là cấu hình hợp lệ nhưng âm thầm không đóng góp gì; phần phủ sanitizer mà nó nhắc tới nằm trong một tệp workflow khác chứ không ở đây.
