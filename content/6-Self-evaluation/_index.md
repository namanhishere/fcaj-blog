---
title: "Self-Assessment"
date: 2026-08-12
weight: 6
chapter: false
pre: " <b> 6. </b> "
includeInReport: false
---

During my internship at **Amazon Web Services Viet Nam Company Limited** from **15/06/2026** to **12/08/2026** as part of the First Cloud AI Journey (FCAJ) Workforce Bootcamp, I had the opportunity to learn, practice, and apply the knowledge acquired in school to a real-world working environment.

I spent the full nine weeks on a single project: **awsplace**, a real-time collaborative pixel canvas deployed on AWS. The system spans a Go WebSocket server, a C++23 Raft-consensus storage engine (RaftDB), Discord OAuth2 authentication through AWS Lambda, infrastructure defined entirely as CDK TypeScript, and a CI/CD pipeline that deploys with OIDC-authenticated credentials and zero stored access keys. Through this project, I improved my skills in systems programming (Go, C++23), cloud infrastructure (AWS CDK, ECS Fargate, Lambda, API Gateway, EFS, S3, Secrets Manager), distributed systems (Raft consensus, write-ahead logging, snapshotting), and DevOps (GitLab CI, Trivy image scanning, OIDC federation).

In terms of work ethic, I maintained a daily worklog, completed every planned deliverable within its scheduled week, wrote tests alongside the code they verify, and documented architectural decisions as comments in the source rather than in a separate document. I complied with the programme's structure while adapting its twelve-week template to a nine-week internship without fabricating content for the weeks I did not work.

To objectively reflect on my internship period, I evaluate myself against the following criteria:

| No. | Criteria                            | Description                                                                                      | Good | Fair | Average |
| --- | ----------------------------------- | ------------------------------------------------------------------------------------------------ | ---- | ---- | ------- |
| 1   | **Professional knowledge & skills** | Understanding of cloud architecture, applying distributed-systems theory in practice, proficiency with Go, C++, TypeScript and AWS tooling, work quality | ☐    | ✅    | ☐       |
| 2   | **Ability to learn**                | Absorbing Raft consensus, C++23 build systems, AWS CDK concepts and OIDC federation from first principles | ✅    | ☐    | ☐       |
| 3   | **Proactiveness**                   | Designing the canvas encoding before writing a server, identifying the nibble parity constraint across four languages, writing test harnesses to enforce it | ✅    | ☐    | ☐       |
| 4   | **Sense of responsibility**         | Completing nine weeks of planned work on schedule, recording every architectural trade-off in code comments, owning the gaps in the final handover | ✅    | ☐    | ☐       |
| 5   | **Discipline**                      | Adhering to the daily worklog structure, committing code with meaningful messages, maintaining a clean Git history | ✅    | ☐    | ☐       |
| 6   | **Progressive mindset**             | Accepting that production runs a single RaftDB voter without pretending otherwise, documenting that the custom CloudWatch namespace is provisioned but dormant, naming the operational gaps rather than hiding them | ✅    | ☐    | ☐       |
| 7   | **Communication**                   | Writing a bilingual report site with diagrams compiled from PlantUML sources, documenting the why behind every architecture decision in the proposal section | ☐    | ✅    | ☐       |
| 8   | **Teamwork**                        | Working with FCAJ mentors and admin staff through the internship, coordinating with the AWS Study Group for blog publication | ☐    | ✅    | ☐       |
| 9   | **Professional conduct**            | Respecting colleagues and the programme structure, taking the internship seriously as a learning opportunity rather than a checkbox exercise | ✅    | ☐    | ☐       |
| 10  | **Problem-solving skills**          | Debugging Raft log corruption across Go, C++ and JavaScript; resolving the ECS `minHealthyPercent: 0` constraint for a single-writer WAL; designing a nibble encoding that needs to be byte-identical across four languages | ☐    | ✅    | ☐       |
| 11  | **Contribution to project/team**    | Delivering a complete, reproducible system: one `cdk deploy` produces every AWS resource, the RaftDB store survives task restarts, and the site is live at `place.namanhishere.com` | ✅    | ☐    | ☐       |
| 12  | **Overall**                         | Delivered a working full-stack application with infrastructure as code, a custom storage engine, and automated CI/CD, while honestly documenting the work that remains | ✅    | ☐    | ☐       |

### Needs Improvement

* Strengthen operational awareness: production has no CloudWatch alarms, and the RaftDB custom namespace is provisioned but dormant because no publisher exists in the tree. I should have prioritised at least a basic alarm on task health before declaring the project complete.

* Plan for redundancy from the start: the deployment strategy deliberately runs a single RaftDB voter because one writer owns the EFS write-ahead log. A three-voter cluster was documented as the target but never reached production. Future projects should have replication built in earlier rather than deferred to a later phase.

* Design for graceful degradation: when the RaftDB sidecar becomes unavailable mid-flight in `raftdb-only` mode, the application behaviour is undocumented. Every failure path should be thought through and described before the code ships.

* Improve technical communication: while the report is thorough and the code is well-commented, I could have delivered more frequent verbal updates to mentors rather than relying on the worklog as the primary communication channel.
