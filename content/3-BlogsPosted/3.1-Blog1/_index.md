---
title: "Bitmask and case study"
date: 2024-01-01
weight: 1
chapter: false
pre: " <b> 3.1. </b> "
includeInReport: false
---

# Bitmask and case study

## TL/DR

I want to talk about bitmasks — not the CS 101 definition, but how they show up in real systems and why you should care. If you have ever typed `chmod 755`, you have used a bitmask without knowing it. Discord uses a single 64-bit integer to check 50+ permissions per request. r/place packed its entire 4-million-pixel canvas into 4 MB of memory. The idea is simple: each bit in an integer is an independent on/off switch. Setting a flag is `|`, checking is `&`, removing is `& ~`. One integer replaces 64 boolean columns. I wrote some runnable Node.js code with PostgreSQL and DynamoDB to back this up — it is in `demos/bitmask-demo/` if you want to follow along.

---

## What is a bitmask

Every integer is just bits. `7` in binary is `0111` — three 1s, one 0. A bitmask treats each bit position as a separate flag.

Here is the one pattern you need to remember: `1 << n` gives you exactly one bit set at position `n`. That is your flag.

```
READ   = 1 << 0   // 0b0001 = 1
WRITE  = 1 << 1   // 0b0010 = 2
EXEC   = 1 << 2   // 0b0100 = 4
DELETE = 1 << 3   // 0b1000 = 8
```

Now you have four moves and that is basically it:

```
let perms = 0;

perms |= READ;                    // Set: turn READ on
perms |= WRITE;                   // Set another → perms = 3

(perms & READ) === READ           // Check: true
(perms & DELETE) === DELETE       // Check: false

perms &= ~WRITE;                  // Remove WRITE

perms ^= DELETE;                  // Toggle DELETE (off → on)
perms ^= DELETE;                  // Toggle again (on → off)
```

You can pre-compose masks for roles. Instead of checking flags one by one, you check against a combined mask:

```
const ADMIN  = READ | WRITE | EXEC | DELETE;   // 15
const EDITOR = READ | WRITE | DELETE;           // 11
const VIEWER = READ;                            // 1

// Does user have ALL of these?
(userPerms & (READ | WRITE)) === (READ | WRITE)

// Does user have ANY of these?
(userPerms & (WRITE | DELETE)) !== 0
```

The storage argument is the thing that sold me. For 1 million users with 64 feature flags each:

- 64 boolean columns → 64 MB
- 1 `BIGINT` bitmask → 8 MB

That is 8× less. One indexed column instead of 64. Your queries, your cache, your network transfers — all smaller.

One gotcha: JavaScript `Number` is only safe up to 53 bits. Discord's permission system uses 64 bits, so you need `BigInt`:

```
const CREATE = 1n << 0n;
const KICK   = 1n << 1n;
const ADMIN  = 1n << 3n;

let modPerms = CREATE | KICK;
(modPerms & ADMIN) === ADMIN   // BigInt comparison
```

---

## Using bitmasks in PostgreSQL

Postgres handles bitwise operations on integers natively — no extensions, no weird functions.

Create a table with a `BIGINT` column for your permission mask:

```
CREATE TABLE users (
    id      SERIAL PRIMARY KEY,
    name    TEXT NOT NULL,
    role    TEXT NOT NULL,
    perms   BIGINT NOT NULL DEFAULT 0
);
```

From there, the SQL is what you would expect:

```
-- Set a flag
UPDATE users SET perms = perms | 4 WHERE name = 'alice';

-- Remove a flag
UPDATE users SET perms = perms & ~8 WHERE name = 'alice';

-- Toggle (XOR is # in Postgres, not ^)
UPDATE users SET perms = perms # 16 WHERE name = 'alice';

-- Find users with WRITE
SELECT * FROM users WHERE (perms & 2) = 2;

-- Find users with READ AND DELETE
SELECT * FROM users WHERE (perms & 9) = 9;

-- Find users with EXEC OR ADMIN
SELECT * FROM users WHERE (perms & 20) != 0;
```

`BIT_COUNT()` counts how many flags are active. Cast to `bit(n)` for a readable binary display:

