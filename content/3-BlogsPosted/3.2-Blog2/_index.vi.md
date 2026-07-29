---
title: "Triển khai AWS không cần khóa tĩnh từ GitLab CI bằng OIDC"
date: 2026-07-24
weight: 2
chapter: false
pre: " <b> 3.2. </b> "
includeInReport: false
---

# Vấn đề

Project thực tập của mình, **awsplace**, nằm trên GitLab instance mà mình tự dựng ở `git.namanhishere.com`. Đó là git remote duy nhất của repository. Mọi thứ pipeline làm với AWS đều bắt đầu từ đây: push container image lên Amazon ECR, chạy `npx cdk deploy` cho `AwsplaceStack`, upload bundle frontend lên Amplify Hosting, và force một lần deploy mới trên ECS.

Cách hiển nhiên nhất để làm được việc đó là tạo một IAM user, sinh một cặp access key, rồi dán `AWS_ACCESS_KEY_ID` và `AWS_SECRET_ACCESS_KEY` vào CI/CD variables của project. Mất hai phút và chạy đúng ngay từ lần đầu. Mình không muốn làm vậy, vì những lý do rất cụ thể chứ không phải lý thuyết.

Một access key đã lưu thì không tự hết hạn. Key của mình sẽ nằm trong variable store của một GitLab instance do mình tự quản trị, trên máy đặt ở nhà, phía sau không có quy trình rotate key nào. Mọi job trong pipeline đều thừa hưởng nó, kể cả các job build image datastore C++ và chạy bốn contract test lên image đó, những job chẳng có việc gì phải nói chuyện với AWS. Và nếu key rò rỉ, qua một `set -x` đặt sai chỗ, một CI plugin của bên thứ ba, hay một runner bị chiếm quyền, thì phạm vi thiệt hại sẽ kéo dài vĩnh viễn cho tới khi mình phát hiện và tự tay revoke.

Vì vậy pipeline không giữ một AWS key nào cả. Giá trị liên quan tới AWS duy nhất được lưu trong GitLab là `${AWS_ROLE_ARN}`, đó là một tham chiếu role, không phải credential. Biết nó cũng không cấp cho ai quyền gì.

# Quan hệ tin cậy được thiết lập ra sao

GitLab có thể đóng vai một OpenID Connect identity provider. Với bất kỳ job nào khai báo keyword `id_tokens`, GitLab sinh một JWT ngắn hạn, ký bằng khóa của chính nó, rồi inject vào environment của riêng job đó. Token không bao giờ được ghi vào repository và không bao giờ được lưu lại thành artifact.

Phía AWS có hai đối tượng. Thứ nhất là một IAM OIDC identity provider đăng ký cho issuer URL `https://git.namanhishere.com`, nhờ nó IAM mới lấy được document JWKS và xác thực chữ ký trên token do GitLab của mình phát ra. Thứ hai là một IAM role có trust policy chỉ định provider đó làm principal và giới hạn những token nào được phép assume role.

Audience quan trọng hơn vẻ ngoài của nó. Trong `.gitlab-ci.yml` mình khai báo tường minh:

```yaml
id_tokens:
  AWS_JWT_TOKEN:
    aud: https://git.namanhishere.com
```

Cả ba job có credential đều khai báo đúng giá trị đó, nên ở đây `aud` và `iss` là cùng một chuỗi. Đó là một lựa chọn có chủ ý và nó có cái giá cần nói thẳng: một audience trùng với issuer là ràng buộc yếu hơn so với audience riêng cho từng consumer, chẳng hạn `sts.amazonaws.com`, bởi nó không phân biệt được "token dành cho AWS" với "token dành cho bất cứ thứ gì khác đang tin GitLab của mình". Hiện tại AWS là OIDC relying party duy nhất trong project, nên khác biệt này còn nằm trên giấy. Nếu mình thêm relying party thứ hai, việc đầu tiên phải làm là tách audience ra.

<figure>
  <img src="/images/3-BlogsPosted/3.2-Blog2/iam-oidc.png" alt="Console IAM của AWS hiển thị OpenID Connect identity provider git.namanhishere.com với duy nhất một audience được đăng ký" loading="lazy">
  <figcaption>IAM identity provider cho GitLab instance của mình, với đúng một audience được đăng ký. Đó chính là giá trị <code>aud</code> mà cả ba job có credential đều xin; tách nó ra là điều kiện tiên quyết cho relying party thứ hai.</figcaption>
</figure>

