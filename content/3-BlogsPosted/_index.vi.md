---
title: "Các bài viết"
linkPreviewLabel: "Bài viết"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 3. </b> "
includeInReport: true
---


Đây là nơi mình ghi lại những bài toán kỹ thuật đã gặp trong lúc tự dựng và thử nghiệm hệ thống: cách làm, lý do chọn nó và những chỗ vẫn còn có thể cải thiện. Cả ba bài dưới đây đều được đăng trong group Facebook AWS Study Group.

### Scale GitLab Runner về 0 bằng EC2 Auto Scaling

[Đọc bài viết](3.1-Blog1/)

Bài viết trình bày cách mình kết hợp Docker Autoscaler của GitLab Runner, Fleeting AWS plugin, Terraform, Packer và EC2 Auto Scaling Group để tạo một worker tạm thời cho mỗi job rồi đưa số lượng worker trở về 0 khi hàng đợi trống.

<figure>
  <a href="/vi/3-blogsposted/3.1-blog1/" aria-label="Đọc bài Scale GitLab Runner về 0 bằng EC2 Auto Scaling">
    <img src="/images/diagrams/gitlab-runner-ec2-autoscale-vi.svg" alt="Kiến trúc GitLab Runner sử dụng EC2 Auto Scaling Group và các worker tạm thời" loading="lazy">
  </a>
  <figcaption>Chuẩn bị worker image một lần, khởi tạo EC2 worker theo nhu cầu và đưa capacity trở về 0 sau khi các job hoàn tất.</figcaption>
</figure>

<div hidden aria-hidden="true">

![Kiến trúc GitLab Runner sử dụng EC2 Auto Scaling Group và các worker tạm thời](/images/diagrams/gitlab-runner-ec2-autoscale-vi.png)

</div>

### Triển khai AWS không cần khóa tĩnh từ GitLab CI tự quản bằng OIDC

[Đọc bài viết](3.2-Blog2/)

Bài viết trình bày cách pipeline awsplace triển khai lên AWS mà không lưu access key nào: GitLab sinh một token OIDC đã ký cho từng job, IAM xác thực issuer cùng các claim `aud` và `sub`, và `sts assume-role-with-web-identity` trả về một session 3600 giây. Sau đó bài viết đi theo chuỗi giám hộ image RaftDB, nơi job build và scan image không hề giữ credential AWS nào.

<figure>
  <a href="/vi/3-blogsposted/3.2-blog2/" aria-label="Đọc bài Triển khai AWS không cần khóa tĩnh từ GitLab CI tự quản bằng OIDC">
    <img src="/images/diagrams/gitlab-oidc-trust-vi.svg" alt="Một job GitLab CI đổi token OIDC đã ký lấy session IAM role tạm thời" loading="lazy">
  </a>
  <figcaption>Pipeline chỉ lưu một role ARN, không lưu credential. GitLab ký token cho từng job và IAM quyết định có tin token đó hay không.</figcaption>
</figure>

<div hidden aria-hidden="true">

![Một job GitLab CI đổi token OIDC đã ký lấy session IAM role tạm thời](/images/diagrams/gitlab-oidc-trust-vi.png)

</div>

### Amazon EFS đã rút ngắn vòng lặp phát triển của tôi khi xây dựng một Raft datastore như thế nào

[Đọc bài viết](3.3-Blog3/)

Bài viết giải thích vì sao sidecar RaftDB giữ write-ahead log và snapshot trên một Amazon EFS access point thay vì trên phần lưu trữ thuộc về task, và điều đó thay đổi công việc hằng ngày ra sao: một lần deploy Fargate không còn xóa sạch canvas mà trở thành một bài kiểm tra khả năng phục hồi. Bài viết ghi lại lý do EBS, Amazon S3 và volume tạm gắn với task đều bị loại, cùng cách access point đảm nhận phần định danh để uid/gid `10001` rơi vào đúng thư mục mà nó đã sở hữu. Bài viết cũng nói thẳng cái giá của thiết kế này: vì chỉ một writer sở hữu write-ahead log, service deploy với `minHealthyPercent: 0`, nên mỗi lần deploy canvas offline trong suốt cửa sổ đó.

<figure>
  <a href="/vi/3-blogsposted/3.3-blog3/" aria-label="Đọc bài Amazon EFS đã rút ngắn vòng lặp phát triển của tôi khi xây dựng một Raft datastore như thế nào">
    <img src="/images/diagrams/raftdb-efs-devloop-vi.svg" alt="Write-ahead log và snapshot của RaftDB nằm trên một Amazon EFS access point dùng chung qua các lần thay task Fargate" loading="lazy">
  </a>
  <figcaption>Fargate thay task mới sau mỗi lần deploy. Write-ahead log thì sống lâu hơn task.</figcaption>
</figure>

<div hidden aria-hidden="true">

![Write-ahead log và snapshot của RaftDB nằm trên một Amazon EFS access point dùng chung qua các lần thay task Fargate](/images/diagrams/raftdb-efs-devloop-vi.png)

</div>