```
SELECT name, perms::bit(6), BIT_COUNT(perms::bit(6)) FROM users;

 name  | perms  | bit_count
-------+--------+-----------
 alice | 111111 | 6
 bob   | 001011 | 3
 carol | 000001 | 1
```

Here is the power move: partial indexes. This turns a full table scan into an index scan when you frequently query a specific flag:

```
CREATE INDEX idx_has_write ON users (id) WHERE (perms & 2) = 2;
```

Without this, `WHERE (perms & 2) = 2` scans every row. With it, Postgres reads only the matching rows. Same idea as a filtered index.

---

## Using bitmasks in DynamoDB

DynamoDB does not support bitwise operators in expressions at all. No `(perms & 2) = 2` in a `ConditionExpression`. This tripped me up the first time I tried it.

The workaround is straightforward: store the mask as a `Number`, retrieve the item, and check the bits in your app:

```
const { Item } = await client.send(new GetCommand({
  TableName: "Users",
  Key: { id: "alice" },
}));

const hasWrite = (Item.perms & WRITE) === WRITE;
```

Granting and revoking works fine — you compute the new value and `SET` it:

```
const newPerms = currentPerms | AUDIT;
await client.send(new UpdateCommand({
  TableName: "Users",
  Key: { id: "eve" },
  UpdateExpression: "SET perms = :new",
  ExpressionAttributeValues: { ":new": newPerms },
}));
```

The annoying part is query-time filtering. Since you cannot write `WHERE (perms & 2) = 2`, you have three choices: scan everything and filter in JS (fine for small tables), add pre-computed boolean attributes like `has_write: true` and use them in GSI keys, or keep a separate sparse table for query-time lookups while the bitmask lives in the user record for compact transport.

The storage win is still there. One `Number` attribute = up to 53 flags versus 53 separate `BOOL` attributes eating item size and write capacity.

Bottom line: Postgres lets the database do the heavy lifting. DynamoDB makes you move the bit-checking into your application code. But the bitmask itself — the integer, the flag constants, the `&`/`|`/`~` — stays exactly the same in both cases.

---

## Case study: Linux file permissions

Every file on your machine has a 9-bit permission mask. It is been this way since Unix V1 in 1971. Three triplets of three bits: owner, group, others.

```
Owner   Group   Others
 r w x   r w x   r w x
 4 2 1   4 2 1   4 2 1
```

Read is 4, write is 2, execute is 1. `chmod 755` means:

```
7  5  5
rwx r-x r-x

Owner:  read, write, execute   (4+2+1 = 7)
Group:  read, execute           (4+1   = 5)
Others: read, execute           (4+1   = 5)
```

Under the hood, `sys/stat.h` maps these to constants:

```
#define S_IRUSR  00400   // owner read     (1 << 8)
#define S_IWUSR  00200   // owner write    (1 << 7)
#define S_IXUSR  00100   // owner execute  (1 << 6)
#define S_IRGRP  00040   // group read     (1 << 5)
#define S_IWGRP  00020   // group write    (1 << 4)
#define S_IXGRP  00010   // group execute  (1 << 3)
#define S_IROTH  00004   // others read    (1 << 2)
#define S_IWOTH  00002   // others write   (1 << 1)
#define S_IXOTH  00001   // others execute (1 << 0)
```

A `stat` call gives you `st_mode` as a 16-bit integer. The bottom 9 bits are permissions. Checking if the owner can write is literally:

```
if (st.st_mode & S_IWUSR) { ... }
```

This is the oldest bitmask still in active use — over 50 years — and it has never needed a redesign. When a permission system lasts half a century with one integer and three bitwise operators, the approach works.

---

## Case study: Discord permissions

Discord's permission system is probably the largest real-world bitmask deployment most developers interact with. Every role in a server stores permissions as a 64-bit integer. The API serializes it as a string because JavaScript `Number` cannot safely hold values above 2^53.

Each permission is `1 << n`. A few of them:

```
CREATE_INSTANT_INVITE = 1 << 0
KICK_MEMBERS         = 1 << 1
BAN_MEMBERS          = 1 << 2
ADMINISTRATOR        = 1 << 3
VIEW_CHANNEL         = 1 << 10
SEND_MESSAGES        = 1 << 11
MANAGE_MESSAGES      = 1 << 13
```