Trust policy là nơi chứa quyền cấp phép thật sự. Nó kiểm tra audience theo kiểu so khớp tuyệt đối và kiểm tra subject theo pattern, nên một token được sinh cho project khác hoặc cho branch khác của cùng project cũng không assume được role dù chữ ký hoàn toàn hợp lệ:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/git.namanhishere.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "git.namanhishere.com:aud": "https://git.namanhishere.com"
        },
        "StringLike": {
          "git.namanhishere.com:sub": "project_path:namanhishere/awsplace:ref_type:branch:ref:main"
        }
      }
    }
  ]
}
```

Account ID được ẩn đi trong toàn bộ bài viết này. Claim `sub` là phần làm việc thật: GitLab dựng nó từ project path, ref type và tên ref, và việc ghim nó vào `ref:main` là thứ ngăn một branch hay một fork tự sinh cho mình một credential để deploy. Chữ ký hợp lệ không đồng nghĩa với được cấp quyền.

<figure>
  <img src="/images/diagrams/gitlab-oidc-trust.svg" alt="Sơ đồ tuần tự mô tả một job GitLab CI đổi token OIDC đã ký lấy credential AWS tạm thời qua IAM và STS" loading="lazy">
  <figcaption>Toàn bộ quá trình bắt tay, từ khai báo <code>id_tokens</code> tới một session STS 3600 giây. Mỗi bước đều ghi kèm dòng tương ứng trong <code>.gitlab-ci.yml</code>.</figcaption>
</figure>

# Cấu hình job

Bản thân bước đổi token chỉ là một lệnh `aws-cli`. Đây là `before_script` của job `push-ecr`, job build image ứng dụng Go rồi push lên ECR:

```yaml
before_script:
  - >
    ASSUME_ROLE_OUTPUT=$(aws sts assume-role-with-web-identity
    --role-arn ${AWS_ROLE_ARN}
    --role-session-name "GitLabCI-${CI_PIPELINE_ID}"
    --web-identity-token ${AWS_JWT_TOKEN}
    --duration-seconds 3600
    --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]"
    --output text)
  - export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $1}')
  - export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $2}')
  - export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | awk '{print $3}')
