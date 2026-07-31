---
title : "VPC & Mạng"
date : 2024-01-01
weight : 2
chapter : false
pre : " <b> 5.3.2 </b> "
---

#### Cấu hình VPC

Module VPC (**createVpc**) là module đơn giản nhất nhưng cơ bản nhất. Mọi tài nguyên khác đều phụ thuộc vào nó.

```typescript
export function createVpc(scope: Construct): VpcOutput {
  const vpc = new ec2.Vpc(scope, 'AwsplaceVpc', {
    maxAzs: 2,
    natGateways: 0,
    subnetConfiguration: [
      {
        name: 'Public',
        subnetType: ec2.SubnetType.PUBLIC,
        cidrMask: 24,
      },
    ],
  });
  return { vpc };
}
```

**Đặc điểm chính:**

| Thuộc tính | Giá trị | Lý do |
|------------|--------|-------|
| **maxAzs** | 2 | Tính sẵn sàng cao trên hai Vùng Khả dụng |
| **natGateways** | 0 | Không NAT Gateway — tối ưu chi phí |
| Kiểu subnet | PUBLIC | ECS tasks cần IP công cộng để truy cập AWS APIs |
| CIDR mask | /24 | 256 địa chỉ mỗi subnet, đủ cho các tác vụ Fargate |

#### Tại sao không có NAT Gateway?

Đây là một quyết định kiến trúc có chủ đích. Trong kiến trúc này:

1. **ECS tasks chạy trong public subnets** với **assignPublicIp: true**. Chúng không cần NAT Gateway để truy cập internet.
2. **Lambda KHÔNG nằm trong VPC**. Nó truy cập DynamoDB, S3 và ECS ALB qua các điểm cuối API công cộng của AWS.
3. **Bảo mật được thực thi ở cấp security group**, không phải ở lớp mạng. ECS tasks được bảo vệ bởi security groups chỉ cho phép ingress từ ALB.

Điều này tiết kiệm khoảng **$32/tháng cho mỗi NAT Gateway** (2 AZ sẽ cần 2 NAT Gateway để có tính sẵn sàng cao).

![Sơ đồ Kiến trúc VPC](/images/5-Workshop/5.3-CDK-Project-Structure/vpc-architecture.png)

#### Security Groups

Security groups KHÔNG được tạo trong module VPC. Chúng được tạo cùng với tài nguyên mà chúng bảo vệ trong module ECS:

**ALB Security Group** — được tạo trong module ECS:
```typescript
const albSg = new ec2.SecurityGroup(scope, 'AlbSecurityGroup', {
  vpc,
  description: 'ALB security group - cho phép HTTP/HTTPS từ mọi nơi',
  allowAllOutbound: true,
});
albSg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(80), 'Cho phép HTTP từ mọi nơi');
albSg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(443), 'Cho phép HTTPS từ mọi nơi');
```

**ECS Security Group** — được tạo trong module ECS:
```typescript
const ecsSg = new ec2.SecurityGroup(scope, 'EcsSecurityGroup', {
  vpc,
  description: 'ECS security group - chỉ cho phép cổng ứng dụng từ ALB',
  allowAllOutbound: true,
});
ecsSg.addIngressRule(albSg, ec2.Port.tcp(8980), 'Cho phép lưu lượng ứng dụng từ ALB');
```

**Chuỗi security group:**
```
Internet → ALB SG (cổng 80/443) → ALB → ECS SG (cổng 8980) → ECS Task (Go app)
```

ECS security group bị khóa chặt: nó chỉ chấp nhận lưu lượng trên cổng 8980 từ ALB security group. Không thể truy cập internet trực tiếp vào ECS tasks, mặc dù chúng có địa chỉ IP công cộng.

**Quyền truy cập EFS cho RaftDB:**
```typescript
raftDb.fileSystem.connections.allowDefaultPortFrom(
  ecsSg,
  'Cho phép tác vụ ứng dụng gắn kết lưu trữ raftdb bền vững',
);
```

Điều này cho phép ECS task gắn kết EFS filesystem cho lưu trữ WAL bền vững của RaftDB.
