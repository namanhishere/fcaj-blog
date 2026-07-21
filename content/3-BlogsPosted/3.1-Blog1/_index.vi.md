---
title: "Scale GitLab Runner về 0 bằng EC2 Auto Scaling"
date: 2026-07-21
weight: 1
chapter: false
pre: " <b> 3.1. </b> "
includeInReport: false
---

# Giới thiệu

Trong quá trình thực hiện project thực tập tại FCAJ, mình host toàn bộ source code trên GitLab cá nhân và tự dựng một GitLab Runner trên máy ở nhà để chạy CI/CD.

Vấn đề là cấu hình máy không đủ mạnh để chạy nhiều pipeline cùng lúc, nên mình chỉ cấu hình 1 concurrent job. Điều đó đồng nghĩa với việc mỗi khi có nhiều pipeline được trigger, các job sẽ phải xếp hàng chờ rất lâu. Có những lúc toàn bộ pipeline mất hơn một tiếng mới hoàn thành, và riêng các job chạy AddressSanitizer (ASan) hay ThreadSanitizer (TSan) còn phải chờ hơn 30 phút chỉ để giành được một worker.

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/longqueue.png" alt="Danh sách job GitLab có thời gian chờ từ 11 đến 33 phút" loading="lazy">
  <figcaption>Job không chạy chậm. Chúng chỉ mất quá lâu để giành được một worker.</figcaption>
</figure>

Lúc đó mình chợt nghĩ: thay vì nâng cấp phần cứng, tại sao không tận dụng luôn **AWS EC2 Auto Scaling Group**? AWS vẫn còn khoản tín dụng 200 USD dành cho sinh viên, nên đây cũng là cơ hội khá hay để thử triển khai một GitLab Runner có khả năng tự mở rộng theo số lượng job cần chạy. Vừa giải quyết đúng vấn đề mình đang gặp, vừa có dịp thực hành với hạ tầng AWS trên một bài toán thực tế.

# Mục tiêu thiết kế

Mình không đặt mục tiêu xây một hệ thống CI/CD hoàn chỉnh hay thay thế GitLab SaaS. Điều mình muốn chỉ đơn giản là:

- Không tốn tiền cho worker khi không có pipeline nào chạy (scale-to-zero).
- Chấp nhận mất vài chục giây cold start để đổi lấy chi phí gần như bằng 0.
- Khi có pipeline, worker phải tự động được tạo mà không cần can thiệp thủ công.
- Mỗi job chạy trên một môi trường hoàn toàn mới để tránh ảnh hưởng lẫn nhau.
- Sau khi hoàn thành, worker tự hủy để không lãng phí tài nguyên.

Nói ngắn gọn hơn, mình muốn biến GitLab Runner thành một dịch vụ "chỉ tồn tại khi cần".

# Ý tưởng thiết kế kiến trúc

Toàn bộ hệ thống được chia thành hai phần.

Phần thứ nhất là **Runner Manager**, chạy liên tục trên một máy nhỏ. Nó chỉ có nhiệm vụ kết nối với GitLab, theo dõi hàng đợi pipeline và quyết định khi nào cần thêm worker.

Phần thứ hai là các **EC2 Worker** nằm trong một **Auto Scaling Group** với `desired capacity = 0`. Bình thường sẽ không có EC2 nào tồn tại. Chỉ khi GitLab xuất hiện job mới, Runner Manager mới yêu cầu Auto Scaling Group khởi tạo thêm instance. Worker sau khi boot sẽ nhận đúng một job, chạy trong Docker container rồi tự terminate.

Điểm mình thích ở mô hình này là Runner Manager luôn rất nhẹ, còn toàn bộ tài nguyên phục vụ build chỉ xuất hiện khi thực sự cần.

<figure>
  <img src="/images/diagrams/gitlab-runner-ec2-autoscale-vi.svg" alt="Sơ đồ GitLab Runner Manager điều khiển EC2 Auto Scaling Group và các worker tạm thời" loading="lazy">
  <figcaption>Hai luồng chính của hệ thống: chuẩn bị worker image và thực thi một CI job trên EC2 tạm thời.</figcaption>
</figure>

Luồng chạy một job có thể tóm tắt như sau:

1. Runner Manager nhận job từ GitLab qua HTTPS.
2. Fleeting AWS plugin yêu cầu Auto Scaling Group tăng capacity từ `0` lên `1`.
3. EC2 boot từ custom AMI, Runner Manager kết nối qua SSH và khởi chạy Docker container.
4. Log cùng kết quả được trả về GitLab.
5. Worker bị loại bỏ sau job và capacity quay về `0`.