```

Folded scalar `- >` là lý do lệnh này tới tay shell dưới dạng một dòng duy nhất dù trải ra bảy dòng YAML.

Ba chi tiết trong lệnh trên đều mang tải. `--web-identity-token` chỉ nhận đúng `${AWS_JWT_TOKEN}` được inject vào chứ không nhận gì khác, nên không có secret nào bị nội suy từ variable store. `--role-session-name` nhúng `${CI_PIPELINE_ID}`, nghĩa là mọi session xuất hiện trong CloudTrail đều truy về được một pipeline; job `publish-raftdb-image` dùng `"GitLabCI-${CI_PIPELINE_ID}-RaftDB"` nên hành động của nó tách được khỏi lần push image ứng dụng. Còn `--query` đi cùng `--output text` trả về ba trường credential dưới dạng text phân tách bằng tab, sau đó ba dòng `export` tách chúng ra bằng `awk`. Không credential nào bị in ra log.

Khi các biến đó đã được export, phần còn lại của job chỉ là công cụ AWS bình thường. Việc đăng nhập registry dùng một token dẫn xuất từ chính session đó:

```bash
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"
```

`get-login-password` in password ra stdout, và việc pipe vào `--password-stdin` giữ cho nó không lộ trên process table lẫn trong log của job. Nó hết hạn cùng session, giống mọi thứ khác ở đây.



# Credential làm được gì và không làm được gì

Session được cấp cho 3600 giây. Khi pipeline kết thúc, credential đã thành vô dụng, và không còn gì phải rotate hay revoke. Con số đó chưa được tinh chỉnh; nó là cùng một `--duration-seconds 3600` ở cả ba job, và dài hơn nhu cầu thực tế của một lần chạy. Siết lại theo từng job sẽ thu hẹp thêm cửa sổ rủi ro, với cái giá là một lần deploy thất bại nếu CDK deploy chạy lâu hơn tuổi thọ credential của chính nó.

Session được phép làm gì thì phụ thuộc vào permission policy của role, và đây là điểm yếu thật sự của cấu hình mình đang dùng. Một role phục vụ cả ba job, nên `push-ecr` chạy với đúng quyền của `deploy-to-aws`, job cần tới CloudFormation, ECS, Amplify, Secrets Manager, EFS, S3 và Route 53 để dựng `AwsplaceStack`. Identity thì ngắn hạn; quyền cấp cho nó thì không hề hẹp. Federation đã xóa bỏ vấn đề secret lưu trữ, chứ không xóa vấn đề cấp quyền quá rộng, và mình không nên nói khác đi.

Ba job khai báo `id_tokens`: `push-ecr`, `publish-raftdb-image` và `deploy-to-aws`. Mọi thứ còn lại trong pipeline chạy mà không có bất kỳ identity AWS nào, và đó mới là nửa thú vị của thiết kế.

<figure>
  <img src="/images/3-BlogsPosted/3.2-Blog2/gitlab-ci.png" alt="Pipeline #73 của GitLab ở chế độ job dependencies, hiển thị mười bốn job trải trên các stage build-ci-image, test, build và deploy" loading="lazy">
  <figcaption>Pipeline #73 trên <code>main</code>: 14 job, 35 phút. Ba job trong đó giữ một identity AWS. Mười một job còn lại, gồm cả <code>raftdb-image</code>, không giữ gì.</figcaption>
</figure>

# Chuỗi giám hộ

Đây là phần mình thật sự sẵn sàng bảo vệ trong một buổi review.

Container image RaftDB là datastore production của awsplace. `raftdb-image` là job build nó, và job đó không có khối `id_tokens`, không có role ARN, không có đường nào chạm tới AWS. Nó chạy ở stage `test` trên `docker:27-cli`, build `raftdb:${CI_COMMIT_SHA}`, rồi chạy bốn contract test lên image vừa build: `container_contract_test.sh`, `qualification_runtime_contract_test.sh`, `migration_runtime_contract_test.sh` và `s3_runtime_contract_test.sh`. Nó cài Trivy 0.72.0 bằng cách tải archive release cùng file checksums của release, xác minh file checksums đó với một sha256 ghi cứng trong pipeline, rồi mới xác minh archive với file checksums. Nó ghi lại Docker image ID trước và sau khi scan và fail nếu hai giá trị khác nhau, vì một scanner chẳng có lý do gì để làm biến đổi chính artefact nó đang kiểm tra. Bất kỳ phát hiện CRITICAL nào cũng làm job fail ngay. Một phát hiện HIGH cũng vậy, trừ khi `RAFTDB_ACCEPT_HIGH_CVES` được đặt đúng bằng `$CI_COMMIT_SHA` đang được build, điều này biến việc chấp nhận rủi ro thành quyết định cho một commit cụ thể chứ không phải một cái công tắc ai đó bật rồi để đó.

Ý nghĩa của việc không cấp credential cho job đó là: một build step bị chiếm quyền cũng không có gì để push. Một dependency độc hại trong Dockerfile của RaftDB có thử làm gì thì cũng không tới được ECR, vì trong environment của job đó không tồn tại identity nào chạm được vào ECR.

Nên image đã được test buộc phải di chuyển. Job lưu nó lại và chuyển giao dưới dạng artifact, kèm một tài liệu bằng chứng nhỏ:

```bash
docker save --output raftdb-image.tar "$LOCAL_IMAGE"
gzip -9 raftdb-image.tar
jq -n \
  --arg commit "$CI_COMMIT_SHA" \
  --arg imageId "$IMAGE_ID_AFTER_SCAN" \
  --arg tag "$LOCAL_IMAGE" \
  --argjson criticalCount "$CRITICAL_COUNT" \
  --argjson highCount "$HIGH_COUNT" \
  --argjson highAccepted "$HIGH_ACCEPTED" \
  '{commit: $commit, imageId: $imageId, localTag: $tag, scan: {criticalCount: $criticalCount, highCount: $highCount, highAccepted: $highAccepted}}' \
  > raftdb-image-evidence.json