Building a member role is just OR-ing:

```
const member = VIEW_CHANNEL | SEND_MESSAGES | ATTACH_FILES | EMBED_LINKS;

(member & SEND_MESSAGES) === SEND_MESSAGES   // true
(member & ADMINISTRATOR) === ADMINISTRATOR   // false
```

The interesting part is how Discord layers **overwrites** on top. A channel can override guild-level permissions with `allow` and `deny` masks. The resolution order is:

1. Start with `@everyone` base permissions
2. OR in all of the user's role permissions
3. If `ADMINISTRATOR` is set, stop — grant everything
4. Apply channel `@everyone` deny → clear those bits
5. Apply channel `@everyone` allow → set those bits
6. Apply role-specific overrides (deny first, then allow)
7. Apply member-specific overrides (deny first, then allow)

In pseudocode, each step is just:

```
permissions &= ~overwrite.deny;
permissions |=  overwrite.allow;
```

The whole thing resolves in a handful of `&` and `|` operations. No database query. No recursion. No network call. Just CPU instructions. For a platform serving millions of real-time permission checks per second, that matters.

One thing I learned the hard way: because the integer can exceed JavaScript's safe range, Discord returns permissions as a string like `"66321471"`. Parse it as `BigInt`:

```
const perms = BigInt("66321471");
const canKick = (perms & (1n << 1n)) === (1n << 1n);
```

---

## Case study: r/place canvas management

r/place was Reddit's collaborative pixel art experiment. In 2022, the canvas was 2000×2000 pixels — 4 million pixels total. Millions of users placed pixels simultaneously, and the system had to handle thousands of writes per second while serving the real-time canvas state globally.

A naive database schema would store each pixel as a row: `x`, `y`, `color`, `user_id`, `timestamp`, `is_protected`, `placed_by_mod`, and so on. Seven fields per pixel, multiplied by four million, with real-time replication. That balloons fast.

Here is the bitmask approach — pack everything into one byte per pixel:

```
bit 0-4:  color index   (5 bits → 32-color palette)
bit 5:    is_protected  (moderator-locked, cannot overwrite)
bit 6:    placed_by_mod (placed by a moderator, takes priority)
bit 7:    reserved
```

That is 1 byte × 4,000,000 = **4 MB** for the entire canvas. Compare to ~160 MB for a relational approach. A 40× reduction.

At the application level, reading and writing pixels becomes:

```
function getColor(packed) {
  return packed & 0x1F;  // bottom 5 bits
}

function isProtected(packed) {
  return (packed & 0x20) !== 0;  // bit 5
}

function setPixel(packed, color) {
  return (packed & 0xE0) | (color & 0x1F);  // keep top 3 bits, swap color
}
```

After the event ended, the community built their own r/place clones. The most common storage choice was Redis bitfields:

```
BITFIELD canvas SET u8 #(y * width + x) #packed_value
```

One command, one pixel, constant time. No rows, no columns, no serialization — just direct memory access at an offset. Shard the canvas across a Redis Cluster and you can handle millions of placements per minute.

I find this the most elegant example of bitmasks in the wild. When your data fits in a handful of bits, keeping it a handful of bits eliminates an entire class of overhead.

---

## Wrapping up

That is pretty much it. Bitmasks are not complicated — just an integer where you care about which bits are on. But once you start seeing them, you will notice them everywhere: file permissions, network flags, game state, feature flags, protocol headers.

The companion code is in `demos/bitmask-demo/`. Four Node.js scripts that run against real PostgreSQL and DynamoDB:

```sh
cd demos/bitmask-demo
docker compose up -d
npm install
npm run basics        # pure JS, no DB needed
npm run postgresql    # bitwise queries with partial indexes
npm run dynamodb      # app-level bit-checking
npm run permissions   # same logic, both databases
```

If your database has native bitwise operators (Postgres, MySQL, SQLite), lean into them — server-side filtering with partial indexes is a superpower. If it does not (DynamoDB, MongoDB), the bitmask still wins on storage; you just do the checking in your application.

And if you ever need more than 53 flags in JavaScript, `BigInt` has your back. Just serialize to strings like Discord does.
