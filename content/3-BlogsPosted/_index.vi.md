---
title: "Các bài viết"
linkPreviewLabel: "Bài viết"
date: 2024-01-01
weight: 3
chapter: false
pre: " <b> 3. </b> "
includeInReport: false
---

{{% notice warning %}}  
⚠️ **Lưu ý:** Các thông tin dưới đây chỉ nhằm mục đích tham khảo, vui lòng **không sao chép nguyên văn** cho bài báo cáo của bạn kể cả warning này.
{{% /notice %}}

Đây là nơi mình ghi lại những bài toán kỹ thuật đã gặp trong lúc tự dựng và thử nghiệm hệ thống — gồm cả cách làm, lý do chọn nó và những chỗ vẫn còn có thể cải thiện.

### [Scale GitLab Runner về 0 bằng EC2 Auto Scaling](3.1-Blog1/)

Bài viết trình bày cách mình kết hợp Docker Autoscaler của GitLab Runner, Fleeting AWS plugin, Terraform, Packer và EC2 Auto Scaling Group để tạo một worker tạm thời cho mỗi job rồi đưa số lượng worker trở về 0 khi hàng đợi trống.

<figure>
  <a href="/vi/3-blogsposted/3.1-blog1/" aria-label="Đọc bài Scale GitLab Runner về 0 bằng EC2 Auto Scaling">
    <img src="/images/diagrams/gitlab-runner-ec2-autoscale-vi.svg" alt="Kiến trúc GitLab Runner sử dụng EC2 Auto Scaling Group và các worker tạm thời" loading="lazy">
  </a>
  <figcaption>Chuẩn bị worker image một lần, khởi tạo EC2 worker theo nhu cầu và đưa capacity trở về 0 sau khi các job hoàn tất.</figcaption>
</figure>