## Một job trên một máy

Phần cấu hình quan trọng nhất của Runner thực ra khá ngắn:

```toml
[[runners]]
  executor = "docker-autoscaler"

  [runners.autoscaler]
    plugin               = "aws:latest"
    capacity_per_instance = 1
    max_use_count         = 1
    max_instances         = 10

    [[runners.autoscaler.policy]]
      idle_count = 0
      idle_time  = "5m"
```

`capacity_per_instance = 1` giới hạn mỗi EC2 chạy một job tại một thời điểm, còn `max_use_count = 1` khiến instance được lên lịch loại bỏ ngay sau lần sử dụng đầu tiên. Mình chấp nhận mất local cache và khả năng tái sử dụng worker để đổi lấy môi trường sạch, dễ dự đoán hơn cho từng pipeline. Trong môi trường production, `aws:latest` cũng nên được pin về một phiên bản plugin cụ thể.


## Chỉ nên có một thành phần điều khiển capacity

Terraform tạo Auto Scaling Group ban đầu, nhưng GitLab Runner mới là thành phần tăng hoặc giảm `desired_capacity` trong lúc vận hành. Nếu Terraform vẫn cố quản lý giá trị này ở mỗi lần `apply`, hai controller có thể kéo capacity theo hai hướng khác nhau.

```hcl
resource "aws_autoscaling_group" "runner" {
  name                = "${var.name_prefix}-asg"
  min_size            = 0
  max_size            = var.max_instances
  desired_capacity    = 0
  vpc_zone_identifier = local.subnet_ids

  launch_template {
    id      = aws_launch_template.runner.id
    version = "$Latest"
  }

  lifecycle {
    # Fleeting plugin là controller của capacity sau khi ASG được tạo.
    ignore_changes = [desired_capacity]
  }
}
```

`ignore_changes` không có nghĩa là Terraform bỏ quản lý ASG. Terraform vẫn quản lý Launch Template, subnet, tag và các thuộc tính hạ tầng khác; nó chỉ không ghi đè số lượng instance mà Runner đang yêu cầu.

# Prebuilt Docker image bằng GitHub Actions

Một vấn đề mình gặp khá sớm là môi trường build.

Nếu mỗi worker mới khởi động lại phải cài compiler, SDK, dependency rồi mới chạy pipeline thì phần lớn thời gian sẽ bị lãng phí cho việc chuẩn bị môi trường thay vì chạy job.

Để giải quyết việc đó, mình tách toàn bộ môi trường build thành một Docker image riêng. Image này được GitHub Actions tự động build và publish lên GitHub Container Registry (GHCR) mỗi khi có thay đổi.

Nhờ vậy, tất cả worker đều sử dụng chung một môi trường build giống hệt nhau. Khi cần thêm package hay tool mới, mình chỉ cần cập nhật Dockerfile rồi để GitHub Actions build lại image.

Điều này cũng giúp việc quản lý môi trường CI trở nên đơn giản hơn rất nhiều vì toàn bộ dependency chỉ tồn tại ở một nơi.

Đây là phiên bản rút gọn của workflow build và publish image:

```yaml
name: Build CI image

on:
  push:
    paths:
      - "ci-image/**"

permissions:
  contents: read
  packages: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v7
        with:
          context: ./ci-image
          push: true
          tags: |
            ghcr.io/${{ github.repository }}-ci:latest
            ghcr.io/${{ github.repository }}-ci:sha-${{ github.sha }}
```

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/ghcr.png" alt="Docker image của GitLab Runner worker được publish trên GitHub Container Registry" loading="lazy">
  <figcaption>CI image trên GHCR có cả tag <code>latest</code> và tag gắn với commit để dễ truy vết.</figcaption>
</figure>

Trong bản demo mình vẫn dùng `latest` để cập nhật nhanh. Nếu cần tính tái lập cao hơn, worker nên pull image theo digest hoặc một tag bất biến thay vì một tag có thể trỏ sang nội dung mới.

# Bake sẵn VM image

Có Docker image thôi vẫn chưa đủ.

Nếu mỗi lần EC2 khởi động mới cài Docker rồi pull image từ GHCR thì cold start vẫn khá dài. Với một hệ thống được thiết kế để scale từ 0, vài chục giây này xuất hiện ở mọi pipeline đầu tiên.

