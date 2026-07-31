---
title : "Lớp Cơ sở dữ liệu DynamoDB"
date : 2024-01-01
weight : 3
chapter : false
pre : " <b> 5.3.3 </b> "
---

#### Bảng DynamoDB

Module cơ sở dữ liệu (**createDatabase**) định nghĩa **4 bảng DynamoDB** sử dụng construct **TableV2** (API DynamoDB CDK được khuyến nghị). Tất cả các bảng sử dụng **on-demand billing** (**Billing.onDemand()**) — không có dung lượng được cung cấp, trả tiền theo yêu cầu.

```typescript
export function createDatabase(scope: Construct): DatabaseOutput {
  const configTable = new dynamodb.TableV2(scope, 'ConfigTable', {
    partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
    sortKey: { name: 'SK', type: dynamodb.AttributeType.STRING },
    billing: dynamodb.Billing.onDemand(),
  });

  const bansTable = new dynamodb.TableV2(scope, 'BansTable', {
    partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
    sortKey: { name: 'SK', type: dynamodb.AttributeType.STRING },
    billing: dynamodb.Billing.onDemand(),
  });

  const milestonesTable = new dynamodb.TableV2(scope, 'MilestonesTable', {
    partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
    sortKey: { name: 'SK', type: dynamodb.AttributeType.STRING },
    billing: dynamodb.Billing.onDemand(),
    globalSecondaryIndexes: [
      {
        indexName: 'TriggerAtIndex',
        partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
        sortKey: { name: 'triggerAt', type: dynamodb.AttributeType.NUMBER },
        projectionType: dynamodb.ProjectionType.ALL,
      },
    ],
  });

  const historyTable = new dynamodb.TableV2(scope, 'HistoryTable', {
    partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
    sortKey: { name: 'SK', type: dynamodb.AttributeType.STRING },
    billing: dynamodb.Billing.onDemand(),
    globalSecondaryIndexes: [
      {
        indexName: 'XOriginalIndex',
        partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
        sortKey: { name: 'x_original', type: dynamodb.AttributeType.NUMBER },
        projectionType: dynamodb.ProjectionType.INCLUDE,
        nonKeyAttributes: ['y_original', 'offset_x', 'offset_y', 'colorIndex'],
      },
    ],
  });

  return { configTable, bansTable, milestonesTable, historyTable };
}
```

#### Thiết kế Bảng

Tất cả bốn bảng chia sẻ một mẫu thiết kế chung: **khóa chính tổng hợp** bao gồm **PK** (Partition Key, STRING) và **SK** (Sort Key, STRING). Đây là **thiết kế bảng đơn giản hóa** — mỗi loại thực thể sử dụng tiền tố PK riêng biệt thay vì nằm trong các cột riêng biệt.

![Sơ đồ Thiết kế Bảng DynamoDB](/images/5-Workshop/5.3-CDK-Project-Structure/dynamodb-tables.png)

#### Chi tiết Bảng

| Bảng | Khóa chính | GSI | Mục đích |
|------|------------|-----|----------|
| **Config** | PK (STRING), SK (STRING) | Không | Cấu hình đơn: kích thước bảng, cooldown, offset toàn cục |
| **Bans** | PK (STRING), SK (STRING) | Không | Cấm người dùng/IP |
| **Milestones** | PK (STRING), SK (STRING) | TriggerAtIndex | Mở rộng bảng theo lịch, sắp xếp theo triggerAt |
| **History** | PK (STRING), SK (STRING) | XOriginalIndex | Bản ghi đặt pixel với tọa độ gốc |

#### Mẫu Khóa Mục

Mỗi bảng sử dụng giá trị khóa cụ thể để tổ chức dữ liệu:

| Bảng | PK | SK | Ví dụ |
|------|-----|-----|-------|
| Config | CONFIG | SINGLETON | **{PK: "CONFIG", SK: "SINGLETON", width: 960, height: 540}** |
| Bans | BAN#user#\<discordId\> | BAN | **{PK: "BAN#user#123456789", SK: "BAN"}** |
| Bans | BAN#ip#\<address\> | BAN | **{PK: "BAN#ip#192.168.1.1", SK: "BAN"}** |
| Milestones | MILESTONE | \<ulid\> | **{PK: "MILESTONE", SK: "01ARZ3NDEK...", triggerAt: 1700000000}** |
| History | HISTORY | ts#\<epoch_ms\>#\<uuid\> | **{PK: "HISTORY", SK: "ts#1700000000000#abc..."}** |

#### Chỉ mục Phụ Toàn cục (GSIs)

**Milestones — TriggerAtIndex:**
- **Mục đích**: Truy vấn milestones được sắp xếp theo thời gian kích hoạt (triggerAt), tăng dần. Bộ lập lịch thăm dò chỉ mục này để tìm milestones chưa kích hoạt có thời gian kích hoạt đã qua.
- **Projection**: ALL — trả về mục milestone đầy đủ, bao gồm direction, amount, label và trạng thái fired.
- **Mẫu truy vấn**: **PK = "MILESTONE"** với triggerAt sắp xếp tăng dần (**ScanIndexForward: true**).

**History — XOriginalIndex:**
- **Mục đích**: Truy vấn hình chữ nhật hiệu quả trên lịch sử pixel. Lọc theo phạm vi x_original (điều kiện khóa trên sort key) và phạm vi y_original (biểu thức lọc).
- **Projection**: INCLUDE với các thuộc tính không phải khóa cụ thể (y_original, offset_x, offset_y, colorIndex) — giảm thiểu dung lượng đọc bằng cách chỉ chiếu các trường cần thiết cho truy vấn hình chữ nhật.
- **Mẫu truy vấn**: **PK = "HISTORY" AND x_original BETWEEN x1 AND x2** với bộ lọc **y_original BETWEEN y1 AND y2**.

#### Tại sao sử dụng On-Demand Billing?

- **Config, Bans, Milestones**: Lưu lượng rất thấp (chỉ thao tác quản trị). Dung lượng được cung cấp sẽ lãng phí tiền.
- **History**: Lưu lượng ghi thay đổi tùy thuộc vào hoạt động người dùng. On-demand hấp thụ các đợt tăng đột biến đặt pixel mà không bị điều tiết.

#### Quan trọng: Không TTL, Không Bảng Canvas

Lưu ý rằng:
- **Không TTL** được cấu hình trên bất kỳ bảng nào. Cooldowns được quản lý trong bộ nhớ bởi máy chủ Go, không phải qua DynamoDB TTL.
- **Không có bảng Canvas**. Dữ liệu pixel canvas được lưu trữ dưới dạng blob nhị phân trong S3, sử dụng **đóng gói nibble 4-bit** (2 pixel mỗi byte). DynamoDB có giới hạn mục 400 KB, không đủ cho canvas có thể phát triển đến 32 MiB (8000×8000 ở 4bpp).
