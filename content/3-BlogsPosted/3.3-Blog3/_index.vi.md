---
title: "Amazon EFS đã rút ngắn vòng lặp phát triển của mình khi xây dựng một Raft datastore như thế nào"
date: 2026-07-27
weight: 3
chapter: false
pre: " <b> 3.3. </b> "
includeInReport: false
---

> **Bài viết gốc trên Facebook**: [AWS Study Group](https://www.facebook.com/groups/awsstudygroupfcj/posts/2228318824599744)

## Bối cảnh

Datastore production của dự án thực tập của mình không phải là một dịch vụ được quản lý. Đó là một server C++23 tên RaftDB, chạy như một container sidecar trong cùng một ECS Fargate task với ứng dụng Go. Ứng dụng nói chuyện với nó qua `127.0.0.1:9100` với `DATA_MODE=raftdb-only`, nên mọi pixel trên canvas cộng tác, cùng với config, bans, milestones và lịch sử đặt pixel, đều nằm trong đúng một process đó (`awsplace/cdk/lib/ecs.ts:130-140`).

RaftDB giữ trạng thái của nó trên đĩa. Runtime contract của nó nói rõ về layout: thư mục dữ liệu ghi được là `/data/raftdb`, write-ahead log nằm ở `/data/raftdb/wal`, checkpoint cục bộ nằm ở `/data/raftdb/snapshots`, và process chỉ công bố readiness marker tạm thời tại `/tmp/raftdb-ready` sau khi quá trình recovery hoàn tất (`awsplace/docs/raftdb/runtime-contract.md:34-41`).

Fargate không giữ container. Mỗi lần `cdk deploy`, mỗi image digest mới, mỗi `force-new-deployment` đều thay task bằng một task hoàn toàn mới. Vậy là mình có một process mà toàn bộ giá trị của nó là những byte nó đã ghi xuống đĩa, chạy trên một nền tảng ném cái đĩa đó đi.

## Một WAL rỗng đã khiến mình mất những gì

Ở local thì việc này chưa bao giờ là vấn đề, vì Docker Compose đã cho mình một đĩa bền vững. Service `raftdb` mount một named volume, và named volume sống sót qua `docker compose down`:

```yaml
services:
  raftdb:
    build:
      context: .
      dockerfile: raftdb/Dockerfile
    container_name: awsplace-raftdb
    environment:
      RAFTDB_PORT: "9100"
      RAFTDB_DATA_DIR: /data/raftdb
    volumes:
      - raftdb_data:/data/raftdb
    ports:
      - "9100:9100"

volumes:
  pg_data:
  raftdb_data:
```

Đoạn trên được rút gọn từ `awsplace/docker-compose.yml:7-19` và `:138-140`. Build lại image, khởi động lại container, và các WAL segment cùng snapshot catalog dưới `/data/raftdb` vẫn còn đó. Canvas local của mình giữ nguyên pixel qua một lần build lại mà mình không phải làm gì cả.

Trên Fargate, trước khi mình gắn storage bền vững, điều ngược lại đã xảy ra. Task thay thế khởi động với `/data/raftdb` rỗng. Không có phần cuối WAL nào để replay và không có snapshot nào để restore, nên mỗi lần deploy mình lại nhận về một bảng trắng. Muốn kiểm thử bất cứ thứ gì phụ thuộc vào trạng thái có sẵn thì phải gieo lại canvas bằng tay trước, mà mình thì deploy nhiều lần mỗi giờ. Phần thú vị nhất của công việc, tức là xem server phục hồi ra sao, lại đúng là phần mình không thể quan sát, vì chẳng bao giờ có gì để phục hồi.

## Vì sao chọn EFS chứ không phải các lựa chọn khác

Mình đã xem xét ba lựa chọn khác trước khi mount Amazon EFS, và mỗi lựa chọn thất bại vì một lý do cụ thể.

Một **EBS volume** chỉ gắn được vào một compute instance tại một thời điểm. Với một lần thay thế Fargate task, task mới là một task khác với lifecycle riêng của nó, và mình sẽ phải tháo volume khỏi task đang chết rồi gắn lại vào task mới đúng vào thời điểm chính xác. Việc chuyển giao đó không phải thứ mà ECS deployment cho mình sẵn, và làm sai thì task thay thế không mount được chút nào.

**Amazon S3** không phải một filesystem. RaftDB ghi thêm vào write-ahead log tại chỗ, và nó replay phần cuối WAL khi khởi động (`runtime-contract.md:114-116`). Object trên S3 là bất biến: ghi thêm nghĩa là viết lại cả object. S3 vẫn nằm trong thiết kế, nhưng với vai trò đích đến của các checkpoint hoàn chỉnh, không phải thiết bị chứa WAL.

Một **ephemeral volume ở phạm vi task** thì theo định nghĩa bị hủy cùng với task. Đó chính xác là thất bại mình đã gặp.

Amazon EFS là lựa chọn duy nhất vừa là một POSIX filesystem, vừa có thể được mount bởi task nào đang tồn tại ngay lúc này, và sống lâu hơn tất cả chúng. Phần CDK cho nó rất ngắn:

```typescript
const fileSystem = new efs.FileSystem(scope, 'RaftDbApplicationFileSystem', {
  vpc: props.vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
  encrypted: true,
  removalPolicy: RemovalPolicy.DESTROY,
});
const accessPoint = fileSystem.addAccessPoint('ApplicationAccessPoint', {
  path: '/raftdb/production/member-1',
  createAcl: { ownerUid: '10001', ownerGid: '10001', permissions: '0750' },
  posixUser: { uid: '10001', gid: '10001' },
});

props.taskRole.addToPrincipalPolicy(new iam.PolicyStatement({
  actions: ['elasticfilesystem:ClientMount', 'elasticfilesystem:ClientWrite'],
  resources: [fileSystem.fileSystemArn],
  conditions: {
    StringEquals: { 'elasticfilesystem:AccessPointArn': accessPoint.accessPointArn },
  },
}));
```

Đó là `awsplace/cdk/lib/raftdb-application.ts:32-51`. Sau đó task definition khai báo volume với transit encryption và IAM authorization được bật, rồi mount nó vào đúng đường dẫn mà RaftDB vốn đã mong đợi:

```typescript
taskDefinition.addVolume({
  name: 'raftdb-data',
  efsVolumeConfiguration: {
    fileSystemId: raftDb.fileSystem.fileSystemId,
    transitEncryption: 'ENABLED',
    authorizationConfig: {
      accessPointId: raftDb.accessPoint.accessPointId,
      iam: 'ENABLED',
    },
  },
});

raftDbContainer.addMountPoints({
  sourceVolume: 'raftdb-data',
  containerPath: '/data/raftdb',
  readOnly: false,
});
```

Từ `awsplace/cdk/lib/ecs.ts:87-125`. Hãy để ý điều gì không thay đổi: container vẫn ghi vào `/data/raftdb`, giống hệt như khi chạy dưới Docker Compose. Vòng lặp local và vòng lặp đã deploy giờ dùng chung một hợp đồng về độ bền thay vì hai thiết kế khác nhau.

<figure>
  <img src="/images/3-BlogsPosted/3.3-Blog3/efs-console.png" alt="Bảng điều khiển Amazon EFS hiển thị RaftDB file system với General Purpose performance, Bursting throughput, regional availability và encryption được bật" loading="lazy">
  <figcaption>File system production sau khi tạo. General Purpose performance mode và Bursting throughput là các giá trị mặc định mà đoạn CDK ở trên tạo ra.</figcaption>
</figure>

# Access point lo phần định danh

Container RaftDB chạy dưới `user: '10001:10001'` và buộc phải khởi động không có quyền root (`ecs.ts:101`, `runtime-contract.md:43-46`). Một NFS mount thông thường sẽ trao cho nó một thư mục thuộc quyền root, và lần ghi WAL đầu tiên sẽ thất bại vì lỗi permission. Cách chữa quen thuộc là một entrypoint chạy `chown` trước khi hạ quyền, mà muốn vậy thì container phải có root ngay từ đầu.

Access point loại bỏ bước đó. `createAcl` khiến EFS tạo `/raftdb/production/member-1` thuộc quyền uid và gid `10001` với mode `0750`, còn `posixUser` buộc mọi request đi qua access point đều được đánh giá dưới đúng uid và gid đó. Định danh số của container trùng với thư mục nó rơi vào, nên không cần `chown`, không cần root, không cần init script.

Access point cũng là biên giới phân quyền. Câu lệnh IAM ở trên chỉ cấp `ClientMount` và `ClientWrite` trên file system khi `elasticfilesystem:AccessPointArn` bằng đúng access point này, nên task role không thể chạm tới thư mục nào khác trên cùng file system dù có thư mục như vậy đi nữa. `runtime-contract.md:100-101` phát biểu cùng quy tắc đó từ phía bên kia: IAM vẫn là biên giới phân quyền cho EFS access point.

Cũng chính construct này mở đường cho một cluster nhiều voter trong tương lai. `awsplace/cdk/lib/raftdb.ts:388-408` tạo một access point cho mỗi member tại `/raftdb/${dataGeneration}/member-${nodeId}`, trong đó `dataGeneration` do môi trường cung cấp, nên ba voter có thể dùng chung một file system mà vẫn không thể chạm vào WAL của nhau. Đó là mục tiêu staging đã được ghi trong tài liệu ở `RaftDbStagingStack`, không phải thứ đang chạy hôm nay. Production là một voter duy nhất với `desiredCount: 1` và một đường dẫn cố định `/raftdb/production/member-1`.

# Giá phải trả: deploy theo kiểu dừng rồi mới chạy

Đây là phần mình đã không lường trước. Storage bền vững làm thay đổi chiến lược deploy, và thay đổi theo hướng không dễ chịu.

RaftDB có đúng một writer, và Raft leader fencing thì chưa tồn tại (`runtime-contract.md:78-80`). Nếu ECS làm một rolling deployment bình thường, task mới sẽ mount `/raftdb/production/member-1` khi task cũ còn đang mở WAL. Hai process cùng ghi thêm vào một tập log là hỏng dữ liệu, không phải một tình huống tranh chấp có thể thử lại. Vì vậy service được cấu hình để việc chồng lấp là không thể xảy ra:

```typescript
const service = new ecs.FargateService(scope, 'Service', {
  cluster,
  taskDefinition,
  desiredCount: 1,
  // A single raftdb writer owns the EFS WAL. Stop it before replacement;
  // overlapping tasks would open the same durable files concurrently.
  minHealthyPercent: 0,
  maxHealthyPercent: 100,
  // ...
});
```

`minHealthyPercent: 0` là sự cho phép để ECS đưa số task đang chạy về không. `maxHealthyPercent: 100` cấm nó chạy hai task. Hai giá trị đó cùng nhau biến một lần thay thế kiểu rolling thành dừng rồi mới chạy (`awsplace/cdk/lib/ecs.ts:159-170`).

Cái giá thì rõ ràng: canvas không truy cập được trong suốt cửa sổ deploy, ở mọi lần deploy. Không có sự chồng lấp nào để núp sau, không có task thứ hai phục vụ traffic, và cũng không có autoscaling theo số task, vì một task thứ hai đồng nghĩa với một writer thứ hai. Mình chọn điều đó thay vì lựa chọn còn lại, là một WAL hỏng.

Nửa còn lại của thỏa thuận này là thời gian tắt. `stopTimeout: Duration.seconds(120)` cho container mức tối đa của ECS để xử lý `SIGTERM` (`ecs.ts:119`). Graceful shutdown ngừng nhận client, đóng các luồng kết nối, và công bố một checkpoint cuối, chỉ thoát với mã 0 nếu checkpoint đó thành công (`runtime-contract.md:118-123`). Nếu task bị kill thay vì tắt êm, các command đã được acknowledge vẫn phục hồi được từ WAL đã đồng bộ trên EFS, và đó chính là tính chất khiến mount bền vững đáng với cái giá về tính khả dụng của nó.

Khởi động là hình ảnh phản chiếu. Task thay thế mount lại đúng access point đó, kiểm tra snapshot được chọn trước khi bind client port, restore nó, rồi replay phần cuối WAL. Dữ liệu thiếu, hỏng hoặc không khớp sẽ làm startup thất bại chứ không gieo một database rỗng (`runtime-contract.md:114-116`). Câu lệnh health đòi `/tmp/raftdb-ready` và ghi một file probe dưới thư mục dữ liệu, nên một mount chỉ đọc hoặc không khả dụng sẽ fail health thay vì giả vờ đang hoạt động (`:105-112`). Container App chờ container RaftDb báo `HEALTHY` rồi mới khởi động.

<figure>
  <img src="/images/diagrams/raftdb-efs-devloop.svg" alt="Activity diagram of the RaftDB development and deploy loop: local named volume, immutable image publication, stop-then-start deployment onto the same EFS access point, snapshot restore and WAL replay, contrasted with the discarded ephemeral-volume path" loading="lazy">
  <figcaption>Toàn bộ vòng lặp. Nhánh bên trái là những gì EFS access point làm cho khả thi; nhánh bên phải là những gì một volume phạm vi task sẽ làm với canvas ở mỗi lần deploy.</figcaption>
</figure>

Kết quả là đúng thứ mình muốn từ đầu. Một lần deploy giờ là một bài tập phục hồi mà mình có thể ngồi xem, và canvas ở phía bên kia của nó chính là canvas mình đã để lại.

## References

- [Working with Amazon EFS access points](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html)
- [Amazon ECS: using Amazon EFS volumes](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/efs-volumes.html)
- [Amazon EFS performance](https://docs.aws.amazon.com/efs/latest/ug/performance.html)
- [Amazon ECS rolling update deployment: minimumHealthyPercent and maximumPercent](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html)
- [Docker: persist data with volumes](https://docs.docker.com/engine/storage/volumes/)