Vì vậy mình sử dụng Packer để tạo một **custom Amazon Machine Image (AMI)**.

Trong AMI này đã có sẵn:

- Docker
- các công cụ cần thiết
- Docker image phục vụ CI

Packer dùng builder `amazon-ebs`, chạy provisioning script và đóng gói trạng thái cuối thành AMI:

```hcl
build {
  name    = "gitlab-runner-worker"
  sources = ["source.amazon-ebs.runner"]

  provisioner "shell" {
    environment_vars = [
      "CI_IMAGE=${var.ci_image}",
      "SSH_USER=${var.ssh_username}",
    ]
    script = "${path.root}/scripts/install.sh"
  }
}
```

Provisioning script cài Docker và chạy `docker pull "${CI_IMAGE}"` ngay trong quá trình build AMI. Vì các layer đã có sẵn trên disk, worker mới chỉ cần kiểm tra hoặc tải những layer thay đổi khi boot.

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/config.png" alt="File biến Packer chứa region, instance type và địa chỉ CI image trên GHCR" loading="lazy">
  <figcaption>Các giá trị đầu vào dùng để build worker AMI bằng Packer.</figcaption>
</figure>

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/build_image.png" alt="Log Packer pull Docker image và hoàn tất tạo Amazon Machine Image" loading="lazy">
  <figcaption>Lần build thử nghiệm hoàn tất sau 6 phút 44 giây; chi phí chuẩn bị được trả một lần thay vì lặp lại trên mọi job.</figcaption>
</figure>

Khi Auto Scaling Group tạo worker mới, máy gần như có thể chạy job ngay mà không phải cài đặt lại từ đầu.

Việc build AMI mất thêm vài phút, nhưng đây là chi phí chỉ phải trả một lần. Đổi lại, mọi worker được tạo sau đó đều khởi động nhanh hơn đáng kể.

# Quan sát vòng đời worker

Để kiểm tra autoscaling, mình theo dõi đồng thời log của Runner và trạng thái Auto Scaling Group:

```bash
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names <asg_name> \
  --query "AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances[].LifecycleState}"'
```

Nếu hệ thống hoạt động đúng, `desired` sẽ đi theo chuỗi `0 → 1 → 0`. Trong một đợt nhiều job, EC2 ở trạng thái `Initializing`, `Running`, `Shutting-down` và `Terminated` có thể cùng xuất hiện vì mỗi worker có vòng đời riêng.

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/ec2.png" alt="Các EC2 worker tạm thời ở trạng thái running, shutting-down và terminated" loading="lazy">
  <figcaption>Các worker mới và worker đang bị thu hồi có thể chồng lấp trong một đợt pipeline.</figcaption>
</figure>

<figure>
  <img src="/images/3-BlogsPosted/3.1-Blog1/runner.png" alt="GitLab Runner sử dụng Docker Autoscaler đang online và xử lý các job" loading="lazy">
  <figcaption>Kết quả Runner trên trang quản lý của Gitlab</figcaption>
</figure>

# Tổng kết

Sau khi hoàn thành, GitLab Runner của mình có thể tự động mở rộng theo số lượng pipeline đang chờ.

Khi không có job nào, toàn bộ EC2 worker đều được tắt và chi phí gần như bằng 0. Khi có pipeline mới, Auto Scaling Group tự tạo worker, chạy đúng một job rồi thu hồi instance sau khi hoàn thành.

Đây chưa phải là một hệ thống production-ready. Mình vẫn còn nhiều thứ muốn cải thiện như private subnet, sử dụng IAM Role thay cho access key, pin image bằng digest hay bổ sung monitoring cho toàn bộ quá trình khởi tạo worker.

Dù vậy, project này giúp mình hiểu rõ hơn cách GitLab Runner Autoscaler hoạt động, cách kết hợp Terraform, Packer và AWS Auto Scaling Group để xây dựng một hệ thống CI/CD có khả năng tự mở rộng mà không phải duy trì một cụm máy chạy liên tục.

## Tài liệu tham khảo

- [GitLab Docker Autoscaler executor](https://docs.gitlab.com/runner/executors/docker_autoscaler/)
- [GitLab Runner advanced configuration](https://docs.gitlab.com/runner/configuration/advanced-configuration/#the-runnersautoscaler-section)
- [HashiCorp: Manage AWS Auto Scaling Groups with Terraform](https://developer.hashicorp.com/terraform/tutorials/aws/aws-asg)
- [HashiCorp Packer: Amazon EBS builder](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/builder/ebs)