```

`publish-raftdb-image` nhận phần đó qua `needs: [{job: raftdb-image, artifacts: true}]`. Trước khi xin token, nó xác lập lại danh tính của artifact hai lần. Nó đọc `.commit` từ `raftdb-image-evidence.json` và fail nếu giá trị đó không phải `$CI_COMMIT_SHA`, qua đó loại bỏ một artifact cũ từ pipeline trước. Sau đó nó chạy `gzip -dc raftdb-image.tar.gz | docker load` và so `{{.Id}}` của image vừa load với `.imageId` trong file bằng chứng, lệch một chút là fail. Chỉ khi cả hai kiểm tra đều qua thì `aws sts assume-role-with-web-identity` mới xuất hiện, với session name có hậu tố `-RaftDB`. Credential tới ở bước bốn, không phải bước một.

Việc nó làm với credential đó cũng bị bó lại có chủ ý. `scripts/ensure-ecr-repository.sh` giải ra URI của repository, rồi job khẳng định thành phần repository đúng bằng chuỗi `awsplace-ecs`, từ chối tiếp tục với bất cứ thứ gì khác. Nó push tag `raftdb-${CI_COMMIT_SHA}`. Tag đó bất biến trên ECR theo cấu hình: repository chạy với `--image-tag-mutability MUTABLE_WITH_EXCLUSION` và một exclusion filter `filterType=WILDCARD,filter=raftdb-*`, nên tag thường vẫn di chuyển được còn tag `raftdb-*` thì không. Nếu tag đã tồn tại, job pull nó về và so image ID với image nó vừa xác minh, fail nếu tag đang trỏ tới bytes khác thay vì ghi đè lên bất cứ thứ gì.

Rồi nó làm điều mình thích nhất trong cả pipeline. Nó đọc digest trả về, kiểm tra với `^sha256:[0-9a-f]{64}$`, xóa mọi bản local của image bằng `docker image rm --force`, pull image lại *theo digest*, và chạy lại container test cùng migration test trên đúng bytes mà ECR trả về:

```bash
docker image rm --force \
  "$LOCAL_IMAGE" \
  "${ECR_URI}:${IMAGE_TAG}" \
  "${ECR_URI}@${IMAGE_DIGEST}" 2>/dev/null || true
docker pull "${ECR_URI}@${IMAGE_DIGEST}"
bash raftdb/test/container_contract_test.sh "${ECR_URI}@${IMAGE_DIGEST}"
bash raftdb/test/migration_runtime_contract_test.sh "${ECR_URI}@${IMAGE_DIGEST}"
```

Việc xóa các image local trước là thứ làm cho lần pull lại có ý nghĩa. Không xóa thì Docker sẽ dùng luôn các layer nó đã có, và bài test chẳng chứng minh được gì về những gì thật sự đang nằm trong registry.

Digest sau đó được chuyển tiếp dưới dạng một dotenv report:

```yaml
artifacts:
  expire_in: 90 days
  paths:
    - raftdb-publish-evidence.json
    - raftdb-publish.env
  reports:
    dotenv: raftdb-publish.env
```

`deploy-to-aws` nhận `PUBLISHED_RAFTDB_IMAGE_DIGEST` từ dotenv report đó, và nó không tin ngay. `before_script` của nó đọc `.digest` ra từ `raftdb-publish-evidence.json` và fail nếu giá trị dotenv và file bằng chứng không khớp, sau đó export giá trị đã khớp thành `RAFTDB_IMAGE_DIGEST` rồi chạy `scripts/validate-deploy-env.sh`. Script đó đòi chín biến phải có mặt, loại bỏ mọi giá trị còn giữ một tham chiếu `${VAR}` chưa được giải, kiểm tra `RAFTDB_IMAGE_DIGEST` với cùng pattern sha256, và kiểm tra `HOSTED_ZONE_ID` với `^Z[A-Z0-9]+$`. Toàn bộ phần này chạy *trước* lệnh STS. Một secret thiếu hoặc một digest sai dạng làm job fail khi nó vẫn chưa có credential AWS nào và chưa tạo ra tài nguyên AWS nào.

Kết quả là digest mà CDK ghim vào ECS task definition chứng minh được là digest của một image được build mà không có quyền AWS, đã scan, đã test bốn kiểu, đã đối chiếu từng byte khi chuyển giao, và test lại một lần nữa sau khi đi vòng qua registry.

<figure>
  <img src="/images/diagrams/cicd-pipeline.svg" alt="Bốn stage của pipeline GitLab awsplace với chuỗi giám hộ image RaftDB được làm nổi bật" loading="lazy">
  <figcaption>Bốn stage: <code>build-ci-image</code>, <code>test</code>, <code>build</code>, <code>deploy</code>. Làn giám hộ chạy từ job <code>raftdb-image</code> không có credential tới bước đối chiếu digest trong <code>deploy-to-aws</code>.</figcaption>
</figure>

## References

- [GitLab: ID token authentication](https://docs.gitlab.com/ci/secrets/id_token_authentication/)
- [GitLab: `id_tokens` keyword reference](https://docs.gitlab.com/ci/yaml/#id_tokens)
- [GitLab: Configure OpenID Connect with AWS to retrieve temporary credentials](https://docs.gitlab.com/ci/cloud_services/aws/)
- [AWS STS API: `AssumeRoleWithWebIdentity`](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [AWS IAM: Create OpenID Connect identity providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Amazon ECR: Private registry authentication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html)
- [Amazon ECR: Image tag mutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html)
