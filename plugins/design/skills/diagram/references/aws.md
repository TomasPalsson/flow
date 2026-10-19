# AWS architecture diagrams

Load this when the diagram shows AWS services, accounts or networks. It layers AWS's own diagram conventions on top of [type-architecture.md](type-architecture.md) (layout grammar, PaaS placement) and the connector rules in SKILL.md §6, which never relax. The official icons are what make an AWS diagram read as AWS at a glance; a box labelled "Lambda" does not.

## 1. Icons: real ones, placed by script

```
node <DIAGRAM>/scripts/aws-icon.mjs find <words>                         # which icon is it?
node <DIAGRAM>/scripts/aws-icon.mjs get <name> --x <x> --y <y> --size 48  # paste the output into the SVG
```

`<name>` is a nickname (`lambda`, `s3`, `apigw`, `ddb`, `sqs`, `sns`, `eventbridge`, `sfn`, `cognito`, `rds`, `aurora`, `ecs`, `eks`, `fargate`, `ec2`, `alb`, `nlb`, `cloudfront`, `route53`, `waf`, `bedrock`, `kinesis`, `cloudwatch`, `kms`, `secrets-manager`, `nat`, `igw`, `vpc-endpoint`, `user`, `users`, `mobile`, `internet`, group icons `aws-cloud`, `region`, `vpc`, `account`, `public-subnet`, `private-subnet`, `auto-scaling`, `datacenter`; full list in `data/aws-icons.json`), a full path (`resource/AmazonDynamoDBTable`), or search words. `get` prints a nested `<svg x y width height viewBox aria-hidden>` with its ids prefixed; paste it as-is. 809 icons (AWS Architecture Icons 01/30/2026, via the `aws-icons` npm package, cached after the first fetch).

- **Never redraw, recolour, crop, rotate or outline an AWS icon**, and never draw a fake one (an orange square with "λ"). The icon's own colour is its category colour; leave it.
- **Service icon vs resource icon.** The service icon (`architecture-service/`, coloured square) stands for the service. A resource icon (`resource/`, glyph only) stands for one specific thing: a DynamoDB *table*, an S3 *bucket*, an ALB, a NAT gateway. Pick one per node; never both for the same thing.
- **Size.** Service icons 48px (40px in tight layouts, never under 32px). Resource icons 40px. Group icons 32px (24px minimum) at the group's top-left corner. The same role is the same size across the diagram.
- **Label under the icon**, centred: the service name in the node-name font (12-13px, 600), at most two lines, then an optional mono sublabel for the specific thing (`orders-table`, `POST /orders`, `t4g.medium ×3`). Use the short service name consistently (`DynamoDB`, not `Amazon DynamoDB` in one place and `DDB` in another). The icon carries `aria-hidden`; the label is the accessible text.
- **A feature with no icon of its own** (Bedrock Knowledge Base, an Aurora reader, a Step Functions state): use its service's resource icon if `find <service>` lists one, else the parent service icon at resource size (40px), labelled with the feature's name (`Knowledge Base`, sublabel `Bedrock`).
- **No icon found** (offline, or a service newer than the set): say so in the summary and draw a plain node box with the name. Never invent an icon.

## 2. Groups: AWS's boxes, AWS's colours

Groups are containers, not nodes; they do not count toward the 9-node budget. Each is a rect with `fill="none"` (or the listed tint), a 1.5px stroke, square corners (`rx=0`), the group icon flush in its top-left corner and the group label beside the icon, 12px, in the group colour (use a darker shade if it falls under 4.5:1 on paper).

| Group | Stroke | Dash | Fill | Icon |
|---|---|---|---|---|
| AWS Cloud | `#232F3E` | solid | none | `aws-cloud` |
| AWS account | `#E7157B` | solid | none | `account` |
| Region | `#00A4A6` | `4,3` | none | `region` |
| Availability Zone | `#00A4A6` | `4,3` | none | none (text label only) |
| VPC | `#8C4FFF` | solid | none | `vpc` |
| Public subnet | `#7AA116` | solid | `#F2F6E8` | `public-subnet` |
| Private subnet | `#00A4A6` | solid | `#E6F6F7` | `private-subnet` |
| Security group | `#DD344C` | solid | none | none (label only) |
| Auto Scaling group | `#ED7100` | `4,3` | none | `auto-scaling` |
| Corporate data center | `#7D8998` | solid | none | `datacenter` |
| Generic group (a tier, a team) | `#7D8998` | `4,3` | none | none |

On a dark skin keep the strokes, drop the subnet tints to 12% opacity, and use the `aws-cloud` dark variant (`architecture-group/AWSCloudlogoDark`).

Nesting order, outside in: AWS Cloud → account (only when more than one) → Region → VPC → Availability Zone → subnet → security group / Auto Scaling group. Leave 16px between nested borders and 40px of header room under each group label so icons never touch a label.

## 3. What goes where (placement is a claim)

Where a service sits says what network it lives in. Wrong placement is a factual error, not a style slip.

- **Outside AWS Cloud:** users, browsers, phones, the internet, third-party SaaS, on-prem systems (inside a `datacenter` group).
- **Inside AWS Cloud, outside any Region:** global services: CloudFront, Route 53, IAM, WAF on CloudFront, Organizations.
- **Inside the Region, outside the VPC:** regional managed services that do not live in a VPC: S3, DynamoDB, SQS, SNS, EventBridge, Step Functions, Cognito, API Gateway (public), Lambda (unless VPC-attached), Bedrock, Kinesis, CloudWatch, Secrets Manager, KMS. This is upstream's PaaS rule: a managed service never sits inside a subnet; only its **VPC endpoint** (`vpc-endpoint`) sits in the subnet.
- **Inside the VPC:** things with an ENI in your subnets: EC2, ECS/EKS tasks and nodes, RDS/Aurora, ElastiCache, OpenSearch (VPC domain), VPC-attached Lambda, ALB/NLB, NAT gateway (public subnet), internet gateway (on the VPC border, not inside a subnet).
- **Availability Zones only when high availability is the point.** Then mirror: each AZ column holds the same subnets in the same order; the ALB spans the public subnets (draw it across the AZ boundary); RDS primary in AZ a, standby in AZ b with a dashed `SYNC` connector. Otherwise omit AZs; they double the box count and say nothing.
- **Only the services the user named or the code shows.** Do not add CloudWatch, IAM, KMS or a WAF "because real systems have them". If a needed piece is implied but unnamed (a VPC for an RDS database), draw it and list it under assumptions.

## 4. Layout

- **Request flow reads left to right** (or top to bottom on a portrait preset): client → edge (Route 53, CloudFront, WAF) → entry (API Gateway, ALB) → compute (Lambda, ECS, EC2) → data (DynamoDB, RDS, S3). Async side-paths (SQS, EventBridge, SNS → worker) run on a lower row, connectors dashed `5,4`.
- **Numbered steps** for a request walkthrough: a 20px circle badge (`accent` fill, paper numeral, mono 11px) beside each connector, and a numbered list under the diagram that says what happens at each step in one line. Badges replace long arrow labels; keep labels to protocol or verb (`HTTPS`, `INVOKE`, `PUT`, `STREAM`).
- **Accent.** The icons already bring colour, so the editorial accent goes on the one headline path (its connectors and step badges) and nowhere else. Never add category colours of your own.
- **Budget.** Nine service icons per view, groups excluded. A system with more becomes an overview (one icon per tier) plus detail diagrams (the network, the data pipeline), each standalone.
- **Connectors attach to the icon's edge** (the 48px square), not to the label below it; leave the label clear of every line.

## 5. Checks specific to AWS

Before the SKILL.md §9 gate, confirm:

- [ ] Every AWS service is a real icon from `aws-icon.mjs`, unmodified, at one consistent size per role.
- [ ] Each service sits in the right container (§3); no managed service inside a subnet.
- [ ] Group strokes, dashes and icons match the §2 table; group labels clear of icons and nodes.
- [ ] No service the brief did not name, except listed assumptions.
- [ ] Step badges (if any) match the numbered list under the diagram, one to one.
- [ ] Inlined icons carry `aria-hidden`; the figure's `<desc>` names the flow in one sentence.
